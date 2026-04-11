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

  local curl_config = table.concat({
    'header = "Authorization: Bearer ' .. api_key .. '"',
    'header = "Content-Type: application/json"',
    'data-binary = @-',
  }, '\n')

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

  -- It turns your Lua table into a perfectly formatted JSON string, handling quotes and \n characters automatically
  local json_payload = vim.json.encode(request_body)

  local status, job = pcall(vim.system, {
    'curl',
    '-s',
    '-m',
    '120',
    '-K-',
    url,
  }, {
    stdin = curl_config .. '\n' .. json_payload,
    text = true,
  }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        vim.notify('API Request failed: ' .. (obj.stderr or 'Unknown error'), vim.log.levels.ERROR)
        return callback(nil)
      end

      local ok, answer = pcall(vim.json.decode, obj.stdout)

      if not ok or not answer.choices or not answer.choices[1] or not answer.choices[1].message then
        if answer.error then
          return callback(answer.error)
        end
        vim.notify('API request failed', vim.log.levels.ERROR)
        return callback(nil)
      end

      -- Deep check the table structure
      local content = vim.tbl_get(answer, 'choices', 1, 'message', 'content')

      if not content then
        vim.notify('API response structure unexpected.', vim.log.levels.WARN)
        return callback(nil)
      end

      callback(content)
    end)
  end)

  if not status then
    vim.notify('Failed to execute curl: ' .. tostring(job), vim.log.levels.ERROR)
    return callback(nil)
  end
end

--- Takes the parses diff and prompt the LLM to review it
--- @param git_diff string: The buffer number
--- @return string[] | nil: Final parsed and ordered version
local run_review = function(git_diff, final_callback)
  local path = vim.fn.stdpath('config') .. '/REVNVIM.md'

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    vim.notify('REVNVIM: Configuration file not found at ' .. path, vim.log.levels.ERROR)
    return final_callback(nil)
  end

  local config = table.concat(lines, '\n')

  local MAX_TOKENS = 100000 -- Model context window limit
  local CHARS_PER_TOKEN = 4 -- Conservative heuristic
  local MAX_INPUT_CHARS = MAX_TOKENS * CHARS_PER_TOKEN

  local context = '# Do a code review'
  local input = table.concat({ context, config, git_diff }, '\n\n')

  if #input > MAX_INPUT_CHARS then
    vim.notify('Exceeded the maximum number of tokens in a request...', vim.log.levels.ERROR)
    return final_callback(nil)
  end

  llm_call(input, function(review)
    if not review then
      return final_callback(nil)
    end

    return final_callback(vim.split(review, '\n'))
  end)
end

--- Takes the buf and create a spinner_frame
--- @param buf integer: The lines in the buffer
--- @return uv.uv_timer_t | nil: The timer object
local start_spinner = function(buf)
  local timer = vim.uv.new_timer()

  if not timer then
    return nil
  end

  local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
  local frame = 1

  timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        if not timer:is_closing() then
          timer:stop()
          timer:close()
          return
        end
      end

      local msg =
        string.format(' %s Gathering insights from your LLM Model...', spinner_frames[frame])

      local ok = pcall(vim.api.nvim_buf_set_lines, buf, 2, 3, false, { msg })

      if not ok then
        if not timer:is_closing() then
          timer:stop()
          timer:close()
        end
        return
      end

      frame = (frame % #spinner_frames) + 1
    end)
  )
  return timer
end

--- Runs the review with the provided code
--- @param to_review string: The lines to be reviewed
local run = function(to_review)
  vim.cmd('rightbelow vsplit')

  local review_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, review_buf)

  -- Modern option setting
  vim.bo[review_buf].filetype = 'markdown'
  vim.bo[review_buf].buftype = 'nofile'
  vim.bo[review_buf].bufhidden = 'wipe'

  vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, { '# Code Review', '', 'Loading review...' })

  local spinner_timer = start_spinner(review_buf)

  if not spinner_timer then
    vim.notify('REVNVIM: Error during starting the spinner', vim.log.levels.ERROR)
    return
  end

  local ok, answer = pcall(run_review, to_review, function(review_lines)
    if spinner_timer and not spinner_timer:is_closing() then
      spinner_timer:stop()
      spinner_timer:close()
    end

    if not vim.api.nvim_buf_is_valid(review_buf) then
      return
    end

    if not review_lines then
      vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, { 'Error: Review failed.' })
      return
    end

    vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, review_lines)
  end)

  if not ok or not answer then
    if spinner_timer and not spinner_timer:is_closing() then
      spinner_timer:stop()
      spinner_timer:close()
    end
    return
  end
end

M.start_review = function(opts)
  opts = opts or {}

  vim.system({ 'git', 'diff', '-W' }, { text = true }, function(obj)
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

      local final_diff = table.concat(diff_lines, '\n')

      local ok, answer = pcall(run, final_diff)
      if not ok or not answer then
        vim.notify('Issue on run function', vim.log.levels.INFO)
      end
    end)
  end)
end

-- Does code review for that specific function where the breakpoint is set
M.breakpoint_review = function(opts)
  opts = opts or {}

  local status_dap, dap_bp = pcall(require, 'dap.breakpoints')
  if not status_dap then
    vim.notify('Error: nvim-dap is not installed or loaded.', vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()

  local all_breakpoints = dap_bp.get()
  local buffer_breakpoints = all_breakpoints[bufnr]

  if not buffer_breakpoints or #buffer_breakpoints < 2 or #buffer_breakpoints > 2 then
    vim.notify('You need only 2 breakpoints in this file to define a range.', vim.log.levels.ERROR)
    return
  end

  local lines = {}
  for _, bp in ipairs(buffer_breakpoints) do
    table.insert(lines, bp.line)
  end
  table.sort(lines)

  local start_line = lines[1]
  local end_line = lines[2]

  local code_block = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local final_block = table.concat(code_block, '\n')

  local ok, answer = pcall(run, final_block)
  if not ok or not answer then
    vim.notify('Issue on run function', vim.log.levels.INFO)
  end

  -- setTimeout
  --  vim.defer_fn(function()
  --  if spinner_timer and not spinner_timer:is_closing() then
  --  spinner_timer:stop()
  --spinner_timer:close()
  --  end
  --  vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, code_block)
  --end, 2000)
end

vim.keymap.set('n', '<leader>rv', function()
  M.start_review()
end, { desc = 'Start code review' })

vim.keymap.set('n', '<leader>rb', function()
  M.breakpoint_review()
end, { desc = 'Start breakpoints block review' })
M.breakpoint_review()
return M
