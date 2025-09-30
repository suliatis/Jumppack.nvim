local H = {}
H.utils = require('Jumppack.utils')

-- Constants
local GOLDEN_RATIO = 0.618 -- Golden ratio for default window sizing
local WINDOW_ZINDEX = 251 -- Float window z-index for layering

--Create scratch buffer for picker
-- returns: Buffer ID
function H.create_buffer()
  local buf_id = H.utils.create_scratch_buf('main')
  vim.bo[buf_id].filetype = 'minipick'
  return buf_id
end

--Create floating window for picker
-- buf_id: Buffer ID to display
-- win_config: Window configuration
-- cwd: Current working directory
-- cache: Cache table for storing guicursor state
-- returns: Window ID
function H.create_window(buf_id, win_config, cwd, cache)
  -- Hide cursor while instance is active (to not be visible in the window)
  -- This mostly follows a hack from 'folke/noice.nvim'
  cache.guicursor = vim.o.guicursor
  vim.o.guicursor = 'a:JumppackCursor'

  -- Create window and focus on it
  local win_id = vim.api.nvim_open_win(buf_id, true, H.compute_config(win_config, true))

  -- Set window-local data
  vim.wo[win_id].foldenable = false
  vim.wo[win_id].foldmethod = 'manual'
  vim.wo[win_id].list = true
  vim.wo[win_id].listchars = 'extends:…'
  vim.wo[win_id].scrolloff = 0
  vim.wo[win_id].wrap = false
  H.utils.win_update_hl(win_id, 'NormalFloat', 'JumppackNormal')
  H.utils.win_update_hl(win_id, 'FloatBorder', 'JumppackBorder')
  vim.fn.clearmatches(win_id)

  -- Set window's local "current directory" for easier choose/preview/etc.
  H.utils.win_set_cwd(nil, cwd)

  return win_id
end

--Compute window configuration
-- win_config: Window config or callable
-- is_for_open: Whether config is for opening window
-- returns: Computed window configuration
function H.compute_config(win_config, is_for_open)
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  local default_config = {
    relative = 'editor',
    anchor = 'SW',
    width = math.floor(GOLDEN_RATIO * max_width),
    height = math.floor(GOLDEN_RATIO * max_height),
    col = 0,
    row = max_height + (has_tabline and 1 or 0),
    border = (vim.fn.exists('+winborder') == 1 and vim.o.winborder ~= '') and vim.o.winborder or 'single',
    style = 'minimal',
    noautocmd = is_for_open,
    -- Use high enough value to be on top of built-in windows (pmenu, etc.)
    zindex = WINDOW_ZINDEX,
  }
  local config = vim.tbl_deep_extend('force', default_config, H.utils.expand_callable(win_config) or {})

  -- Tweak config values to ensure they are proper
  if config.border == 'none' then
    config.border = { '', ' ', '', '', '', ' ', '', '' }
  end
  -- - Account for border
  config.height = math.min(config.height, max_height - 2)
  config.width = math.min(config.width, max_width - 2)

  return config
end

return H
