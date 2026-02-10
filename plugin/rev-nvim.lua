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

--- @class present.Slides
--- @field slides string[][]: The slides of the file

--- Takes some lines and parses them
--- @param lines string[]: The lines in the buffer
--- @return present.Slides
local parse_diff = function(lines)
  local slides = { slides = {} }
  local current_slide = {}

  local added_separator = '^+'
  local removed_separator = '^-'

  for _, line in ipairs(lines) do
    print(line, 'find:', line:find(separator), ' | ')
    if line:find(separator) then
      if #current_slide > 0 then
        table.insert(slides.slides, current_slide)
      end

      current_slide = {}
    end

    table.insert(current_slide, line)
  end

  table.insert(slides.slides, current_slide)

  return slides
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
  local parsed = parse_diff(lines)
  local window = create_float_window(opts)

  vim.api.nvim_buf_set_lines(window.buf, 0, -1, false, parsed.slides[1])
end

M.start_review({ bufnr = vim.api.nvim_get_current_buf() })

-- Get the absolute path of the current buffer
-- local current_file = vim.fn.expand('%:p')

-- Run git diff and output it to the Neovim messages
-- local raw_diff = vim.fn.system('git diff ' .. current_file)

-- local diff = vim.trim(raw_diff)

-- vim.print(diff)

return M
