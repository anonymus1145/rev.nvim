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

--- Generate chain prompts
--- @param input number: The lines in the buffer
--- @return string
local prompt_create = function(input)
  return ''
end

--- Takes the parses diff and prompt the LLM to review it
--- @param prompt string: The lines in the buffer
--- @return string[] | nil: Final parsed and ordered version
local llm_call = function(prompt)
  -- Ask the LLM to write its own prompt
  -- Use self-evaluation -> force the LLM to self-evaluate the quality of its answer before outputting it
  -- Ask the LLM for explanation
  local api_key = os.getenv('GEMINI_API_KEY')

  -- Escape quotes in the prompt to avoid breaking the JSON
  local safe_prompt = prompt:gsub('"', '\\"')

  if not api_key then
    print('Error: GEMINI_API_KEY is not set.')
    return
  end

  local cmd = string.format(
    [[
curl -s -H 'Content-Type: application/json' \
-d '{"contents":[{"parts":[{"text":"%s"}]}]}' \
"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=%s"
]],
    safe_prompt,
    api_key
  )

  -- Execute and read the output
  local handle = io.popen(cmd)
  local result = nil

  if handle then
    result = handle:read('*a')
    handle:close()
  else
    print('Error: LLM error.')
    return
  end

  if not result then
    print('Error: No review recevied.')
    return
  end

  -- Extract the text recevied in result
  -- Check if candidates and content exist first
  local answer = vim.json.decode(result)
  local text = answer.candidates[1].content.parts[1].text
  print(text)
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
  local review = llm_call(final_diff)
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
