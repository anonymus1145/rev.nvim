vim.keymap.set('n', '<leader>rv', function()
  require('rev-nvim').start_review()
end, { desc = 'Start code review' })

vim.keymap.set('n', '<leader>rb', function()
  require('rev-nvim').breakpoint_review()
end, { desc = 'Start breakpoints block review' })

-- Create a command so users can type :RevReview
vim.api.nvim_create_user_command('RevReview', function()
  require('rev-nvim').start_review()
end, {})
