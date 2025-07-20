-- Minimal init.lua for testing Jumppack plugin
-- This configuration provides the minimal setup needed to test the plugin

-- Clone 'mini.nvim' manually in a temporary directory for testing
local path_package = vim.fn.stdpath('data') .. '/site'
local mini_path = path_package .. '/pack/deps/start/mini.nvim'

if not vim.loop.fs_stat(mini_path) then
  vim.cmd('echo "Installing mini.nvim for tests..."')
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/echasnovski/mini.nvim',
    mini_path,
  })
end

-- Add mini.nvim to runtime path
vim.cmd('set rtp+=' .. mini_path)

-- Add current plugin to runtime path
local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.cmd('set rtp+=' .. plugin_path)

-- Setup mini.test
require('mini.test').setup()

-- Load the plugin
vim.cmd('runtime! plugin/**/*.lua')

-- Set up minimal vim options for testing
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
vim.o.hidden = true
vim.o.shortmess = 'atI'

-- Disable some features that might interfere with testing
vim.o.updatetime = 10
vim.o.cmdheight = 1

-- Enable termguicolors for proper highlighting in tests
if vim.fn.has('termguicolors') == 1 then
  vim.o.termguicolors = true
end

-- Set up basic colorscheme
vim.cmd('colorscheme default')
