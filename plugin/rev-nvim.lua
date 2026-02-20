-- Module -> Public interface for the file
local M = {}

M.setup = function()
  -- do stuff
end

--- Takes some lines and parses them
--- @param lines string[]: The lines in the buffer
--- @return string[] | nil: Final parsed and ordered version
local parse_diff = function(lines)
  local added_lines = { '#Added Changes' }
  local removed_lines = { '#Removed changes' }

  local add_separator = '^%+'
  local removed_separator = '^%-'

  for _, line in ipairs(lines) do
    if line:find(add_separator) then
      table.insert(added_lines, line)
    elseif line:find(removed_separator) then
      table.insert(removed_lines, line)
    end
  end

  -- Check if we actually found any diffs/slides
  if #added_lines <= 1 and #removed_lines <= 2 then
    return nil
  end

  local diff = added_lines
  vim.list_extend(diff, removed_lines)

  return diff
end

--- Takes the prompt and calls the llm
--- @param prompt string: The lines in the buffer
--- @return string | nil: Final parsed and ordered version
local llm_call = function(prompt)
  local api_key = os.getenv('GEMINI_API_KEY')
  if not api_key then
    vim.notify('Error: GEMINI_API_KEY is not set.', vim.log.levels.ERROR)
    return nil
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

  -- Write payload to a temporary file
  local tmp_file = vim.fn.tempname() .. '.json'
  local f = io.open(tmp_file, 'w')
  if not f then
    vim.notify('Error: Could not create temporary file.', vim.log.levels.ERROR)
    return nil
  end
  f:write(json_payload)
  f:close()

  local url = string.format(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=%s',
    api_key
  )
  local cmd = {
    'curl',
    '-s',
    '-X',
    'POST',
    '-H',
    'Content-Type: application/json',
    '-d',
    '@' .. tmp_file,
    url,
  }
  local result = vim.fn.system(cmd)

  -- Remove the temp file
  os.remove(tmp_file)

  -- Execute and read the output
  if not result or result == '' then
    vim.notify('Error: No response from API.', vim.log.levels.ERROR)
    return nil
  end

  -- pcall wrapped vim.json.decode in a "protected call." If the API returns a non-JSON error (like a 404 page), the plugin won't crash;
  local ok, answer = pcall(vim.json.decode, result)
  if not ok then
    vim.notify('Error: Failed to parse API response.', vim.log.levels.ERROR)
    return nil
  end

  if answer.candidates and answer.candidates[1] and answer.candidates[1].content then
    return answer.candidates[1].content.parts[1].text
  else
    vim.notify('Error: Unexpected API structure.', vim.log.levels.ERROR)
    return nil
  end
end

--- Takes the parses diff and prompt the LLM to review it
--- @param git_diff string: The lines in the buffer
--- @return string[] | nil: Final parsed and ordered version
local chain_call = function(git_diff)
  -- Ask the LLM to write its own prompt
  local initial_prompt =
    'Create and return only the prompt for doing a code review using a file that has the old(-) and new(+) changes'

  -- Use self-evaluation -> force the LLM to self-evaluate the quality of its answer before outputting it
  local evaluation_prompt = 'Evaluate this answer and change what is necessary'

  -- Ask the LLM for explanation
  local generated_prompt = llm_call(initial_prompt)

  local input = generated_prompt .. git_diff

  local initial_review = llm_call(input)

  if not initial_review then
    vim.notify('No code review received.', vim.log.levels.INFO)
    return
  end

  -- Force vertical split to the right
  vim.cmd('rightbelow vsplit')

  -- Create a new temporary buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  -- Modern option setting
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].buftype = 'nofile' -- Keeps it from asking to save on exit

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(initial_review, '\n'))
end

M.start_review = function(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0
  -- Return the path we are in
  local file_path = vim.api.nvim_buf_get_name(opts.bufnr)

  if file_path == '' then
    return print('Buffer has no file name')
  end

  -- Run git diff to return the changes
  local diff_output = vim.system({ 'git', 'diff', '--', file_path }, { text = true }):wait()
  local lines = vim.split(diff_output.stdout, '\n')

  -- Call the parser
  local diff_lines = parse_diff(lines)

  if not diff_lines or #diff_lines <= 1 then
    vim.notify('No changes found to review.', vim.log.levels.INFO)
    return
  end

  -- Concat the diff in an string
  local final_diff = table.concat(diff_lines, '\n')
  local review = chain_call(final_diff)
end

M.start_review({ bufnr = vim.api.nvim_get_current_buf() })

return M

-- Get the absolute path of the current buffer
-- local current_file = vim.fn.expand('%:p')

-- Run git diff and output it to the Neovim messages
-- local raw_diff = vim.fn.system('git diff ' .. current_file)

-- local diff = vim.trim(raw_diff)

-- vim.print(diff)
--
-- vim.notify(diff_output.stdout, vim.log.levels.INFO)
-- Use vim.inspect to turn the table into a string
-- vim.notify(vim.inspect(slides), vim.log.levels.INFO)
-- Basic print print(line)
