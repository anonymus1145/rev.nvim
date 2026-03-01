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
  local api_key = os.getenv('GEMINI_API_KEY')
  local llm_model = os.getenv('LLM_MODEL')

  if not api_key or not llm_model then
    vim.notify('Missing API Key or Model environment variables.', vim.log.levels.ERROR)
    return callback(nil)
  end

  local request_body = {
    contents = {
      {
        parts = {
          { text = prompt },
        },
      },
    },
  }

  -- This handles all the "safe_prompt".
  -- It turns your Lua table into a perfectly formatted JSON string, handling quotes and \n characters automatically
  local json_payload = vim.json.encode(request_body)

  local url = string.format(
    'https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent',
    llm_model
  )

  vim.system({
    'curl',
    '-s',
    '-X',
    'POST',
    '-H',
    'x-goog-api-key: ' .. api_key,
    '-H',
    'Content-Type: application/json',
    url,
    '--data-binary',
    '@-',
  }, {
    stdin = json_payload,
    text = true,
  }, function(obj)
    -- This runs in a background thread!
    -- We must use vim.schedule to talk to Neovim again.
    vim.schedule(function()
      if obj.code ~= 0 then
        vim.notify('API Request failed: ' .. (obj.stderr or 'Unknown error'), vim.log.levels.ERROR)
        return callback(nil)
      end

      local ok, answer = pcall(vim.json.decode, obj.stdout)
      if not ok or not answer.candidates then
        vim.notify('Failed to parse API response.', vim.log.levels.ERROR)
        return callback(nil)
      end

      local text = answer.candidates[1].content.parts[1].text
      callback(text)
    end)
  end)
end

--- Takes the parses diff and prompt the LLM to review it
--- @param git_diff string: The lines in the buffer
--- @return string[] | nil: Final parsed and ordered version
local chain_call = function(git_diff, final_callback)
  local initial_prompt =
    'Create and return only the prompt for doing a code review using a file that has the old(-) and new(+) changes'

  -- Call 1: Get the generated prompt
  llm_call(initial_prompt, function(generated_prompt)
    if not generated_prompt then
      return final_callback(nil)
    end

    local input = generated_prompt .. '\n\n' .. git_diff

    -- Call 2: Get the actual review
    llm_call(input, function(review)
      if not review then
        return final_callback(nil)
      end

      -- Send the final result back to the UI
      final_callback(vim.split(review, '\n'))
    end)
  end)
end

local start_spinner = function(buf)
  local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
  local frame = 1
  local timer = vim.uv.new_timer()

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
    return print('Buffer has no file name')
  end

  -- Run git diff to return the changes
  local diff_output = vim.system({ 'git', 'diff', '-U20' }, { text = true }):wait()
  local lines = vim.split(diff_output.stdout, '\n')

  -- Call the parser
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
  chain_call(final_diff, function(review_lines)
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
end

vim.keymap.set('n', '<leader>rv', function()
  M.start_review({ bufnr = vim.api.nvim_get_current_buf() })
end, { desc = 'Start code review' })

return M
