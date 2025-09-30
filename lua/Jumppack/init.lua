---@brief [[*jumppack.txt*    Enhanced jumplist navigation for Neovim]]
---
---@tag jumppack jumppack.nvim
---
---JUMPPACK
---
---Enhanced jumplist navigation interface with floating window preview.
---Navigate your jump history with visual feedback and flexible controls.
---
---==============================================================================
---CONTENTS                                               *jumppack-contents*
---
---@toc
---
---==============================================================================
---INTRODUCTION                                       *jumppack-introduction*
---
---@toc_entry Introduction |jumppack-introduction|
---
---Jumppack provides an enhanced navigation interface for Neovim's jumplist.
---The plugin creates a floating window picker that allows users to visualize
---and navigate their jump history with preview functionality.
---
---Display format: [indicator] [icon] [path/name] [lnum:col] [│ line preview]
---Examples: ● 󰢱 src/main.lua 45:12 │ local function init()
---          ✗  config.json 10:5 │ "name": "jumppack"
---
---Features:
---  • Floating window interface for jump navigation
---  • Preview mode showing destination content
---  • Configurable key mappings and window appearance
---  • Filtering options (current working directory only)
---  • Edge wrapping for continuous navigation
---  • Icon support with file type detection
---  • Hide system with optional session persistence
---
---==============================================================================
---SETUP                                                   *jumppack-setup*
---
---@toc_entry Setup |jumppack-setup|
---
---@author Attila Süli
---@copyright 2025
---@license MIT

---@class Config
---@field options ConfigOptions Configuration options
---@field mappings ConfigMappings Key mappings for actions
---@field window ConfigWindow Window configuration

---@class ConfigOptions
---@field global_mappings boolean Whether to override default <C-o>/<C-i> with Jumppack interface
---@field cwd_only boolean Whether to include only jumps within current working directory
---@field wrap_edges boolean Whether to wrap around edges when navigating
---@field default_view string Default view mode ('list' or 'preview')

---@class ConfigMappings
---@field jump_back string Key for jumping back
---@field jump_forward string Key for jumping forward
---@field choose string Key for choosing item
---@field choose_in_split string Key for choosing item in split
---@field choose_in_tabpage string Key for choosing item in tab
---@field choose_in_vsplit string Key for choosing item in vsplit
---@field stop string Key for stopping picker
---@field toggle_preview string Key for toggling preview
---@field toggle_file_filter string Key for toggling file-only filter
---@field toggle_cwd_filter string Key for toggling current working directory filter
---@field toggle_show_hidden string Key for toggling visibility of hidden items
---@field reset_filters string Key for resetting all filters
---@field toggle_hidden string Key for marking/unmarking current item as hidden
---@field jump_to_top string Key for jumping to the top of the jumplist
---@field jump_to_bottom string Key for jumping to the bottom of the jumplist

---@class ConfigWindow
---@field config table|function|nil Float window config

---@class FilterState
---@field file_only boolean Whether to show only jumps from current file
---@field cwd_only boolean Whether to show only jumps from current working directory
---@field show_hidden boolean Whether to show items marked as hidden

---@class JumpItem
---@field bufnr number Buffer number
---@field path string File path
---@field lnum number Line number
---@field col number Column number
---@field jump_index number Index in jumplist
---@field is_current boolean Whether this is current position
---@field offset number Navigation offset from current position
---@field hidden boolean|nil Whether this item is marked as hidden by user

---@class Instance
---@field opts table Configuration options
---@field items JumpItem[] List of jump items (filtered)
---@field original_items JumpItem[]|nil Original unfiltered items for filter operations
---@field filters FilterState Filter state for item filtering
---@field buffers table Buffer IDs
---@field windows table Window IDs
---@field action_keys table Action key mappings
---@field view_state string Current view state ('list' or 'preview')
---@field visible_range table Visible range info
---@field current_ind number Current item index
---@field shown_inds number[] Shown item indices
---@field pending_count string Accumulated count digits for navigation

---@class PickerState
---@field items JumpItem[] Available jump items
---@field selection table Current selection info
---@field general_info table General picker information

local Jumppack = {}

-- Load all modules
local H = {}
H.utils = require('Jumppack.utils')
H.hide = require('Jumppack.hide')
H.filters = require('Jumppack.filters')
H.window = require('Jumppack.window')
H.display = require('Jumppack.display')
H.sources = require('Jumppack.sources')
H.instance = require('Jumppack.instance')
H.actions = require('Jumppack.actions')

-- Config module (inline since it's small and central)
H.config = {}

--- Setup Jumppack with optional configuration
---
---@text Initialize Jumppack plugin with custom configuration. This function merges
--- provided config with defaults, sets up autocommands, highlights, and key mappings.
--- Also sets up a global `Jumppack` variable for convenient access from anywhere.
---
--- IMPORTANT: By default, this overrides Vim's native <C-o> and <C-i> jump commands
--- with Jumppack's enhanced interface. The original behavior can be preserved by
--- setting `options.global_mappings = false` and creating custom mappings.
---
--- Should be called once during plugin initialization, typically in your init.lua.
---
-- config: Configuration table with options, mappings, and window settings
---
---@usage >lua
--- -- Basic setup with defaults (overrides <C-o>/<C-i>)
--- require('jumppack').setup()
---
--- -- Preserve original <C-o>/<C-i> behavior
--- require('jumppack').setup({
---   options = {
---     global_mappings = false -- Disable automatic override of jump keys
---   }
--- })
--- -- Then set up custom mappings:
--- vim.keymap.set('n', '<Leader>o', function() Jumppack.start({ offset = -1 }) end)
--- vim.keymap.set('n', '<Leader>i', function() Jumppack.start({ offset = 1 }) end)
---
--- -- Complete configuration with all available options
--- require('jumppack').setup({
---   options = {
---     cwd_only = true,        -- Only show jumps within current working directory
---     wrap_edges = true,      -- Allow wrapping when navigating with enhanced <C-o>/<C-i>
---     default_view = 'list',  -- Start interface in list mode instead of preview
---     global_mappings = true  -- Override default jump keys (this is the default)
---   },
---   mappings = {
---     -- Navigation
---     jump_back = '<Leader>o',    -- Custom back navigation
---     jump_forward = '<Leader>i', -- Custom forward navigation
---
---     -- Selection
---     choose = '<CR>',            -- Choose item
---     choose_in_split = '<C-s>',  -- Open in horizontal split
---     choose_in_vsplit = '<C-v>', -- Open in vertical split
---     choose_in_tabpage = '<C-t>',-- Open in new tab
---
---     -- Control
---     stop = '<Esc>',             -- Close picker
---     toggle_preview = 'p',       -- Toggle preview mode
---
---     -- Filtering (runtime filters, not persistent)
---     toggle_file_filter = 'f',   -- Toggle current file filter
---     toggle_cwd_filter = 'c',    -- Toggle current directory filter
---     toggle_show_hidden = '.',   -- Toggle visibility of hidden items
---     reset_filters = 'r',        -- Clear all active filters
---
---     -- Hide management
---     toggle_hidden = 'x',        -- Hide/unhide current item
---   },
---   window = {
---     config = {
---       relative = 'editor',
---       width = 80,
---       height = 15,
---       row = 10,
---       col = 10,
---       style = 'minimal',
---       border = 'rounded'
---     }
---   }
--- })
--- <
---
---@seealso |jumppack-configuration| For detailed configuration options
function Jumppack.setup(config)
  local log = H.utils.get_logger()
  log.debug('setup() called')
  config = H.config.setup(config)
  H.config.apply(config)
  H.config.setup_autocommands()
  H.config.setup_highlights()
  H.config.setup_mappings(config)
  log.debug('setup: configuration complete, log_level=', Jumppack.config.options.log_level)

  -- Set global for convenient access
  _G.Jumppack = Jumppack
end

---==============================================================================
---CONFIGURATION                                     *jumppack-configuration*
---
---@toc_entry Configuration |jumppack-configuration|
---
---Jumppack can be configured through the setup() function. All configuration
---options have sensible defaults and are optional.
---
---Default Configuration Values ~
---
---Options:
---| Option                | Default       | Description                                   |
---| --------------------- | ------------- | --------------------------------------------- |
---| global_mappings       | true          | Override <C-o>/<C-i> with Jumppack            |
---| cwd_only              | false         | Show only jumps in current directory          |
---| wrap_edges            | false         | Wrap around list edges                        |
---| default_view          | 'preview'     | Initial view mode (list or preview)           |
---| count_timeout_ms      | 1000          | Timeout for count accumulation (ms)           |
---
---Default Keymaps ~
---
---Navigation:
---| Key        | Action                 | Description                                 |
---| ---------- | ---------------------- | ------------------------------------------- |
---| <C-o>      | jump_back              | Navigate backward in jumplist               |
---| <C-i>      | jump_forward           | Navigate forward in jumplist                |
---| gg         | jump_to_top            | Jump to top of list                         |
---| G          | jump_to_bottom         | Jump to bottom of list                      |
---
---Selection:
---| Key        | Action                 | Description                                 |
---| ---------- | ---------------------- | ------------------------------------------- |
---| <CR>       | choose                 | Go to selected jump location                |
---| <C-s>      | choose_in_split        | Open in horizontal split                    |
---| <C-v>      | choose_in_vsplit       | Open in vertical split                      |
---| <C-t>      | choose_in_tabpage      | Open in new tab                             |
---
---Control:
---| Key        | Action                 | Description                                 |
---| ---------- | ---------------------- | ------------------------------------------- |
---| <Esc>      | stop                   | Close picker                                |
---| p          | toggle_preview         | Toggle preview mode                         |
---
---Filtering:
---| Key        | Action                 | Description                                 |
---| ---------- | ---------------------- | ------------------------------------------- |
---| f          | toggle_file_filter     | Toggle current file filter                  |
---| c          | toggle_cwd_filter      | Toggle current directory filter             |
---| .          | toggle_show_hidden     | Toggle visibility of hidden items           |
---| r          | reset_filters          | Clear all active filters                    |
---
---Hide Management:
---| Key        | Action                 | Description                                 |
---| ---------- | ---------------------- | ------------------------------------------- |
---| x          | toggle_hidden          | Mark/unmark item as hidden                  |
---
---Session Persistence ~
---
---Hidden items can persist across Neovim sessions using the global variable
---`g:Jumppack_hidden_items`. This integrates with Neovim's built-in session management.
---
---**IMPORTANT**: Session persistence requires 'globals' in your sessionoptions.
---The default sessionoptions does NOT include 'globals', so you must add it manually.
---
---**Setup for persistence:**
--- >lua
--- -- Add to your init.lua to enable global variable saving in sessions
--- vim.opt.sessionoptions:append('globals')
--- <
---
---**Usage:**
---  1. Ensure 'globals' is in sessionoptions (see setup above)
---  2. Hide items using `x` key in the picker interface
---  3. Save session with `:mksession` or `:mks`
---  4. Restart Neovim and restore session with `:source Session.vim`
---  5. Hidden items persist automatically across sessions
---
---**Note**: Without 'globals' in sessionoptions, hidden items reset on restart.
---This is standard Neovim behavior - global variables are not saved by default.
---
---See the setup() function documentation and configuration examples for
---detailed information about all available options.

Jumppack.config = {
  options = {
    -- Whether to override default <C-o>/<C-i> jump keys with Jumppack interface
    global_mappings = true,
    -- Whether to include only jumps within current working directory
    cwd_only = false,
    -- Whether to wrap around edges when navigating with <C-o>/<C-i>
    wrap_edges = false,
    -- Default view mode when starting picker ('list' or 'preview')
    default_view = 'preview',
    -- Timeout in milliseconds for count accumulation (like Vim's timeout)
    count_timeout_ms = 1000,
    -- Log level: 'off', 'error', 'warn', 'info', 'debug', 'trace'
    -- Can be overridden by JUMPPACK_LOG_LEVEL environment variable
    log_level = 'off',
  },
  -- Keys for performing actions. See `:h Jumppack-actions`.
  mappings = {
    -- Navigation
    jump_back = '<C-o>',
    jump_forward = '<C-i>',
    jump_to_top = 'gg',
    jump_to_bottom = 'G',

    -- Selection
    choose = '<CR>',
    choose_in_split = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit = '<C-v>',

    -- Control
    stop = '<Esc>',
    toggle_preview = 'p', -- Toggle between list and preview view modes

    -- Filtering (temporary filters, reset when picker closes)
    toggle_file_filter = 'f', -- Show only jumps in current file
    toggle_cwd_filter = 'c', -- Show only jumps in current working directory
    toggle_show_hidden = '.', -- Toggle visibility of hidden items
    reset_filters = 'r', -- Clear all active filters

    -- Hide management
    toggle_hidden = 'x', -- Hide/unhide current item
  },

  -- Window related options
  window = {
    -- Float window config (table or callable returning it)
    config = nil,
  },
}

---==============================================================================
---USAGE                                                   *jumppack-usage*
---
---@toc_entry Usage |jumppack-usage|
---
---Basic usage patterns and workflows for Jumppack navigation interface.
---
---See the API Functions section for detailed usage examples of all functions.
---
---==============================================================================
---API FUNCTIONS                                             *jumppack-api*
---
---@toc_entry API Functions |jumppack-api|
---
---Public API functions for Jumppack navigation interface.

--- Start the jumplist navigation interface
---
---@text Opens the jumplist navigation interface with a floating window. Displays available
--- jump positions with navigation preview. Supports directional navigation with offsets
--- and filtering options. The interface allows interactive selection and navigation
--- through your jump history with vim.jumplist.
---
-- opts: Navigation options with the following fields:
---   - offset (number): Navigation offset from current position. Negative for backward
---     jumps (e.g., -1 for previous position), positive for forward jumps (e.g., 1 for next).
---     If offset exceeds available range, falls back to nearest valid position.
---   - source (table): Custom source configuration (advanced usage)
---
-- returns: Selected jump item if user chose one, nil if cancelled
---
---@usage >lua
--- -- Open interface showing previous jump position
--- Jumppack.start({ offset = -1 })
---
--- -- Open interface showing next jump position
--- Jumppack.start({ offset = 1 })
---
--- -- Open interface with no specific offset (shows all jumps)
--- Jumppack.start()
---
--- -- Advanced usage - capture selected item
--- local selected = Jumppack.start({ offset = -2 })
--- if selected then
---   print('Selected:', selected.path, 'at line', selected.lnum)
--- end
---
--- -- Typical workflow integration (using global variable)
--- vim.keymap.set('n', '<C-o>', function()
---   Jumppack.start({ offset = -1 })
--- end, { desc = 'Jump back with interface' })
---
--- vim.keymap.set('n', '<C-i>', function()
---   Jumppack.start({ offset = 1 })
--- end, { desc = 'Jump forward with interface' })
---
--- -- Custom keymaps with global access
--- vim.keymap.set('n', '<Leader>j', function()
---   Jumppack.start({ offset = -1 })
--- end, { desc = 'Jump back' })
---
--- -- Check if interface is active
--- if Jumppack.is_active() then
---   print('Navigation interface is open')
--- end
---
--- -- Alternative: using require (not necessary after setup)
--- -- require('jumppack').start({ offset = -1 })
--- <
---
---@seealso |jumppack-navigation| For navigation patterns and workflows
function Jumppack.start(opts)
  local log = H.utils.get_logger()
  log.debug('start() called with offset=', opts and opts.offset or 'nil')
  log.info('Starting jumplist picker')

  -- Early validation with clear error messages
  if opts ~= nil and type(opts) ~= 'table' then
    log.error('start(): invalid opts type:', type(opts))
    H.utils.error('start(): options must be a table, got ' .. type(opts))
  end

  opts = opts or {}

  -- Create jumplist source with user feedback
  local jumplist_source = H.sources.create_source(opts)
  if not jumplist_source then
    log.warn('start(): No jumps available')
    H.utils.notify('No jumps available')
    return -- No jumps available - not an error, just nothing to do
  end

  -- Add public API functions to source
  jumplist_source.show = Jumppack.show_items
  jumplist_source.preview = Jumppack.preview_item
  jumplist_source.choose = Jumppack.choose_item

  opts.source = jumplist_source

  opts = H.config.validate_opts(opts)
  local instance = H.instance.create(opts)
  H.instance.set_active(instance)

  if vim.islist(opts.source.items) then
    H.instance.set_items(instance, opts.source.items, opts.source.initial_selection)
  end

  H.instance.track_focus(instance)
  return H.instance.run_loop(instance)
end

--- Refresh the active navigation interface
---
---@text Updates the jumplist interface with current jump data. Only works when the interface
--- is currently active. Useful for refreshing the view if the jumplist has changed
--- during operation or if you want to reload the data without closing and
--- reopening the interface.
---
---@usage >lua
--- -- Refresh current interface (only if active)
--- Jumppack.refresh()
---
--- -- Typical use in custom mappings
--- vim.keymap.set('n', '<F5>', function()
---   if Jumppack.is_active() then
---     Jumppack.refresh()
---   end
--- end, { desc = 'Refresh jumppack interface' })
--- <
---
---@seealso |jumppack-interface-management| For interface lifecycle management
function Jumppack.refresh()
  if not Jumppack.is_active() then
    return
  end
  local instance = H.instance.get_active()
  H.instance.update(instance, true)
end

---==============================================================================
---NAVIGATION                                           *jumppack-navigation*
---
---@toc_entry Navigation |jumppack-navigation|
---
---Navigation patterns and workflows for jump history management.
---
---==============================================================================
---DISPLAY OPTIONS                                       *jumppack-display*
---
---@toc_entry Display Options |jumppack-display|
---
---Display customization and formatting options.

-- ============================================================================
-- DISPLAY & RENDERING FUNCTIONS
-- ============================================================================

-- Highlight priority constants (used by Jumppack.show_items)
local PRIORITY_HIDDEN_MARKER = 150 -- Hidden item markers
local PRIORITY_ICON = 200 -- File type icons
local PRIORITY_HIDDEN_INDICATOR = 250 -- Hidden indicators (highest)

-- Symbol constants (used by Jumppack.show_items)
local SYMBOL_HIDDEN = '✗' -- Hidden item indicator
local SYMBOL_SEPARATOR = '│' -- Content separator

-- Namespaces
local ns_id = {
  headers = vim.api.nvim_create_namespace('JumppackHeaders'),
  preview = vim.api.nvim_create_namespace('JumppackPreview'),
  ranges = vim.api.nvim_create_namespace('JumppackRanges'),
}

---
---
---
--- Display items in a buffer with syntax highlighting
---
---@text Renders jump items in the navigation buffer with integrated format: [indicator] [icon] [path/name] [lnum:col]
--- Handles item formatting, icon display, position markers, and line preview. The format includes
--- position indicators, file type icons, smart filenames, line:column position, and optional line content preview.
---
-- buf_id: Buffer ID to display items in
-- items: List of jump items to display with path, lnum, col, offset, and optional hidden field
-- opts: Display options with fields:
---   - show_icons (boolean): Whether to show file type icons (default: true)
---   - icons (table): Custom icon mapping for file types
---
---@usage >lua
--- -- Display items with default options (shows: ● lua/init.lua 1:1 │ local M = {})
--- local buf = vim.api.nvim_create_buf(false, true)
--- local items = {
---   { path = 'lua/init.lua', lnum = 1, col = 1, offset = -1 },
---   { path = 'config.lua', lnum = 15, col = 10, offset = 1, hidden = true }
--- }
--- Jumppack.show_items(buf, items)
---
--- -- Custom display options
--- Jumppack.show_items(buf, items, {
---   show_icons = false,  -- Disable file icons (✗ config.lua 15:10 │ ...)
---   icons = { file = '📄', none = '  ' }  -- Custom icons
--- })
--- <
---
---@seealso |jumppack-display| For display customization options
function Jumppack.show_items(buf_id, items, opts)
  local default_icons = { file = ' ', none = '  ' }
  opts = vim.tbl_deep_extend('force', { show_icons = true, icons = default_icons }, opts or {})

  -- Generate lines with integrated icons and position info

  local lines = vim.tbl_map(function(item)
    return H.display.item_to_string(item, {
      show_preview = true, -- List mode shows line preview
      show_icons = opts.show_icons,
      icons = opts.icons,
      cwd = vim.fn.getcwd(), -- Use current working directory
    })
  end, items)
  local tab_spaces = string.rep(' ', vim.o.tabstop)
  lines = vim.tbl_map(function(l)
    return l:gsub('%z', SYMBOL_SEPARATOR):gsub('[\r\n]', ' '):gsub('\t', tab_spaces)
  end, lines)

  H.utils.set_buflines(buf_id, lines)

  -- Extract match ranges and set up highlighting
  local ns_id_local = ns_id.ranges
  H.utils.clear_namespace(buf_id, ns_id_local)

  -- Highlight icons if enabled
  if opts.show_icons then
    local icon_extmark_opts = { hl_mode = 'combine', priority = PRIORITY_ICON }
    for i, item in ipairs(items) do
      if item.offset ~= nil and item.lnum then
        local icon_data = H.display.get_icon(item, opts.icons)
        if icon_data.hl then
          -- Calculate icon position: skip indicator (1 char + space) to get to icon
          local icon_start = 2 -- After '[indicator] '
          icon_extmark_opts.hl_group = icon_data.hl
          icon_extmark_opts.end_row, icon_extmark_opts.end_col =
            i - 1, icon_start + (icon_data.text and #icon_data.text or 0)
          H.utils.set_extmark(buf_id, ns_id_local, i - 1, icon_start, icon_extmark_opts)
        end
      end
    end
  end

  -- Highlight hidden items
  local hidden_extmark_opts = { hl_mode = 'combine', priority = PRIORITY_HIDDEN_MARKER }
  for i, item in ipairs(items) do
    if item.hidden then
      -- Highlight the entire line as hidden
      hidden_extmark_opts.hl_group = 'JumppackHidden'
      hidden_extmark_opts.end_row, hidden_extmark_opts.end_col = i - 1, lines[i]:len()
      H.utils.set_extmark(buf_id, ns_id_local, i - 1, 0, hidden_extmark_opts)

      -- Highlight the ✗ marker specifically
      if lines[i]:match('^' .. SYMBOL_HIDDEN) then
        local marker_extmark_opts =
          { hl_mode = 'combine', priority = PRIORITY_HIDDEN_INDICATOR, hl_group = 'JumppackHiddenMarker' }
        marker_extmark_opts.end_row, marker_extmark_opts.end_col = i - 1, 2 -- ✗ + space
        H.utils.set_extmark(buf_id, ns_id_local, i - 1, 0, marker_extmark_opts)
      end
    end
  end
end

--- Preview a jump item in a buffer
---
---@text Displays a preview of the jump destination in the preview buffer. Shows the
--- content around the jump target with syntax highlighting and cursor positioning.
--- Used by the interface's preview mode to show file content before navigation.
---
-- buf_id: Buffer ID for preview content (must be a valid buffer)
-- item: Jump item to preview. If nil, clears the preview buffer
-- opts: Preview options with fields:
---   - context_lines (number): Number of lines to show around target (default: varies)
---   - syntax_highlight (boolean): Whether to apply syntax highlighting (default: true)
---
---@usage >lua
--- -- Preview a jump item
--- local preview_buf = vim.api.nvim_create_buf(false, true)
--- local item = { bufnr = 1, lnum = 10, col = 0, path = 'init.lua' }
--- Jumppack.preview_item(preview_buf, item)
---
--- -- Clear preview
--- Jumppack.preview_item(preview_buf, nil)
---
--- -- Custom preview with more context
--- Jumppack.preview_item(preview_buf, item, {
---   context_lines = 10,
---   syntax_highlight = true
--- })
--- <
---
---==============================================================================
---PREVIEW                                               *jumppack-preview*
---
---@toc_entry Preview |jumppack-preview|
---
---Preview functionality and customization options.
---
---@seealso |jumppack-preview| For preview customization
function Jumppack.preview_item(buf_id, item, opts)
  local log = H.utils.get_logger()
  if not item or not item.bufnr then
    log.trace('preview_item: invalid item or bufnr')
    return
  end

  log.debug('preview_item: buf_id=', buf_id, 'item.path=', item.path, 'lnum=', item.lnum, 'col=', item.col)

  opts = vim.tbl_deep_extend('force', { n_context_lines = 2 * vim.o.lines, line_position = 'center' }, opts or {})

  -- NOTE: ideally just setting target buffer to window would be enough, but it
  -- has side effects. See https://github.com/neovim/neovim/issues/24973 .
  -- Reading lines and applying custom styling is a passable alternative.
  local buf_id_source = item.bufnr

  -- Get lines from buffer ensuring it is loaded without important consequences
  local cache_eventignore = vim.o.eventignore
  vim.o.eventignore = 'BufEnter'
  vim.fn.bufload(buf_id_source)
  vim.o.eventignore = cache_eventignore
  local lines = vim.api.nvim_buf_get_lines(buf_id_source, 0, (item.lnum or 1) + opts.n_context_lines, false)

  log.trace('preview_item: loaded', #lines, 'lines from buffer')

  -- Prepare data for preview_set_lines
  local preview_data = {
    lnum = item.lnum,
    col = item.col,
    filetype = vim.bo[buf_id_source].filetype,
    path = item.path,
    line_position = opts.line_position,
  }
  H.display.preview_set_lines(buf_id, lines, preview_data)
end

--- Choose and navigate to a jump item
---
---@text Executes navigation to the selected jump item. Handles backward and forward
--- jumps using Vim's jump commands (Ctrl-o and Ctrl-i). This function performs the
--- actual jump navigation and closes the navigation interface.
---
-- item: Jump item to navigate to with offset field for direction:
---   - Negative offset: Navigate backward in jumplist (uses <C-o>)
---   - Positive offset: Navigate forward in jumplist (uses <C-i>)
---   - Zero offset: Stay at current position
---
---@usage >lua
--- -- Navigate to a jump item (typically called by interface)
--- local item = { offset = -2, bufnr = 1, lnum = 10 }
--- Jumppack.choose_item(item)
---
--- -- Example of how interface uses this internally
--- vim.keymap.set('n', '<CR>', function()
---   local current_item = get_selected_item()
---   Jumppack.choose_item(current_item)
--- end, { buffer = interface_buf })
--- <
---
---@seealso |jumppack-navigation| For jump navigation patterns
function Jumppack.choose_item(item)
  local log = H.utils.get_logger()
  log.debug('choose_item: offset=', item.offset, 'path=', item.path, 'lnum=', item.lnum)
  log.info('Navigating to', item.path, 'at', item.lnum, ':', item.col, '(offset=', item.offset, ')')
  vim.schedule(function()
    if item.offset < 0 then
      -- Use vim.cmd with proper command syntax
      vim.cmd('execute "normal! ' .. math.abs(item.offset) .. '\\<C-o>"')
    elseif item.offset > 0 then
      -- Use vim.cmd with proper command syntax
      vim.cmd('execute "normal! ' .. item.offset .. '\\<C-i>"')
    elseif item.offset == 0 then
      -- Already at current position, do nothing
      log.info('Already at current position')
      H.utils.notify('Already at current position')
    end
  end)
end

--- Check if the navigation interface is currently active
---
---@text Determines whether the Jumppack navigation interface is currently open and active.
--- Useful for conditional operations and preventing conflicts with multiple instances.
---
-- returns: True if interface is active, false otherwise
---
---@usage >lua
--- -- Check before performing operations
--- if Jumppack.is_active() then
---   print('Interface is open')
---   Jumppack.refresh()
--- else
---   print('No active interface')
--- end
---
--- -- Conditional keymap behavior
--- vim.keymap.set('n', '<Esc>', function()
---   if Jumppack.is_active() then
---     -- Close interface
---     vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'n', false)
---   else
---     -- Normal escape behavior
---     vim.cmd('nohlsearch')
---   end
--- end)
--- <
---
---==============================================================================
---INTERFACE MANAGEMENT                         *jumppack-interface-management*
---
---@toc_entry Interface Management |jumppack-interface-management|
---
---Interface lifecycle management and state control.

function Jumppack.is_active()
  return H.instance.get_active() ~= nil
end

--- Get the current state of the active navigation interface
---
---@text Retrieves the current state of the active interface instance, including items,
--- selection, and general information. Returns nil if no interface is active. Useful
--- for inspecting interface state and implementing custom behaviors.
---
-- returns: Current interface state with fields:
---   - items (JumpItem[]): Available jump items
---   - selection (table): Current selection with index
---   - general_info (table): Interface metadata and configuration
---   - current (JumpItem): Currently selected item
---
---@usage >lua
--- -- Get and inspect interface state
--- local state = Jumppack.get_state()
--- if state then
---   print('Selected item:', state.current.path)
---   print('Total items:', #state.items)
---   print('Selection index:', state.selection.index)
--- end
---
--- -- Custom behavior based on interface state
--- vim.keymap.set('n', '<C-g>', function()
---   local state = Jumppack.get_state()
---   if state and state.current then
---     vim.notify(string.format('Jump: %s:%d', state.current.path, state.current.lnum))
---   end
--- end, { desc = 'Show current jump info' })
--- <
function Jumppack.get_state()
  if not Jumppack.is_active() then
    return nil
  end

  local instance = H.instance.get_active()
  local state = {
    items = instance.items,
    selection = {
      index = instance.current_ind,
      item = H.instance.get_selection(instance),
    },
    general_info = H.display.get_general_info(instance),
  }

  return state
end

-- ============================================================================
-- CONFIG MODULE
-- ============================================================================

local default_config = vim.deepcopy(Jumppack.config)

--Setup and validate configuration
-- config: Configuration table
-- returns: Validated configuration
function H.config.setup(config)
  H.utils.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(default_config), config or {})

  H.utils.check_type('mappings', config.mappings, 'table')
  H.utils.check_type('mappings.jump_back', config.mappings.jump_back, 'string')
  H.utils.check_type('mappings.jump_forward', config.mappings.jump_forward, 'string')
  H.utils.check_type('mappings.choose', config.mappings.choose, 'string')
  H.utils.check_type('mappings.choose_in_split', config.mappings.choose_in_split, 'string')
  H.utils.check_type('mappings.choose_in_tabpage', config.mappings.choose_in_tabpage, 'string')
  H.utils.check_type('mappings.choose_in_vsplit', config.mappings.choose_in_vsplit, 'string')
  H.utils.check_type('mappings.stop', config.mappings.stop, 'string')
  H.utils.check_type('mappings.toggle_preview', config.mappings.toggle_preview, 'string')
  H.utils.check_type('mappings.toggle_file_filter', config.mappings.toggle_file_filter, 'string')
  H.utils.check_type('mappings.toggle_cwd_filter', config.mappings.toggle_cwd_filter, 'string')
  H.utils.check_type('mappings.toggle_show_hidden', config.mappings.toggle_show_hidden, 'string')
  H.utils.check_type('mappings.reset_filters', config.mappings.reset_filters, 'string')
  H.utils.check_type('mappings.toggle_hidden', config.mappings.toggle_hidden, 'string')
  H.utils.check_type('mappings.jump_to_top', config.mappings.jump_to_top, 'string')
  H.utils.check_type('mappings.jump_to_bottom', config.mappings.jump_to_bottom, 'string')

  H.utils.check_type('options', config.options, 'table')
  H.utils.check_type('options.global_mappings', config.options.global_mappings, 'boolean')
  H.utils.check_type('options.cwd_only', config.options.cwd_only, 'boolean')
  H.utils.check_type('options.wrap_edges', config.options.wrap_edges, 'boolean')
  H.utils.check_type('options.default_view', config.options.default_view, 'string')
  if not vim.tbl_contains({ 'list', 'preview' }, config.options.default_view) then
    H.utils.error(
      'setup(): options.default_view must be "list" or "preview", got "' .. config.options.default_view .. '"'
    )
  end
  H.utils.check_type('options.count_timeout_ms', config.options.count_timeout_ms, 'number')
  H.utils.check_type('options.log_level', config.options.log_level, 'string')
  if not vim.tbl_contains({ 'off', 'error', 'warn', 'info', 'debug', 'trace' }, config.options.log_level) then
    H.utils.error(
      'setup(): options.log_level must be one of: off, error, warn, info, debug, trace, got "'
        .. config.options.log_level
        .. '"'
    )
  end

  H.utils.check_type('window', config.window, 'table')
  local is_table_or_callable = function(x)
    return x == nil or type(x) == 'table' or vim.is_callable(x)
  end
  if not is_table_or_callable(config.window.config) then
    H.utils.error('setup(): window.config must be table or callable, got ' .. type(config.window.config))
  end

  return config
end

--Apply configuration to Jumppack
-- config: Configuration to apply
function H.config.apply(config)
  Jumppack.config = config
end

--Get merged configuration
-- config: Override configuration
-- returns: Merged configuration
function H.config.get(config)
  return vim.tbl_deep_extend('force', Jumppack.config, vim.b.minipick_config or {}, config or {})
end

-- Setup autocommands for Jumppack
function H.config.setup_autocommands()
  local gr = vim.api.nvim_create_augroup('Jumppack', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('VimResized', '*', Jumppack.refresh, 'Refresh on resize')
  au('ColorScheme', '*', H.config.setup_highlights, 'Ensure colors')
end

-- Setup default highlight groups
function H.config.setup_highlights()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('JumppackBorder', { link = 'FloatBorder' })
  hi('JumppackBorderText', { link = 'FloatTitle' })
  hi('JumppackCursor', { blend = 100, nocombine = true })
  hi('JumppackIconDirectory', { link = 'Directory' })
  hi('JumppackIconFile', { link = 'JumppackNormal' })
  hi('JumppackNormal', { link = 'NormalFloat' })
  hi('JumppackPreviewLine', { link = 'CursorLine' })
  hi('JumppackPreviewRegion', { link = 'IncSearch' })
  hi('JumppackMatchCurrent', { link = 'Visual' })

  -- Hide system highlights
  hi('JumppackHidden', { link = 'Comment' })
  hi('JumppackHiddenMarker', { link = 'WarningMsg' })
end

-- Setup global key mappings that override default jump behavior
-- Sets up global keymaps that replace Vim's default <C-o> and <C-i> jump
-- commands with Jumppack's enhanced interface. Only runs if global_mappings option
-- is enabled. The mappings support count prefixes (e.g., 3<C-o> for 3 jumps back).
-- config: Configuration with mappings
function H.config.setup_mappings(config)
  if not config.options.global_mappings then
    return
  end

  -- Set up global keymaps for jump navigation with count support
  vim.keymap.set('n', config.mappings.jump_back, function()
    Jumppack.start({ offset = -vim.v.count1 })
  end, { desc = 'Jump back', silent = true })

  vim.keymap.set('n', config.mappings.jump_forward, function()
    Jumppack.start({ offset = vim.v.count1 })
  end, { desc = 'Jump forward', silent = true })
end

--Validate picker options
-- opts: Options to validate
-- returns: Validated options
function H.config.validate_opts(opts)
  opts = opts or {}
  if type(opts) ~= 'table' then
    H.utils.error('validate_opts(): options must be a table, got ' .. type(opts))
  end

  opts = vim.deepcopy(H.config.get(opts))

  local validate_callable = function(x, x_name)
    if not vim.is_callable(x) then
      H.utils.error(string.format('validate_opts(): %s must be callable, got %s', x_name, type(x)))
    end
  end

  -- Source
  local source = opts.source

  if source then
    local items = source.items or {}
    local is_valid_items = vim.islist(items) or vim.is_callable(items)
    if not is_valid_items then
      H.utils.error('validate_opts(): source.items must be array or callable, got ' .. type(items))
    end

    source.name = tostring(source.name or '<No name>')

    if type(source.cwd) == 'string' then
      source.cwd = H.utils.full_path(source.cwd)
    end
    if source.cwd == nil then
      source.cwd = vim.fn.getcwd()
    end
    if vim.fn.isdirectory(source.cwd) == 0 then
      H.utils.error('validate_opts(): source.cwd must be a valid directory, got "' .. tostring(source.cwd) .. '"')
    end

    source.show = source.show or Jumppack.show_items
    validate_callable(source.show, 'source.show')

    source.preview = source.preview or Jumppack.preview_item
    validate_callable(source.preview, 'source.preview')

    source.choose = source.choose or Jumppack.choose_item
    validate_callable(source.choose, 'source.choose')
  end

  -- Mappings
  for field, x in pairs(opts.mappings) do
    if type(field) ~= 'string' then
      H.utils.error('validate_opts(): mapping keys must be strings, got ' .. type(field))
    end
    if type(x) ~= 'string' then
      H.utils.error(string.format('validate_opts(): mapping for "%s" must be string, got %s', field, type(x)))
    end
  end

  -- Window
  local win_config = opts.window.config
  local is_valid_winconfig = win_config == nil or type(win_config) == 'table' or vim.is_callable(win_config)
  if not is_valid_winconfig then
    H.utils.error('validate_opts(): window.config must be table or callable, got ' .. type(win_config))
  end

  return opts
end

--Normalize key mappings for actions
-- mappings: Key mappings
-- returns: Normalized action mappings
function H.config.normalize_mappings(mappings)
  local res = {}
  local add_to_res = function(char, data)
    local key = H.utils.replace_termcodes(char)
    if key == nil or key == '' then
      return
    end
    res[key] = data
  end

  for name, char in pairs(mappings) do
    local data = { char = char, name = name, func = H.actions[name] }
    add_to_res(char, data)
  end

  return res
end

-- ============================================================================
-- DEPENDENCY INJECTION
-- ============================================================================

-- Inject config and namespaces (only what can't be imported)
H.utils.set_config(Jumppack.config)
H.filters.set_logger(H.utils.get_logger())
H.display.set_namespaces(ns_id)
H.sources.set_config(Jumppack.config)
H.instance.set_config(Jumppack.config)
H.instance.set_config_module(H.config)

---==============================================================================
---
---vim:tw=78:ts=8:ft=help:norl:

return Jumppack
