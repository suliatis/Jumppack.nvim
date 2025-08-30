local path_package = vim.fn.stdpath('data') .. '/site'
local mini_path = path_package .. '/pack/deps/start/mini.nvim'
---@diagnostic disable-next-line: undefined-field
if not vim.loop.fs_stat(mini_path) then
  vim.cmd('echo "Installing `mini.nvim`" | redraw')
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    '--branch',
    'stable',
    'https://github.com/echasnovski/mini.nvim',
    mini_path,
  })
  vim.cmd('packadd mini.nvim | helptags ALL')
end

-- Add current plugin to runtime path
vim.cmd([[let &rtp.=','.getcwd()]])
