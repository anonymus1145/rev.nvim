-- Module -> Public interface for the file
local M = {}

M.setup = function()
  -- do stuff
end

--- Takes some lines and parses them
--- @param lines string[]: The lines in the buffer
--- @return string[] | nil: Formatted diff as a markdown code block, or nil if no changes detected.
local parse_diff = function(lines)
  local has_change = false
  local diff_output = {
    '### Git Diff Analysis',
    '```diff',
  }

  for _, line in ipairs(lines) do
    table.insert(diff_output, line)
    if not has_change and line:find('^[+-][^+-]') then
      has_change = true
    end
  end

  table.insert(diff_output, '```')

  -- Check if we actually found any diffs/slides
  if #diff_output <= 2 and not has_change then
    return nil
  end

  return diff_output
end

--- Takes the prompt and calls the llm
--- @param prompt string: The lines in the buffer
--- @return string | nil: Final parsed and ordered version
local llm_call = function(prompt, callback)
  local api_key = os.getenv('REVNVIM_API_KEY')
  local llm_model = os.getenv('REVNVIM_MODEL')
  local url = os.getenv('REVNVIM_URL')

  if
    api_key == nil
    or api_key == ''
    or llm_model == nil
    or llm_model == ''
    or url == nil
    or url == ''
  then
    vim.notify('Missing config environment variables.', vim.log.levels.ERROR)
    return callback(nil)
  end

  local request_body = {
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
    model = llm_model,
    stream = false,
  }

  -- This handles all the "safe_prompt".
  -- It turns your Lua table into a perfectly formatted JSON string, handling quotes and \n characters automatically
  local json_payload = vim.json.encode(request_body)

  -- Add sensitive header in an config file
  local uv = vim.uv or vim.loop
  local config_path = vim.fn.tempname()
  local config_content = { string.format('header = "Authorization: Bearer %s"', api_key) }

  local fd = uv.fs_open(config_path, 'w', 384)

  if fd then
    uv.fs_write(fd, config_content, 0)
    uv.fs_close(fd)
  else
    vim.notify('Could not create secure file.', vim.log.levels.ERROR)
  end

  vim.system({
    'curl',
    '-s',
    '-m',
    '120',
    '-K',
    config_path,
    '-X',
    'POST',
    '-H',
    'Content-Type: application/json',
    url,
    '--data-binary',
    '@-',
  }, {
    stdin = json_payload,
    text = true,
  }, function(obj)
    -- ALWAYS cleanup the temp file immediately async
    uv.fs_unlink(config_path)
    -- This runs in a background thread!
    -- We must use vim.schedule to talk to Neovim again.
    vim.schedule(function()
      if obj.code ~= 0 then
        vim.notify('API Request failed: ' .. (obj.stderr or 'Unknown error'), vim.log.levels.ERROR)
        return callback(nil)
      end

      local ok, answer = pcall(vim.json.decode, obj.stdout)
      if not ok or not answer.choices or not answer.choices[1] or not answer.choices[1].message then
        vim.notify('Failed to parse API response.', vim.log.levels.ERROR)
        return callback(nil)
      end

      local text = answer.choices[1].message.content
      callback(text)
    end)
  end)
end

--- Takes the parses diff and prompt the LLM to review it
--- @param git_diff string: The lines in the buffer
--- @return string[] | nil: Final parsed and ordered version
local run_review = function(git_diff, final_callback)
  local uv = vim.uv or vim.loop
  local path = vim.fn.stdpath('config') .. '/REVNVIM.md'

  -- 1. Open the file
  uv.fs_open(path, 'r', 438, function(err, fd) -- uv.fs_open returns an integer ID
    if err then
      vim.schedule(
        function() -- vim.schedule: Libuv callbacks run outside of Neovim’s main loop, ensures the code runs safely back on the main thread
          vim.notify('REVNVIM: Configuration file not found at ' .. path, vim.log.levels.ERROR)
          final_callback(nil)
        end
      )
      return
    end

    -- 2. Get file stats to know the size
    uv.fs_fstat(fd, function(err, stat)
      if err or not stat or stat.size > (100 * 1024) then
        uv.fs_close(fd)
        vim.schedule(function()
          vim.notify('Failed to stat config file', vim.log.levels.ERROR)
          final_callback(nil)
        end)
        return
      end

      -- 3. Read the entire file content
      uv.fs_read(fd, stat.size, 0, function(err, data)
        -- 4. Always close the file descriptor
        uv.fs_close(fd)

        vim.schedule(function()
          if err or not data then
            vim.notify('Error during REVNVIM.md reading...', vim.log.levels.ERROR)
            return final_callback(nil)
          end

          -- Success!
          local diff_len = string.len(git_diff)
          -- 1 token aprox 4 chars
          local max_diff_limit = 100000 * 4

          if diff_len > max_diff_limit then
            vim.notify(
              'Exceeded the maximum number of tokens in a request...',
              vim.log.levels.ERROR
            )
            return final_callback(nil)
          end

          local context = '# Do a code review'
          local input = context .. '\n\n' .. data .. '\n\n' .. git_diff

          llm_call(input, function(review)
            if not review then
              return final_callback(nil)
            end

            -- Send the final result back to the UI
            final_callback(vim.split(review, '\n'))
          end)
        end)
      end)
    end)
  end)
end

local timer = nil

local start_spinner = function(buf)
  if timer then
    timer:close()
  end

  local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
  local frame = 1
  timer = vim.uv.new_timer()

  if not timer then
    return nil
  end

  timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      -- Safety check: stop if the buffer was closed by the user
      if not vim.api.nvim_buf_is_valid(buf) then
        timer:stop()
        timer:close()
        return
      end

      local msg =
        string.format(' %s Gathering insights from your LLM Model...', spinner_frames[frame])
      vim.api.nvim_buf_set_lines(buf, 2, 3, false, { msg })
      frame = (frame % #spinner_frames) + 1
    end)
  )

  return timer
end

M.start_review = function(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0
  -- Get the file path associated with the buffer.
  local file_path = vim.api.nvim_buf_get_name(opts.bufnr)

  if file_path == '' then
    return vim.notify('Buffer has no file name', vim.log.levels.ERROR)
  end

  -- Run git diff to return the changes
  vim.system({ 'git', 'diff', '-W', '--minimal' }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        vim.notify('Git diff failed: ' .. (obj.stderr or ''), vim.log.levels.ERROR)
        return
      end

      local lines = vim.split(obj.stdout, '\n')
      local diff_lines = parse_diff(lines)

      if not diff_lines or #diff_lines <= 1 then
        vim.notify('No changes found to review.', vim.log.levels.INFO)
        return
      end

      -- Concat the diff in an string
      local final_diff = table.concat(diff_lines, '\n')

      -- Force vertical split to the right
      vim.cmd('rightbelow vsplit')

      -- Create a new temporary buffer
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)

      -- Modern option setting
      vim.bo[buf].filetype = 'markdown'
      vim.bo[buf].buftype = 'nofile' -- Keeps it from asking to save on exit
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# Code Review', '', 'Loading review...' })

      local spinner_timer = start_spinner(buf)

      -- Trigger the async chain
      run_review(final_diff, function(review_lines)
        if spinner_timer then
          spinner_timer:stop()
          spinner_timer:close()
        end

        if not review_lines then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Error: Review failed.' })
          return
        end

        -- Update the buffer with the final result
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, review_lines)
        vim.notify('Review complete!', vim.log.levels.INFO)
      end)
    end)
  end)
end

vim.keymap.set('n', '<leader>rv', function()
  M.start_review({ bufnr = vim.api.nvim_get_current_buf() })
end, { desc = 'Start code review' })

-- Testing locally don't add it in the code review
-- M.start_review()

return M
