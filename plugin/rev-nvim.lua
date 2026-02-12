-- Module -> Public interface for the file
local M = {}

local function create_float_window(opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.8)
  local height = opts.height or math.floor(vim.o.lines * 0.8)

  -- Calculate the position to center the window
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create a buffer
  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer

  -- Define window configuration
  local win_config = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal', -- No borders or extra UI elements
    border = 'rounded',
  }

  -- Create the floating window
  local win = vim.api.nvim_open_win(buf, true, win_config)

  return { buf = buf, win = win }
end

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

  local window = create_float_window(opts)

  vim.api.nvim_buf_set_lines(window.buf, 0, -1, false, diff_lines)
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
