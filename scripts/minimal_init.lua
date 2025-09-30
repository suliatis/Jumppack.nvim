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
local plugin_dir = vim.fn.getcwd()
vim.cmd([[let &rtp.=','.getcwd()]])

-- Add lua directory to package path for submodule loading
-- This ensures jumppack.* modules can be required from lua/jumppack/
local lua_path = plugin_dir .. '/lua/?.lua;' .. plugin_dir .. '/lua/?/init.lua'
package.path = lua_path .. ';' .. package.path
