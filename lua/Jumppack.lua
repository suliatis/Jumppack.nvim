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

local H = {}
H.config = {}
H.jumplist = {}
H.instance = {}
H.window = {}
H.display = {}
H.actions = {}
H.utils = {}

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
  config = H.config.setup(config)
  H.config.apply(config)
  H.config.setup_autocommands()
  H.config.setup_highlights()
  H.config.setup_mappings(config)

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
---|  Option              |  Default    |  Description                                |
---|---------------------|-------------|---------------------------------------------|
---|  global_mappings     |  true       |  Override <C-o>/<C-i> with Jumppack        |
---|  cwd_only            |  false      |  Show only jumps in current directory      |
---|  wrap_edges          |  false      |  Wrap around list edges                    |
---|  default_view        |  'preview'  |  Initial view mode (list or preview)       |
---|  count_timeout_ms    |  1000       |  Timeout for count accumulation (ms)       |
---
---Default Keymaps ~
---
---Navigation:
---|  Key     |  Action              |  Description                              |
---|----------|----------------------|-------------------------------------------|
---|  <C-o>   |  jump_back           |  Navigate backward in jumplist           |
---|  <C-i>   |  jump_forward        |  Navigate forward in jumplist            |
---|  gg      |  jump_to_top         |  Jump to top of list                     |
---|  G       |  jump_to_bottom      |  Jump to bottom of list                  |
---
---Selection:
---|  Key     |  Action              |  Description                              |
---|----------|----------------------|-------------------------------------------|
---|  <CR>    |  choose              |  Go to selected jump location            |
---|  <C-s>   |  choose_in_split     |  Open in horizontal split                |
---|  <C-v>   |  choose_in_vsplit    |  Open in vertical split                  |
---|  <C-t>   |  choose_in_tabpage   |  Open in new tab                         |
---
---Control:
---|  Key     |  Action              |  Description                              |
---|----------|----------------------|-------------------------------------------|
---|  <Esc>   |  stop                |  Close picker                            |
---|  p       |  toggle_preview      |  Toggle preview mode                     |
---
---Filtering:
---|  Key     |  Action              |  Description                              |
---|----------|----------------------|-------------------------------------------|
---|  f       |  toggle_file_filter  |  Toggle current file filter              |
---|  c       |  toggle_cwd_filter   |  Toggle current directory filter         |
---|  .       |  toggle_show_hidden  |  Toggle visibility of hidden items       |
---|  r       |  reset_filters       |  Clear all active filters                |
---
---Hide Management:
---|  Key     |  Action              |  Description                              |
---|----------|----------------------|-------------------------------------------|
---|  x       |  toggle_hidden       |  Mark/unmark item as hidden              |
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
  H.cache = {}

  -- Early validation with clear error messages
  if opts ~= nil and type(opts) ~= 'table' then
    H.utils.error('start(): options must be a table, got ' .. type(opts))
  end

  opts = opts or {}

  -- Create jumplist source with user feedback
  local jumplist_source = H.jumplist.create_source(opts)
  if not jumplist_source then
    H.utils.notify('No jumps available')
    return -- No jumps available - not an error, just nothing to do
  end
  opts.source = jumplist_source

  opts = H.config.validate_opts(opts)
  H.current_instance = H.instance.create(opts)

  if vim.islist(opts.source.items) then
    H.instance.set_items(H.current_instance, opts.source.items, opts.source.initial_selection)
  end

  H.instance.track_focus(H.current_instance)
  return H.instance.run_loop(H.current_instance)
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
  H.instance.update(H.current_instance, true)
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

-- Highlight priority constants
local PRIORITY_HIDDEN_MARKER = 150 -- Hidden item markers
local PRIORITY_ICON = 200 -- File type icons
local PRIORITY_CURRENT_MATCH = 201 -- Current selection highlight
local PRIORITY_PREVIEW_LINE = 201 -- Preview line highlight
local PRIORITY_REGION = 202 -- Preview region highlight
local PRIORITY_HIDDEN_INDICATOR = 250 -- Hidden indicators (highest)

-- Performance limits
local HIGHLIGHT_MAX_FILESIZE = 1000000 -- Max file size for syntax highlighting (bytes)
local HIGHLIGHT_MAX_LINES = 1000 -- Max lines for syntax highlighting

-- Symbol constants
local SYMBOL_CURRENT = '●' -- Current position marker
local SYMBOL_HIDDEN = '✗' -- Hidden item indicator
local SYMBOL_UP = '↑' -- Backward jump marker
local SYMBOL_DOWN = '↓' -- Forward jump marker
local SYMBOL_SEPARATOR = '│' -- Content separator
local SEPARATOR_SPACED = ' │ ' -- Spaced separator

--- Smart filename display that handles ambiguous names
---
-- Get smart filename for display
-- filepath: Full file path
-- cwd: Current working directory (optional)
-- returns: Smart filename string
function H.display.smart_filename(filepath, cwd)
  if not filepath then
    return ''
  end

  local name = vim.fn.fnamemodify(filepath, ':t')
  cwd = cwd or vim.fn.getcwd()

  -- List of ambiguous filenames that need parent directory
  local ambiguous = {
    -- Lua
    'init.lua',
    -- JavaScript/TypeScript
    'index.js',
    'index.ts',
    'index.jsx',
    'index.tsx',
    -- Python
    '__init__.py',
    'main.py',
    'setup.py',
    -- Web
    'index.html',
    'index.css',
    -- Config files
    'config.json',
    'package.json',
    'tsconfig.json',
    -- Build files
    'Makefile',
    'CMakeLists.txt',
    'Dockerfile',
  }

  -- Handle ambiguous names by showing parent directory
  if vim.tbl_contains(ambiguous, name) then
    local parent = vim.fn.fnamemodify(filepath, ':h:t')
    return parent .. '/' .. name
  end

  -- Handle non-cwd files
  local full_path = H.utils.full_path(filepath)
  local full_cwd = H.utils.full_path(cwd)

  if not vim.startswith(full_path, full_cwd) then
    -- Use ~ for home directory
    local home = vim.env.HOME
    if home and vim.startswith(full_path, home) then
      return '~' .. string.sub(full_path, #home + 1)
    end
    -- Show relative path for other locations
    return vim.fn.fnamemodify(filepath, ':.')
  end

  return name
end

--- Get position marker for jump item
---
-- Get position marker for jump item
-- item: Jump item to get marker for
-- returns: Position marker (●, ↑N, ↓N)
function H.display.get_position_marker(item)
  if not item then
    return ' '
  end

  if item.is_current or (item.offset and item.offset == 0) then
    return SYMBOL_CURRENT
  elseif item.offset and item.offset < 0 then
    return string.format(SYMBOL_UP .. '%d', math.abs(item.offset))
  elseif item.offset and item.offset > 0 then
    return string.format(SYMBOL_DOWN .. '%d', item.offset)
  end

  return ' ' -- Fallback for unknown state
end

--- Get line preview content for item
---
-- Get line preview content for jump item
-- item: Jump item to get preview for
-- returns: Line content preview string
function H.display.get_line_preview(item)
  if not item or not item.bufnr or not item.lnum then
    return ''
  end

  if vim.fn.bufloaded(item.bufnr) == 1 then
    local lines = vim.fn.getbufline(item.bufnr, item.lnum)
    if #lines > 0 then
      local content = vim.trim(lines[1])
      -- Truncate very long lines
      if #content > 50 then
        content = content:sub(1, 47) .. '...'
      end
      return content
    end
  end

  return ''
end

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
  local default_icons = { file = ' ', none = '  ' }
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
  local ns_id = H.ns_id.ranges
  H.utils.clear_namespace(buf_id, ns_id)

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
          H.utils.set_extmark(buf_id, ns_id, i - 1, icon_start, icon_extmark_opts)
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
      H.utils.set_extmark(buf_id, ns_id, i - 1, 0, hidden_extmark_opts)

      -- Highlight the ✗ marker specifically
      if lines[i]:match('^' .. SYMBOL_HIDDEN) then
        local marker_extmark_opts =
          { hl_mode = 'combine', priority = PRIORITY_HIDDEN_INDICATOR, hl_group = 'JumppackHiddenMarker' }
        marker_extmark_opts.end_row, marker_extmark_opts.end_col = i - 1, 2 -- ✗ + space
        H.utils.set_extmark(buf_id, ns_id, i - 1, 0, marker_extmark_opts)
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
  if not item or not item.bufnr then
    return
  end

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
  vim.schedule(function()
    if item.offset < 0 then
      -- Use vim.cmd with proper command syntax
      vim.cmd('execute "normal! ' .. math.abs(item.offset) .. '\\<C-o>"')
    elseif item.offset > 0 then
      -- Use vim.cmd with proper command syntax
      vim.cmd('execute "normal! ' .. item.offset .. '\\<C-i>"')
    elseif item.offset == 0 then
      -- Already at current position, do nothing
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
  return H.current_instance ~= nil
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

  local instance = H.current_instance
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
-- JUMPLIST PROCESSING
-- ============================================================================

---Create jumplist source for picker
-- opts: Picker options
-- returns: Jumplist source or nil if no jumps
function H.jumplist.create_source(opts)
  opts = vim.tbl_deep_extend('force', { offset = -1 }, opts)

  local all_jumps = H.jumplist.get_all(Jumppack.config)

  if #all_jumps == 0 then
    return nil
  end

  local initial_selection = H.jumplist.find_target_offset(all_jumps, opts.offset, Jumppack.config)

  return {
    name = 'Jumplist',
    items = all_jumps,
    initial_selection = initial_selection,
    show = Jumppack.show_items,
    preview = Jumppack.preview_item,
    choose = Jumppack.choose_item,
  }
end

---Get all valid jumps from jumplist
-- config: Configuration
-- returns: List of valid jump items
function H.jumplist.get_all(config)
  local jumps = vim.fn.getjumplist()
  local jumplist = jumps[1]
  local current = jumps[2]

  config = config or Jumppack.config
  local cwd_only = config.options and config.options.cwd_only
  local current_cwd = cwd_only and H.utils.full_path(vim.fn.getcwd()) or nil

  local all_jumps = {}

  -- Process all jumps in the jumplist
  for i = 1, #jumplist do
    local jump = jumplist[i]
    if jump.bufnr > 0 and vim.fn.buflisted(jump.bufnr) == 1 then
      local jump_item = H.jumplist.create_item(jump, i, current)
      if jump_item then
        -- Filter by cwd if cwd_only is enabled
        if cwd_only then
          local jump_path = H.utils.full_path(jump_item.path)
          if vim.startswith(jump_path, current_cwd) then
            table.insert(all_jumps, jump_item)
          end
        else
          table.insert(all_jumps, jump_item)
        end
      end
    end
  end

  -- Reverse the order so most recent jumps are at the top
  local reversed_jumps = {}
  for i = #all_jumps, 1, -1 do
    table.insert(reversed_jumps, all_jumps[i])
  end

  -- Mark items with hide status
  H.hide.mark_items(reversed_jumps)

  return reversed_jumps
end

---Create jump item from jumplist entry
-- jump: Vim jumplist entry
-- i: Jump index
-- current: Current position index
-- returns: Jump item or nil if invalid
function H.jumplist.create_item(jump, i, current)
  local bufname = vim.fn.bufname(jump.bufnr)
  if bufname == '' then
    return nil
  end

  local jump_item = {
    bufnr = jump.bufnr,
    path = bufname,
    lnum = jump.lnum,
    col = jump.col + 1,
    jump_index = i,
    is_current = (i == current + 1),
  }

  -- Determine navigation offset
  if i <= current then
    -- Older jump (go back with <C-o>)
    jump_item.offset = -(current - i + 1)
  elseif i == current + 1 then
    -- Current position
    jump_item.offset = 0
  else
    -- Newer jump (go forward with <C-i>)
    jump_item.offset = i - current - 1
  end

  return jump_item
end

---Find best matching jump for target offset
-- jumps: Available jump items
-- target_offset: Target navigation offset
-- config: Configuration
-- returns: Index of best matching jump
function H.jumplist.find_target_offset(jumps, target_offset, config)
  config = config or Jumppack.config
  local wrap_edges = config.options and config.options.wrap_edges

  local best_same_direction = nil
  local current_position = nil
  local min_backward = nil -- Most negative offset (furthest back)
  local max_forward = nil -- Most positive offset (furthest forward)

  for i, jump in ipairs(jumps) do
    -- Priority 1: Exact match
    if jump.offset == target_offset then
      return i
    end

    -- Track min/max offsets for wrapping
    if jump.offset < 0 and (not min_backward or jump.offset < jumps[min_backward].offset) then
      min_backward = i
    end
    if jump.offset > 0 and (not max_forward or jump.offset > jumps[max_forward].offset) then
      max_forward = i
    end

    -- Priority 2: Best match in same direction
    if target_offset ~= 0 and jump.offset ~= 0 then
      local same_direction = (target_offset > 0) == (jump.offset > 0)
      if same_direction then
        if
          not best_same_direction
          or (target_offset > 0 and jump.offset > jumps[best_same_direction].offset)
          or (target_offset < 0 and jump.offset < jumps[best_same_direction].offset)
        then
          best_same_direction = i
        end
      end
    end

    -- Priority 3: Current position
    if jump.offset == 0 then
      current_position = i
    end
  end

  -- Priority 4: Handle wrapping if enabled and no match found
  if wrap_edges and not best_same_direction then
    if target_offset > 0 and min_backward then
      -- Going forward but no forward jumps, wrap to furthest back
      return min_backward
    elseif target_offset < 0 and max_forward then
      -- Going backward but no backward jumps, wrap to furthest forward
      return max_forward
    end
  end

  return best_same_direction or current_position or 1
end

H.filters = {}

-- Filter status symbols
local FILTER_BRACKET_OPEN = '[' -- Filter status opening bracket
local FILTER_BRACKET_CLOSE = ']' -- Filter status closing bracket
local FILTER_SEPARATOR = ',' -- Filter indicator separator
local FILTER_FILE = 'f' -- File-only filter indicator
local FILTER_CWD = 'c' -- Current directory filter indicator
local FILTER_HIDDEN = '.' -- Show hidden filter indicator

---Apply filters to jump items
-- items: Jump items to filter
-- filters: Filter state
-- filter_context: Filter context with original_file and original_cwd
-- returns: Filtered jump items
function H.filters.apply(items, filters, filter_context)
  if not items or #items == 0 then
    return items
  end

  local filtered = {}
  -- Use stored context instead of runtime evaluation to avoid picker buffer context
  local current_file = filter_context and filter_context.original_file or vim.fn.expand('%:p')
  local cwd = filter_context and filter_context.original_cwd or vim.fn.getcwd()

  -- Normalize current file path for robust comparison
  current_file = H.utils.full_path(current_file)

  for _, item in ipairs(items) do
    local should_include = true

    -- File filter: only show jumps in current file
    local item_path = H.utils.full_path(item.path)
    if filters.file_only and item_path ~= current_file then
      should_include = false
    end

    -- CWD filter: only show jumps in current directory
    if should_include and filters.cwd_only then
      local item_dir = vim.fn.fnamemodify(item_path, ':h')
      if not vim.startswith(H.utils.full_path(item_dir), H.utils.full_path(cwd)) then
        should_include = false
      end
    end

    -- Hidden filter: hide hidden items unless show_hidden is true
    if should_include and not filters.show_hidden and item.hidden then
      should_include = false
    end

    if should_include then
      table.insert(filtered, item)
    end
  end

  return filtered
end

---Get filter status text for display
-- filters: Filter state
-- returns: Filter status text
function H.filters.get_status_text(filters)
  local parts = {}

  if filters.file_only then
    table.insert(parts, FILTER_FILE)
  end

  if filters.cwd_only then
    table.insert(parts, FILTER_CWD)
  end

  -- Show hidden status only when it's different from default (false)
  if filters.show_hidden then
    table.insert(parts, FILTER_HIDDEN)
  end

  if #parts == 0 then
    return ''
  end

  return FILTER_BRACKET_OPEN .. table.concat(parts, FILTER_SEPARATOR) .. FILTER_BRACKET_CLOSE .. ' '
end

---Toggle file-only filter state
-- filters: Filter state to modify
-- returns: Modified filter state
function H.filters.toggle_file(filters)
  filters.file_only = not filters.file_only
  return filters
end

---Toggle current working directory filter state
-- filters: Filter state to modify
-- returns: Modified filter state
function H.filters.toggle_cwd(filters)
  filters.cwd_only = not filters.cwd_only
  return filters
end

---Toggle show hidden items filter state
-- filters: Filter state to modify
-- returns: Modified filter state
function H.filters.toggle_hidden(filters)
  filters.show_hidden = not filters.show_hidden
  return filters
end

---Reset all filter states to defaults
-- filters: Filter state to reset
-- returns: Reset filter state
function H.filters.reset(filters)
  filters.file_only = false
  filters.cwd_only = false
  filters.show_hidden = false -- Default to hiding hidden items
  return filters
end

---Check if any filter is currently active
-- filters: Filter state to check
-- returns: True if any filter is active
function H.filters.is_active(filters)
  return filters.file_only or filters.cwd_only or filters.show_hidden
end

---Get list of currently active filters
-- filters: Filter state to check
-- returns: List of active filter names
function H.filters.get_active_list(filters)
  local active = {}
  if filters.file_only then
    table.insert(active, 'file_only')
  end
  if filters.cwd_only then
    table.insert(active, 'cwd_only')
  end
  if filters.show_hidden then
    table.insert(active, 'show_hidden')
  end
  return active
end

H.hide = {}

---Get hidden items from global variable (session-persistent)
-- Returns existing hidden items or empty table if none exist.
-- This function is read-only and never modifies the global variable.
-- Deserializes newline-separated string to table (Vim sessions only save strings/numbers).
-- returns: Hidden items keyed by path:lnum:col
function H.hide.load()
  local str = vim.g.Jumppack_hidden_items or ''
  if str == '' then
    return {}
  end

  local hidden = {}
  for _, key in ipairs(vim.split(str, '\n', { plain = true, trimempty = true })) do
    hidden[key] = true
  end
  return hidden
end

---Save hidden items to global variable (session-persistent)
-- This is the ONLY function that writes to the global variable.
-- The global variable is automatically saved/restored by :mksession when
-- 'globals' is in sessionoptions.
-- Serializes table to newline-separated string (Vim sessions only save strings/numbers).
-- hidden: Hidden items keyed by path:lnum:col
function H.hide.save(hidden)
  local keys = vim.tbl_keys(hidden)
  vim.g.Jumppack_hidden_items = table.concat(keys, '\n')
end

---Get hide key for jump item
-- item: Jump item
-- returns: Hide key
function H.hide.get_key(item)
  return item.path .. ':' .. item.lnum .. ':' .. item.col
end

---Check if item is hidden
-- item: Jump item
-- returns: True if hidden
function H.hide.is_hidden(item)
  local hidden = H.hide.load()
  local key = H.hide.get_key(item)
  return hidden[key] == true
end

---Toggle hide status for item
-- item: Jump item
-- returns: New hide status
function H.hide.toggle(item)
  local hidden = H.hide.load()
  local key = H.hide.get_key(item)

  if hidden[key] then
    hidden[key] = nil
  else
    hidden[key] = true
  end

  H.hide.save(hidden)
  return hidden[key] == true
end

---Mark items with their hide status
-- items: Jump items
-- returns: Items with hide status marked
function H.hide.mark_items(items)
  if not items then
    return items
  end

  local hidden = H.hide.load()

  for _, item in ipairs(items) do
    local key = H.hide.get_key(item)
    item.hidden = hidden[key] == true
  end

  return items
end

H.default_config = vim.deepcopy(Jumppack.config)

-- Namespaces
H.ns_id = {
  headers = vim.api.nvim_create_namespace('JumppackHeaders'),
  preview = vim.api.nvim_create_namespace('JumppackPreview'),
  ranges = vim.api.nvim_create_namespace('JumppackRanges'),
}

-- Timers
H.timers = {
  ---@diagnostic disable-next-line: undefined-field
  focus = vim.uv.new_timer(),
  ---@diagnostic disable-next-line: undefined-field
  getcharstr = vim.uv.new_timer(),
}

H.current_instance = nil

-- General purpose cache
H.cache = {}

---Setup and validate configuration
-- config: Configuration table
-- returns: Validated configuration
function H.config.setup(config)
  H.utils.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

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

  H.utils.check_type('window', config.window, 'table')
  local is_table_or_callable = function(x)
    return x == nil or type(x) == 'table' or vim.is_callable(x)
  end
  if not is_table_or_callable(config.window.config) then
    H.utils.error('setup(): window.config must be table or callable, got ' .. type(config.window.config))
  end

  return config
end

---Apply configuration to Jumppack
-- config: Configuration to apply
function H.config.apply(config)
  Jumppack.config = config
end

---Get merged configuration
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

--- Setup global key mappings that override default jump behavior
---
---@text Sets up global keymaps that replace Vim's default <C-o> and <C-i> jump
--- commands with Jumppack's enhanced interface. Only runs if global_mappings option
--- is enabled. The mappings support count prefixes (e.g., 3<C-o> for 3 jumps back).
---
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

---Validate picker options
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

-- Event loop configuration
local LOOP_MAX_ITERATIONS = 1000000 -- Prevent infinite loops in run_loop
local INPUT_DELAY_MS = 10 -- Responsive input without CPU spinning

-- Timer intervals
local FOCUS_CHECK_INTERVAL = 1000 -- Focus tracking timer interval (ms)

---Create new picker instance
-- opts: Validated picker options
-- returns: New picker instance
function H.instance.create(opts)
  -- Create buffer
  local buf_id = H.window.create_buffer()

  -- Create window and store original context
  local win_target = vim.api.nvim_get_current_win()
  -- Get the file path from the target window's buffer to ensure correct context
  local original_file = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win_target))
  local original_cwd = vim.fn.getcwd() -- Store current working directory
  local win_id = H.window.create_window(buf_id, opts.window.config, opts.source.cwd)

  -- Construct and return object
  local instance = {
    -- Permanent data about instance (should not change)
    opts = opts,

    -- Items to pick from
    items = nil,

    -- Associated Neovim objects
    buffers = { main = buf_id, preview = nil },
    windows = { main = win_id, target = win_target },

    -- Action keys which should be processed as described in mappings
    action_keys = H.config.normalize_mappings(opts.mappings),

    -- View data
    view_state = opts.options and opts.options.default_view or 'preview',
    visible_range = { from = nil, to = nil },
    current_ind = nil,
    shown_inds = {},

    -- Filter state
    filters = {
      file_only = false, -- Show only current file jumps
      cwd_only = false, -- Show only current directory jumps
      show_hidden = false, -- Hide hidden items by default
    },
    filter_context = {
      original_file = original_file, -- File that was active when picker started
      original_cwd = original_cwd, -- Working directory when picker started
    },

    -- Count accumulation for navigation
    pending_count = '',
    count_timer = nil,
  }

  return instance
end

---Run main picker event loop
-- instance: Picker instance
-- returns: Selected item or nil if aborted
function H.instance.run_loop(instance)
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', { pattern = 'JumppackStart' })
  end)

  local is_aborted = false
  ---@diagnostic disable-next-line: unused-local
  for _ = 1, LOOP_MAX_ITERATIONS do
    H.instance.update(instance)

    local char = H.utils.getcharstr(INPUT_DELAY_MS)
    is_aborted = char == nil
    if is_aborted then
      break
    end

    -- Handle count accumulation
    local is_digit = char >= '0' and char <= '9'
    if is_digit then
      -- Special handling for '0': only add to count if we're already building one
      if char == '0' and instance.pending_count == '' then
        -- '0' without existing count - check if it's mapped as an action
        local zero_action = instance.action_keys[char] or {}
        if zero_action.func then
          local should_stop = zero_action.func(instance, 1)
          if should_stop then
            break
          end
        end
      else
        -- Add digit to pending count
        instance.pending_count = instance.pending_count .. char

        -- Start/reset count timeout
        H.instance.start_count_timeout(instance)
      end
    else
      -- Non-digit character - execute action with accumulated count
      local cur_action = instance.action_keys[char] or {}
      is_aborted = cur_action.name == 'stop'

      if cur_action.func then
        -- Parse count, default to 1 if empty
        local count = tonumber(instance.pending_count) or 1
        -- Reset count after parsing
        instance.pending_count = ''

        -- Clear count timeout since action is being executed
        H.instance.clear_count_timeout(instance)

        local should_stop = cur_action.func(instance, count)
        if should_stop then
          break
        end
      else
        -- Unknown character - reset count
        instance.pending_count = ''
        H.instance.clear_count_timeout(instance)
      end
    end
  end

  local item
  if not is_aborted then
    item = H.instance.get_selection(instance)
  end
  H.instance.destroy(instance)
  return item
end

---Update picker instance display
-- instance: Picker instance
-- update_window: Whether to update window config
function H.instance.update(instance, update_window)
  if update_window then
    local config = H.window.compute_config(instance.opts.window.config)
    vim.api.nvim_win_set_config(instance.windows.main, config)
    H.instance.set_selection(instance, instance.current_ind, true)
  end
  H.display.update_border(instance)
  H.display.update_lines(instance)
  H.utils.redraw()
end

-- UI layout constants
local GOLDEN_RATIO = 0.618 -- Golden ratio for default window sizing
local WINDOW_ZINDEX = 251 -- Float window z-index for layering

---Create scratch buffer for picker
-- returns: Buffer ID
function H.window.create_buffer()
  local buf_id = H.utils.create_scratch_buf('main')
  vim.bo[buf_id].filetype = 'minipick'
  return buf_id
end

---Create floating window for picker
-- buf_id: Buffer ID to display
-- win_config: Window configuration
-- cwd: Current working directory
-- returns: Window ID
function H.window.create_window(buf_id, win_config, cwd)
  -- Hide cursor while instance is active (to not be visible in the window)
  -- This mostly follows a hack from 'folke/noice.nvim'
  H.cache.guicursor = vim.o.guicursor
  vim.o.guicursor = 'a:JumppackCursor'

  -- Create window and focus on it
  local win_id = vim.api.nvim_open_win(buf_id, true, H.window.compute_config(win_config, true))

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

---Compute window configuration
-- win_config: Window config or callable
-- is_for_open: Whether config is for opening window
-- returns: Computed window configuration
function H.window.compute_config(win_config, is_for_open)
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

---Track focus loss for picker instance
-- instance: Picker instance
function H.instance.track_focus(instance)
  local track = vim.schedule_wrap(function()
    local is_cur_win = vim.api.nvim_get_current_win() == instance.windows.main
    local is_proper_focus = is_cur_win and (H.cache.is_in_getcharstr or vim.fn.mode() ~= 'n')
    if is_proper_focus then
      return
    end
    if H.cache.is_in_getcharstr then
      -- sends <C-c>
      return vim.api.nvim_feedkeys('\3', 't', true)
    end
    H.instance.destroy(instance)
  end)
  H.timers.focus:start(FOCUS_CHECK_INTERVAL, FOCUS_CHECK_INTERVAL, track)
end

---Set items and initial selection for instance
-- instance: Picker instance
-- items: Jump items
-- initial_selection: Initial selection index
function H.instance.set_items(instance, items, initial_selection)
  -- Store original items before any filtering for session state
  instance.original_items = vim.deepcopy(items)
  instance.original_initial_selection = initial_selection

  -- Apply current filter settings to items immediately
  local filtered_items = H.filters.apply(items, instance.filters, instance.filter_context)
  instance.items = filtered_items

  if #filtered_items > 0 then
    -- Calculate initial selection that works with filtered items
    local initial_ind = H.instance.calculate_filtered_initial_selection(items, filtered_items, initial_selection)
    H.instance.set_selection(instance, initial_ind)
    -- Force update with the new index
    H.instance.set_selection(instance, initial_ind, true)
    -- Show preview by default instead of main
    H.display.render(instance)
  end

  H.instance.update(instance)
end

---Calculate initial selection when items are filtered
-- original_items: Original items
-- filtered_items: Filtered items
-- original_selection: Original selection index
-- returns: Adjusted selection index
function H.instance.calculate_filtered_initial_selection(original_items, filtered_items, original_selection)
  if not original_selection or original_selection <= 0 or #original_items == 0 then
    return 1
  end

  -- Clamp original selection to valid range
  local clamped_selection = math.min(original_selection, #original_items)
  local target_item = original_items[clamped_selection]

  -- Find the target item in filtered items
  for i, item in ipairs(filtered_items) do
    if item.path == target_item.path and item.lnum == target_item.lnum then
      return i
    end
  end

  -- If target not found, find closest by offset
  local target_offset = target_item.offset or 0
  local best_idx = 1
  local min_diff = math.abs(filtered_items[1].offset - target_offset)

  for i, item in ipairs(filtered_items) do
    local diff = math.abs((item.offset or 0) - target_offset)
    if diff < min_diff then
      min_diff = diff
      best_idx = i
    end
  end

  return best_idx
end

---Apply filters and update display
-- instance: Picker instance
function H.instance.apply_filters_and_update(instance)
  if not instance.original_items then
    -- Store original items on first filter
    instance.original_items = vim.deepcopy(instance.items)
  end

  -- Apply filters to original items
  local filtered_items = H.filters.apply(instance.original_items, instance.filters, instance.filter_context)

  -- Update items and preserve best selection after filtering
  instance.items = filtered_items

  if #filtered_items > 0 then
    -- Try to maintain current selection or find closest match
    local new_selection = H.instance.find_best_selection(instance, filtered_items)
    H.instance.set_selection(instance, new_selection, true)

    -- Preserve current view mode when applying filters
    H.display.render(instance)
  else
    -- Handle empty filter results gracefully
    -- Set minimal state to prevent errors
    instance.current_ind = nil
    instance.visible_range = { from = nil, to = nil }
    instance.shown_inds = {}

    -- Preserve current view mode even when no items match
    H.display.render(instance)
  end

  H.instance.update(instance)
end

---Find best selection index when items are filtered
-- instance: Picker instance
-- filtered_items: Filtered items
-- returns: Best selection index
function H.instance.find_best_selection(instance, filtered_items)
  if not instance.original_items or #filtered_items == 0 then
    return 1
  end

  -- Try to find the current item in the filtered list
  local current_item = instance.original_items[instance.current_ind or 1]
  if current_item then
    for i, item in ipairs(filtered_items) do
      if item.path == current_item.path and item.lnum == current_item.lnum then
        return i
      end
    end
  end

  -- If current item not found, find the closest by offset
  local current_offset = current_item and current_item.offset or 0
  local best_idx = 1
  local min_diff = math.abs(filtered_items[1].offset - current_offset)

  for i, item in ipairs(filtered_items) do
    local diff = math.abs(item.offset - current_offset)
    if diff < min_diff then
      min_diff = diff
      best_idx = i
    end
  end

  return best_idx
end

---Start or restart count timeout timer
-- instance: Picker instance
function H.instance.start_count_timeout(instance)
  -- Clear existing timer
  H.instance.clear_count_timeout(instance)

  -- Get timeout from config
  local timeout_ms = Jumppack.config.options.count_timeout_ms or 1000

  -- Start new timer
  instance.count_timer = vim.fn.timer_start(timeout_ms, function()
    instance.pending_count = ''
    instance.count_timer = nil
    H.display.render(instance)
  end)
end

---Clear count timeout timer
-- instance: Picker instance
function H.instance.clear_count_timeout(instance)
  if instance.count_timer then
    vim.fn.timer_stop(instance.count_timer)
    instance.count_timer = nil
  end
end

---Convert jump item to display string with format: [indicator] [icon] [path/name] [lnum:col]
-- item: Jump item to convert
-- opts: Display options with show_preview, show_icons, icons, cwd fields
-- returns: Display string
function H.display.item_to_string(item, opts)
  if not item then
    return ''
  end

  opts = opts or {}
  local show_preview = opts.show_preview ~= false -- Default to true
  local show_icons = opts.show_icons ~= false -- Default to true
  local icons = opts.icons or { file = ' ', none = '  ' }

  -- For jump items, construct the display text using format: [indicator] [icon] [path/name] [lnum:col]
  if item.offset ~= nil and item.lnum then
    -- Get indicator (hidden marker or position marker)
    local indicator
    if item.hidden then
      indicator = SYMBOL_HIDDEN
    else
      indicator = H.display.get_position_marker(item)
    end

    -- Get icon
    local icon = ''
    if show_icons then
      local icon_data = H.display.get_icon(item, icons)
      icon = icon_data.text or ' '
    end

    -- Get smart filename
    local filename = H.display.smart_filename(item.path, opts.cwd)

    -- Get position info
    local position = string.format('%d:%d', item.lnum, item.col or 1)

    -- Build core format: [indicator] [icon] [path/name] [lnum:col]
    local core_format = string.format('%s %s%s %s', indicator, icon, filename, position)

    if show_preview then
      -- List mode: add line preview after core format
      local line_content = H.display.get_line_preview(item)
      local separator = line_content ~= '' and SEPARATOR_SPACED or ''
      return string.format('%s%s%s', core_format, separator, line_content)
    else
      -- Preview mode or title: show only core format
      return core_format
    end
  end

  -- Fallback for non-jump items
  return item.text or tostring(item)
end

---Set current selection index
-- instance: Picker instance
-- ind: Selection index
-- force_update: Force visible range update
function H.instance.set_selection(instance, ind, force_update)
  -- Early validation - guard clause
  if not instance or not instance.items or #instance.items == 0 then
    if instance then
      instance.current_ind, instance.visible_range = nil, {}
    end
    return
  end

  -- Wrap index around edges (trusted state after validation)
  local n_matches = #instance.items
  ind = (ind - 1) % n_matches + 1

  -- (Re)Compute visible range (centers current index if it is currently outside)
  local from, to = instance.visible_range.from, instance.visible_range.to
  local needs_update = not from or not to or not (from <= ind and ind <= to)
  if (force_update or needs_update) and H.utils.is_valid_win(instance.windows.main) then
    local win_height = vim.api.nvim_win_get_height(instance.windows.main)
    to = math.min(n_matches, math.floor(ind + 0.5 * win_height))
    from = math.max(1, to - win_height + 1)
    to = from + math.min(win_height, n_matches) - 1
  end

  -- Set data
  instance.current_ind = ind
  instance.visible_range = { from = from, to = to }
end

---Update buffer lines with current items
-- instance: Picker instance
function H.display.update_lines(instance)
  -- Early validation - guard clauses
  if not instance then
    return
  end

  local buf_id, win_id = instance.buffers.main, instance.windows.main
  if not (H.utils.is_valid_buf(buf_id) and H.utils.is_valid_win(win_id)) then
    return
  end

  -- Handle empty items case - show message instead of returning early
  if not instance.items or #instance.items == 0 then
    local filter_status = H.filters.get_status_text(instance.filters)
    local empty_message = #filter_status > 0 and 'No matching items' or 'No items available'
    instance.shown_inds = {}

    -- Use source.show to display the empty message
    instance.opts.source.show(buf_id, { empty_message })
    return
  end

  local visible_range = instance.visible_range
  if not visible_range or visible_range.from == nil or visible_range.to == nil then
    instance.shown_inds = {}
    instance.opts.source.show(buf_id, {})
    return
  end

  -- Construct target items (validated state - no need for additional checks)
  local items_to_show, items, shown_inds = {}, instance.items, {}
  local cur_ind, cur_line = instance.current_ind, nil
  local from, to = visible_range.from, visible_range.to
  for i = from, to, (from <= to and 1 or -1) do
    table.insert(shown_inds, i)
    table.insert(items_to_show, items[i])
    if i == cur_ind then
      cur_line = #items_to_show
    end
  end

  -- Update visible lines accounting for "from_bottom" direction
  instance.shown_inds = shown_inds
  instance.opts.source.show(buf_id, items_to_show)

  local ns_id = H.ns_id.ranges
  H.utils.clear_namespace(buf_id, ns_id)

  -- Update current item
  if cur_line > vim.api.nvim_buf_line_count(buf_id) then
    return
  end

  local cur_opts = {
    end_row = cur_line,
    end_col = 0,
    hl_eol = true,
    hl_group = 'JumppackMatchCurrent',
    priority = PRIORITY_CURRENT_MATCH,
  }
  H.utils.set_extmark(buf_id, ns_id, cur_line - 1, 0, cur_opts)
end

---Normalize key mappings for actions
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

---Update window border text
-- instance: Picker instance
function H.display.update_border(instance)
  local win_id = instance.windows.main
  if not H.utils.is_valid_win(win_id) then
    return
  end

  -- Compute main text managing views separately and truncating from left
  local view_state, win_width = instance.view_state, vim.api.nvim_win_get_width(win_id)
  local config = {}

  -- Only show title in preview mode
  if view_state == 'preview' then
    local has_items = instance.items
    if has_items and instance.current_ind then
      local current_item = instance.items[instance.current_ind]
      if current_item then
        -- For preview mode title, don't show line content but include icon and position
        local stritem_cur = H.display.item_to_string(current_item, {
          show_preview = false,
          show_icons = true,
          icons = { file = ' ', none = '  ' },
          cwd = instance.opts.source.cwd,
        }) or ''
        -- Sanitize title
        stritem_cur = stritem_cur:gsub('%z', SYMBOL_SEPARATOR):gsub('%s', ' ')
        config = { title = { { H.utils.fit_to_width(' ' .. stritem_cur .. ' ', win_width), 'JumppackBorderText' } } }
      end
    end
  else
    -- Explicitly clear title in list mode
    config.title = ''
  end

  -- Compute helper footer
  local nvim_has_window_footer = vim.fn.has('nvim-0.10') == 1
  if nvim_has_window_footer then
    config.footer, config.footer_pos = H.display.compute_footer(instance, win_id), 'left'
  end

  vim.api.nvim_win_set_config(win_id, config)
  vim.wo[win_id].list = true
end

---Compute footer content for window
-- instance: Picker instance
-- win_id: Window ID
-- returns: Footer content
function H.display.compute_footer(instance, win_id)
  local info = H.display.get_general_info(instance)
  local source_name = string.format(' %s ', info.source_name)
  local status_text = string.format(' %s ', info.status_text) -- Format: ↑3●↓4 │ [f][c] (selected item position)

  local win_width = vim.api.nvim_win_get_width(win_id)
  local source_width = vim.fn.strchars(source_name)
  local status_width = vim.fn.strchars(status_text)

  local footer = { { H.utils.fit_to_width(source_name, win_width), 'JumppackBorderText' } }
  local n_spaces_between = win_width - (source_width + status_width)
  if n_spaces_between > 0 then
    footer[2] = { H.utils.win_get_bottom_border(win_id):rep(n_spaces_between), 'JumppackBorder' }
    footer[3] = { status_text, 'JumppackBorderText' }
  end
  return footer
end

---Destroy picker instance and cleanup
-- instance: Picker instance
function H.instance.destroy(instance)
  vim.tbl_map(function(timer)
    ---@diagnostic disable-next-line: undefined-field
    pcall(vim.uv.timer_stop, timer)
  end, H.timers)

  -- Show cursor (work around `guicursor=''` actually leaving cursor hidden)
  if H.cache.guicursor == '' then
    vim.cmd('set guicursor=a: | redraw')
  end
  pcall(function()
    vim.o.guicursor = H.cache.guicursor
  end)

  if instance == nil then
    return
  end

  vim.api.nvim_exec_autocmds('User', { pattern = 'JumppackStop' })
  H.current_instance = nil

  H.utils.set_curwin(instance.windows.target)
  pcall(vim.api.nvim_win_close, instance.windows.main, true)
  pcall(vim.api.nvim_buf_delete, instance.buffers.main, { force = true })
  instance.windows, instance.buffers = {}, {}
end

H.actions = {
  jump_back = function(instance, count)
    -- Navigate backwards in jump history with count support
    local move_count = count or 1
    H.instance.move_selection(instance, move_count) -- Positive = backward in time
  end,
  jump_forward = function(instance, count)
    -- Navigate forwards in jump history with count support
    local move_count = -(count or 1)
    H.instance.move_selection(instance, move_count) -- Negative = forward in time
  end,

  choose = function(instance, _)
    return H.actions.choose(instance, nil)
  end,
  choose_in_split = function(instance, _)
    return H.actions.choose(instance, 'split')
  end,
  choose_in_tabpage = function(instance, _)
    return H.actions.choose(instance, 'tab split')
  end,
  choose_in_vsplit = function(instance, _)
    return H.actions.choose(instance, 'vsplit')
  end,

  toggle_preview = function(instance, _)
    if instance.view_state == 'preview' then
      return H.display.render_list(instance)
    end
    H.display.render_preview(instance)
  end,

  stop = function(instance, _)
    -- If count is being accumulated, clear it instead of closing picker
    if instance.pending_count ~= '' then
      instance.pending_count = ''
      if instance.count_timer then
        vim.fn.timer_stop(instance.count_timer)
        instance.count_timer = nil
      end
      H.display.render(instance)
      return false -- Don't close picker
    end
    return true -- Close picker
  end,

  -- Filter actions
  toggle_file_filter = function(instance, _)
    H.filters.toggle_file(instance.filters)
    H.instance.apply_filters_and_update(instance)
  end,

  toggle_cwd_filter = function(instance, _)
    H.filters.toggle_cwd(instance.filters)
    H.instance.apply_filters_and_update(instance)
  end,

  toggle_show_hidden = function(instance, _)
    H.filters.toggle_hidden(instance.filters)
    H.instance.apply_filters_and_update(instance)
  end,

  reset_filters = function(instance, _)
    H.filters.reset(instance.filters)
    H.instance.apply_filters_and_update(instance)
  end,

  -- Hide actions
  toggle_hidden = function(instance, _)
    local cur_item = H.instance.get_selection(instance)
    if not cur_item then
      return
    end

    -- Toggle hide status in session storage
    local new_status = H.hide.toggle(cur_item)

    -- Re-mark all items with updated hidden status from storage
    -- This ensures both current items AND original_items reflect the change
    H.hide.mark_items(instance.items)
    if instance.original_items then
      H.hide.mark_items(instance.original_items)
    end

    -- Apply filters to update both list and preview views
    -- This will hide the item if show_hidden = false (default)
    H.instance.apply_filters_and_update(instance)

    -- After filtering, adjust selection if the current item was hidden and removed from view
    if new_status and not instance.filters.show_hidden and #instance.items > 0 then
      -- Ensure we have a valid current selection after filtering
      local current = instance.current or 1

      -- If current selection is beyond available items, adjust to last item
      if current > #instance.items then
        H.instance.set_selection(instance, #instance.items, true)
      elseif current < 1 then
        -- If no valid selection, select first item
        H.instance.set_selection(instance, 1, true)
      end

      -- Re-render to reflect changes
      H.display.render(instance)
    end
  end,

  jump_to_top = function(instance, _)
    -- Jump to the first item in the jumplist (ignores count)
    H.instance.move_selection(instance, 0, 1)
  end,

  jump_to_bottom = function(instance, _)
    -- Jump to the last item in the jumplist (ignores count)
    if instance.items and #instance.items > 0 then
      H.instance.move_selection(instance, 0, #instance.items)
    end
  end,
}

---Choose current item with optional pre-command
-- instance: Picker instance
-- pre_command: Command to execute before choosing
-- returns: True if should stop picker
function H.actions.choose(instance, pre_command)
  -- Early validation - guard clause
  local cur_item = H.instance.get_selection(instance)
  if not cur_item then
    return true
  end

  local win_id_target = instance.windows.target
  if
    pre_command ~= nil
    and type(pre_command) == 'string'
    and pre_command ~= ''
    and H.utils.is_valid_win(win_id_target)
  then
    -- Work around Neovim not preserving cwd during `nvim_win_call`
    -- See: https://github.com/neovim/neovim/issues/32203
    local instance_cwd, global_cwd = vim.fn.getcwd(0), vim.fn.getcwd(-1, -1)
    vim.fn.chdir(global_cwd)
    vim.api.nvim_win_call(win_id_target, function()
      vim.cmd(pre_command)
      instance.windows.target = vim.api.nvim_get_current_win()
    end)
    vim.fn.chdir(instance_cwd)
  end

  local ok, res = pcall(instance.opts.source.choose, cur_item)
  -- Delay error to have time to hide instance window
  if not ok then
    vim.schedule(function()
      H.utils.error('choose_with_action(): Error during choose action:\n' .. res)
    end)
  end
  -- Error or returning nothing, `nil`, or `false` should lead to instance stop
  return not (ok and res)
end

---Move current selection by offset or to position
-- instance: Picker instance
-- by: Movement offset
-- to: Target position
function H.instance.move_selection(instance, by, to)
  -- Early validation - guard clauses
  if not instance or not instance.items or #instance.items == 0 then
    return
  end

  local n_matches = #instance.items

  if to == nil then
    local wrap_edges = Jumppack.config.options and Jumppack.config.options.wrap_edges
    to = instance.current_ind

    if wrap_edges then
      -- Wrap around edges when enabled
      if to == 1 and by < 0 then
        to = n_matches
      elseif to == n_matches and by > 0 then
        to = 1
      else
        to = to + by
      end
    else
      -- No wrapping when disabled - clamp to edges
      to = to + by
    end

    to = math.min(math.max(to, 1), n_matches)
  end

  H.instance.set_selection(instance, to)

  -- Update not main buffer(s)
  if instance.view_state == 'preview' then
    H.display.render_preview(instance)
  end
end

---Get currently selected item
-- instance: Picker instance
-- returns: Current selection or nil
function H.instance.get_selection(instance)
  -- Early validation - return nil for invalid state
  if not instance or not instance.items or #instance.items == 0 then
    return nil
  end
  return instance.items[instance.current_ind]
end

---Render list buffer view
-- instance: Picker instance
function H.display.render_list(instance)
  H.utils.set_winbuf(instance.windows.main, instance.buffers.main)
  instance.view_state = 'list'
  H.display.update_border(instance)
end

---Render current view based on instance view state
-- instance: Picker instance
function H.display.render(instance)
  if instance.view_state == 'preview' then
    H.display.render_preview(instance)
  else
    H.display.render_list(instance)
  end
end

---Get general information about picker state
-- instance: Picker instance
-- returns: General information including position indicator for selected item
function H.display.get_general_info(instance)
  local has_items = instance.items

  -- Calculate position information (↑N●↓N format) based on selected item
  local position_indicator = SYMBOL_CURRENT

  if has_items and instance.items then
    -- Count items before/after the currently selected item in picker
    local selected_index = instance.current_ind or 1
    local up_count = selected_index - 1
    local down_count = #instance.items - selected_index

    -- Include pending count directly in position indicator for compact display
    if instance.pending_count ~= '' then
      position_indicator = string.format(
        SYMBOL_UP .. '%d' .. SYMBOL_CURRENT .. SYMBOL_DOWN .. '%d×%s',
        up_count,
        down_count,
        instance.pending_count
      )
    else
      position_indicator =
        string.format(SYMBOL_UP .. '%d' .. SYMBOL_CURRENT .. SYMBOL_DOWN .. '%d', up_count, down_count)
    end
  end

  -- Build filter indicators
  local filter_text = H.filters.get_status_text(instance.filters)
  if filter_text ~= '' then
    filter_text = SEPARATOR_SPACED .. filter_text
  end

  -- Note: Pending count is now integrated into position_indicator for compact display

  return {
    -- Keep existing fields for backward compatibility
    source_name = instance.opts.source.name or '---',
    source_cwd = vim.fn.fnamemodify(instance.opts.source.cwd, ':~') or '---',
    n_total = has_items and #instance.items or '-',
    relative_current_ind = has_items and instance.current_ind or '-',

    -- New fields for enhanced display
    position_indicator = position_indicator,
    filter_indicator = filter_text,
    status_text = position_indicator .. filter_text,
  }
end

---Render preview buffer view
-- instance: Picker instance
function H.display.render_preview(instance)
  -- Early validation - guard clause
  local item = H.instance.get_selection(instance)
  if not item then
    return
  end

  local preview = instance.opts.source.preview

  local win_id, buf_id = instance.windows.main, H.utils.create_scratch_buf('preview')
  vim.bo[buf_id].bufhidden = 'wipe'
  H.utils.set_winbuf(win_id, buf_id)
  preview(buf_id, item)
  instance.buffers.preview = buf_id
  instance.view_state = 'preview'
  H.display.update_border(instance)
end

---Get icon for item
-- item: Item to get icon for
-- icons: Icon configuration
-- returns: Icon data with text and highlight
function H.display.get_icon(item, icons)
  local path = item.path or ''
  local path_type = H.utils.get_fs_type(path)
  if path_type == 'none' then
    return { text = icons.none, hl = 'JumppackNormal' }
  end

  ---@diagnostic disable-next-line: undefined-field
  if _G.MiniIcons ~= nil then
    local category = path_type == 'directory' and 'directory' or 'file'
    ---@diagnostic disable-next-line: undefined-field
    local icon, hl = _G.MiniIcons.get(category, path)
    return { text = icon .. ' ', hl = hl }
  end

  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
  if not has_devicons then
    return { text = icons.file, hl = 'JumppackIconFile' }
  end

  local icon, hl = devicons.get_icon(vim.fn.fnamemodify(path, ':t'), nil, { default = false })
  icon = type(icon) == 'string' and (icon .. ' ') or icons.file
  return { text = icon, hl = hl or 'JumppackIconFile' }
end

---Get filesystem type for path
-- path: File path
-- returns: Type: 'file', 'directory', or 'none'
function H.utils.get_fs_type(path)
  if path == '' then
    return 'none'
  end
  if vim.fn.filereadable(path) == 1 then
    return 'file'
  end
  if vim.fn.isdirectory(path) == 1 then
    return 'directory'
  end
  return 'none'
end

--- Set lines in preview buffer with syntax highlighting
-- buf_id: Preview buffer id
-- lines: Lines to display
-- extra: Extra info with lnum, col, end_lnum, end_col, filetype, path
function H.display.preview_set_lines(buf_id, lines, extra)
  -- Lines
  H.utils.set_buflines(buf_id, lines)

  -- Highlighting
  H.display.preview_highlight_region(buf_id, extra.lnum, extra.col, extra.end_lnum, extra.end_col)

  if H.display.preview_should_highlight(buf_id) then
    local ft = extra.filetype or vim.filetype.match({ buf = buf_id, filename = extra.path })
    local has_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
    lang = has_lang and lang or ft
    -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
    local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, lang, { error = false })
    has_parser = has_parser and parser ~= nil
    if has_parser then
      has_parser = pcall(vim.treesitter.start, buf_id, lang)
    end
    if not has_parser and ft then
      vim.bo[buf_id].syntax = ft
    end
  end

  -- Cursor position and window view. Find window (and not use instance window)
  -- for "outside window preview" (preview and main are different) to work.
  local win_id = vim.fn.bufwinid(buf_id)
  if win_id == -1 then
    return
  end
  H.utils.set_cursor(win_id, extra.lnum, extra.col)
  local pos_keys = ({ top = 'zt', center = 'zz', bottom = 'zb' })[extra.line_position] or 'zt'
  pcall(vim.api.nvim_win_call, win_id, function()
    vim.cmd('normal! ' .. pos_keys)
  end)
end

--- Check if preview buffer should be syntax highlighted based on size limits
-- buf_id: Buffer id to check
-- returns: # True if buffer should be highlighted
function H.display.preview_should_highlight(buf_id)
  -- Highlight if buffer size is not too big, both in total and per line
  local buf_size = vim.api.nvim_buf_call(buf_id, function()
    return vim.fn.line2byte(vim.fn.line('$') + 1)
  end)
  return buf_size <= HIGHLIGHT_MAX_FILESIZE and buf_size <= HIGHLIGHT_MAX_LINES * vim.api.nvim_buf_line_count(buf_id)
end

--- Highlight specific region in preview buffer
-- buf_id: Buffer id to highlight in
-- lnum: Line number to highlight (1-indexed)
-- col: Column number for region start
-- end_lnum: End line number for region
-- end_col: End column number for region
function H.display.preview_highlight_region(buf_id, lnum, col, end_lnum, end_col)
  -- Highlight line
  if lnum == nil then
    return
  end
  local hl_line_opts =
    { end_row = lnum, end_col = 0, hl_eol = true, hl_group = 'JumppackPreviewLine', priority = PRIORITY_PREVIEW_LINE }
  H.utils.set_extmark(buf_id, H.ns_id.preview, lnum - 1, 0, hl_line_opts)

  -- Highlight position/region
  if col == nil then
    return
  end

  local ext_end_row, ext_end_col = lnum - 1, col
  if end_lnum ~= nil and end_col ~= nil then
    ext_end_row, ext_end_col = end_lnum - 1, end_col - 1
  end
  local bufline = vim.fn.getbufline(buf_id, ext_end_row + 1)[1]
  ext_end_col = H.utils.get_next_char_bytecol(bufline, ext_end_col)

  local hl_region_opts = { end_row = ext_end_row, end_col = ext_end_col, priority = PRIORITY_REGION }
  hl_region_opts.hl_group = 'JumppackPreviewRegion'
  H.utils.set_extmark(buf_id, H.ns_id.preview, lnum - 1, col - 1, hl_region_opts)
end

---Display error message
-- msg: Error message
function H.utils.error(msg)
  error('(jumppack) ' .. msg, 0)
end

---Check value type and error if invalid
-- name: Parameter name
-- val: Value to check
-- ref: Expected type
-- allow_nil: Allow nil values
function H.utils.check_type(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then
    return
  end
  H.utils.error(string.format('check_type(): %s must be %s, got %s', name, ref, type(val)))
end

function H.utils.set_buf_name(buf_id, name)
  vim.api.nvim_buf_set_name(buf_id, 'jumppack://' .. buf_id .. '/' .. name)
end

---Display notification message
-- msg: Message to display
-- level_name: Log level name
function H.utils.notify(msg, level_name)
  vim.notify('(jumppack) ' .. msg, vim.log.levels[level_name])
end

---Check if buffer ID is valid
-- buf_id: Buffer ID
-- returns: True if valid
function H.utils.is_valid_buf(buf_id)
  return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id)
end

---Check if window ID is valid
-- win_id: Window ID
-- returns: True if valid
function H.utils.is_valid_win(win_id)
  return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id)
end

---Create scratch buffer
-- name: Buffer name
-- returns: Buffer ID
function H.utils.create_scratch_buf(name)
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.utils.set_buf_name(buf_id, name)
  vim.bo[buf_id].matchpairs = ''
  vim.b[buf_id].minicursorword_disable = true
  vim.b[buf_id].miniindentscope_disable = true
  return buf_id
end

--- Safely set buffer lines (ignores errors from invalid buffers)
-- buf_id: Buffer id
-- lines: Lines to set
function H.utils.set_buflines(buf_id, lines)
  pcall(vim.api.nvim_buf_set_lines, buf_id, 0, -1, false, lines)
end

--- Set window buffer
-- win_id: Window id
-- buf_id: Buffer id to set
function H.utils.set_winbuf(win_id, buf_id)
  vim.api.nvim_win_set_buf(win_id, buf_id)
end

--- Safely set extmark (ignores errors from invalid buffers)
-- Arguments passed to nvim_buf_set_extmark
function H.utils.set_extmark(...)
  pcall(vim.api.nvim_buf_set_extmark, ...)
end

function H.utils.set_cursor(win_id, lnum, col)
  pcall(vim.api.nvim_win_set_cursor, win_id, { lnum or 1, (col or 1) - 1 })
end

function H.utils.set_curwin(win_id)
  if not H.utils.is_valid_win(win_id) then
    return
  end
  -- Explicitly preserve cursor to fix Neovim<=0.9 after choosing position in
  -- already shown buffer
  local cursor = vim.api.nvim_win_get_cursor(win_id)
  vim.api.nvim_set_current_win(win_id)
  H.utils.set_cursor(win_id, cursor[1], cursor[2] + 1)
end

function H.utils.clear_namespace(buf_id, ns_id)
  pcall(vim.api.nvim_buf_clear_namespace, buf_id, ns_id, 0, -1)
end

function H.utils.replace_termcodes(x)
  if x == nil then
    return nil
  end
  return vim.api.nvim_replace_termcodes(x, true, true, true)
end

function H.utils.expand_callable(x, ...)
  if vim.is_callable(x) then
    return x(...)
  end
  return x
end

function H.utils.redraw()
  vim.cmd('redraw')
end

H.redraw_scheduled = vim.schedule_wrap(H.utils.redraw)

function H.utils.getcharstr(delay_async)
  H.timers.getcharstr:start(0, delay_async, H.redraw_scheduled)
  H.cache.is_in_getcharstr = true
  local ok, char = pcall(vim.fn.getcharstr)
  H.cache.is_in_getcharstr = nil
  H.timers.getcharstr:stop()

  local main_win_id
  if H.current_instance ~= nil then
    main_win_id = H.current_instance.windows.main
  end
  local is_bad_mouse_click = vim.v.mouse_winid ~= 0 and vim.v.mouse_winid ~= main_win_id
  if not ok or char == '' or char == '\3' or is_bad_mouse_click then
    return
  end
  return char
end

function H.utils.win_update_hl(win_id, new_from, new_to)
  if not H.utils.is_valid_win(win_id) then
    return
  end

  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local new_winhighlight, n_replace = vim.wo[win_id].winhighlight:gsub(replace_pattern, new_entry)
  if n_replace == 0 then
    new_winhighlight = new_winhighlight .. ',' .. new_entry
  end

  vim.wo[win_id].winhighlight = new_winhighlight
end

function H.utils.fit_to_width(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

function H.utils.win_get_bottom_border(win_id)
  local border = vim.api.nvim_win_get_config(win_id).border or {}
  local res = border[6]
  if type(res) == 'table' then
    res = res[1]
  end
  return res or ' '
end

function H.utils.win_set_cwd(win_id, cwd)
  -- Avoid needlessly setting cwd as it has side effects (like for `:buffers`)
  if cwd == nil or vim.fn.getcwd(win_id or 0) == cwd then
    return
  end
  local f = function()
    vim.cmd('lcd ' .. vim.fn.fnameescape(cwd))
  end
  if win_id == nil or win_id == vim.api.nvim_get_current_win() then
    return f()
  end
  vim.api.nvim_win_call(win_id, f)
end

function H.utils.get_next_char_bytecol(line_str, col)
  if type(line_str) ~= 'string' then
    return col
  end
  local utf_index = vim.str_utfindex(line_str, math.min(line_str:len(), col))
  ---@diagnostic disable-next-line: missing-parameter, param-type-mismatch
  return vim.str_byteindex(line_str, utf_index, true)
end

function H.utils.full_path(path)
  return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1'))
end

---==============================================================================
---
---vim:tw=78:ts=8:ft=help:norl:

return Jumppack
