---@brief [[Jumppack.nvim - Enhanced jumplist navigation for Neovim]]
---
---Jumppack provides an enhanced navigation interface for Neovim's jumplist.
---The plugin creates a floating window picker that allows users to visualize
---and navigate their jump history with preview functionality.
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

---@class ConfigWindow
---@field config table|function|nil Float window config

---@class JumpItem
---@field bufnr number Buffer number
---@field path string File path
---@field lnum number Line number
---@field col number Column number
---@field jump_index number Index in jumplist
---@field is_current boolean Whether this is current position
---@field offset number Navigation offset

---@class Instance
---@field opts table Configuration options
---@field items JumpItem[] List of jump items
---@field buffers table Buffer IDs
---@field windows table Window IDs
---@field action_keys table Action key mappings
---@field view_state string Current view state
---@field visible_range table Visible range info
---@field current_ind number Current item index
---@field shown_inds number[] Shown item indices

---@class PickerState
---@field items JumpItem[] Available jump items
---@field selection table Current selection info
---@field general_info table General picker information

-- ============================================================================
-- PUBLIC API
-- ============================================================================

local Jumppack = {}

-- ============================================================================
-- INTERNAL MODULES
-- ============================================================================

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
---@param config Config|nil Configuration table with options, mappings, and window settings
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
--- -- Custom configuration with global mappings enabled (default)
--- require('jumppack').setup({
---   options = {
---     cwd_only = true,        -- Only show jumps within current working directory
---     wrap_edges = true,      -- Allow wrapping when navigating with enhanced <C-o>/<C-i>
---     default_view = 'list',  -- Start interface in list mode instead of preview
---     global_mappings = true  -- Override default jump keys (this is the default)
---   },
---   mappings = {
---     jump_back = '<Leader>o',    -- Custom back navigation
---     jump_forward = '<Leader>i', -- Custom forward navigation
---     choose = '<CR>',            -- Choose item
---     choose_in_split = '<C-s>',  -- Open in horizontal split
---     choose_in_vsplit = '<C-v>', -- Open in vertical split
---     choose_in_tabpage = '<C-t>',-- Open in new tab
---     stop = '<Esc>',             -- Close picker
---     toggle_preview = '<C-p>'    -- Toggle preview mode
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
  },
  -- Keys for performing actions. See `:h Jumppack-actions`.
  mappings = {
    jump_back = '<C-o>',
    jump_forward = '<C-i>',

    choose = '<CR>',
    choose_in_split = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit = '<C-v>',

    stop = '<Esc>',

    toggle_preview = '<C-p>',
  },

  -- Window related options
  window = {
    -- Float window config (table or callable returning it)
    config = nil,
  },
}

--- Start the jumplist navigation interface
---
---@text Opens the jumplist navigation interface with a floating window. Displays available
--- jump positions with navigation preview. Supports directional navigation with offsets
--- and filtering options. The interface allows interactive selection and navigation
--- through your jump history with vim.jumplist.
---
---@param opts table|nil Navigation options with the following fields:
---   - offset (number): Navigation offset from current position. Negative for backward
---     jumps (e.g., -1 for previous position), positive for forward jumps (e.g., 1 for next).
---     If offset exceeds available range, falls back to nearest valid position.
---   - source (table): Custom source configuration (advanced usage)
---
---@return JumpItem|nil Selected jump item if user chose one, nil if cancelled
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

  -- Validate opts type early
  if opts ~= nil and type(opts) ~= 'table' then
    H.utils.error('Jumppack options should be table.')
  end

  opts = opts or {}

  -- Create jumplist source
  local jumplist_source = H.jumplist.create_source(opts)
  if not jumplist_source then
    H.utils.notify('No jumps available')
    return -- No jumps available
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

-- ============================================================================
-- DISPLAY & RENDERING FUNCTIONS
-- ============================================================================

--- Display items in a buffer with syntax highlighting
---
---@text Renders jump items in the navigation buffer with file icons and syntax highlighting.
--- Handles item formatting, icon display, and visual presentation. This is the main
--- function used by the interface to show the jumplist entries.
---
---@param buf_id number Buffer ID to display items in
---@param items JumpItem[] List of jump items to display with path, line, and offset info
---@param opts table|nil Display options with fields:
---   - show_icons (boolean): Whether to show file type icons (default: true)
---   - icons (table): Custom icon mapping for file types
---
---@usage >lua
--- -- Display items with default options
--- local buf = vim.api.nvim_create_buf(false, true)
--- local items = {
---   { path = 'init.lua', lnum = 1, offset = -1, direction = 'back' },
---   { path = 'config.lua', lnum = 15, offset = 1, direction = 'forward' }
--- }
--- Jumppack.show_items(buf, items)
---
--- -- Custom display options
--- Jumppack.show_items(buf, items, {
---   show_icons = false,  -- Disable file icons
---   icons = { file = '📄', none = '  ' }  -- Custom icons
--- })
--- <
---
---@seealso |jumppack-display| For display customization options
function Jumppack.show_items(buf_id, items, opts)
  local default_icons = { file = ' ', none = '  ' }
  opts = vim.tbl_deep_extend('force', { show_icons = true, icons = default_icons }, opts or {})

  -- Compute and set lines. Compute prefix based on the whole items to allow
  -- separate `text` and `path` table fields (preferring second one).
  local get_prefix_data = opts.show_icons and function(item)
    return H.display.get_icon(item, opts.icons)
  end or function()
    return { text = '' }
  end
  local prefix_data = vim.tbl_map(get_prefix_data, items)

  local lines = vim.tbl_map(H.display.item_to_string, items)
  local tab_spaces = string.rep(' ', vim.o.tabstop)
  lines = vim.tbl_map(function(l)
    return l:gsub('%z', '│'):gsub('[\r\n]', ' '):gsub('\t', tab_spaces)
  end, lines)

  local lines_to_show = {}
  for i, l in ipairs(lines) do
    lines_to_show[i] = prefix_data[i].text .. l
  end

  H.utils.set_buflines(buf_id, lines_to_show)

  -- Extract match ranges
  local ns_id = H.ns_id.ranges
  H.utils.clear_namespace(buf_id, ns_id)

  -- Highlight prefixes
  if not opts.show_icons then
    return
  end
  local icon_extmark_opts = { hl_mode = 'combine', priority = 200 }
  for i = 1, #prefix_data do
    icon_extmark_opts.hl_group = prefix_data[i].hl
    icon_extmark_opts.end_row, icon_extmark_opts.end_col = i - 1, prefix_data[i].text:len()
    H.utils.set_extmark(buf_id, ns_id, i - 1, 0, icon_extmark_opts)
  end
end

--- Preview a jump item in a buffer
---
---@text Displays a preview of the jump destination in the preview buffer. Shows the
--- content around the jump target with syntax highlighting and cursor positioning.
--- Used by the interface's preview mode to show file content before navigation.
---
---@param buf_id number Buffer ID for preview content (must be a valid buffer)
---@param item JumpItem|nil Jump item to preview. If nil, clears the preview buffer
---@param opts table|nil Preview options with fields:
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
    end_lnum = item.end_lnum,
    end_col = item.end_col,
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
---@param item JumpItem Jump item to navigate to with offset field for direction:
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
      vim.cmd(string.format([[execute "normal\! %d\<C-o>"]], math.abs(item.offset)))
    elseif item.offset > 0 then
      vim.cmd(string.format([[execute "normal\! %d\<C-i>"]], item.offset))
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
---@return boolean True if interface is active, false otherwise
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
function Jumppack.is_active()
  return H.current_instance ~= nil
end

--- Get the current state of the active navigation interface
---
---@text Retrieves the current state of the active interface instance, including items,
--- selection, and general information. Returns nil if no interface is active. Useful
--- for inspecting interface state and implementing custom behaviors.
---
---@return PickerState|nil Current interface state with fields:
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
---@param opts table Picker options
---@return table|nil Jumplist source or nil if no jumps
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
---@param config Config|nil Configuration
---@return JumpItem[] List of valid jump items
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

  return reversed_jumps
end

---Create jump item from jumplist entry
---@param jump table Vim jumplist entry
---@param i number Jump index
---@param current number Current position index
---@return JumpItem|nil Jump item or nil if invalid
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
---@param jumps JumpItem[] Available jump items
---@param target_offset number Target navigation offset
---@param config Config Configuration
---@return number Index of best matching jump
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

-- ============================================================================
-- CONFIGURATION MANAGEMENT
-- ============================================================================

H.default_config = vim.deepcopy(Jumppack.config)

-- Namespaces
H.ns_id = {
  headers = vim.api.nvim_create_namespace('JumppackHeaders'),
  preview = vim.api.nvim_create_namespace('JumppackPreview'),
  ranges = vim.api.nvim_create_namespace('JumppackRanges'),
}

-- Timers
H.timers = {
  focus = vim.uv.new_timer(),
  getcharstr = vim.uv.new_timer(),
}

H.current_instance = nil

-- General purpose cache
H.cache = {}

---Setup and validate configuration
---@param config Config|nil Configuration table
---@return Config Validated configuration
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

  H.utils.check_type('options', config.options, 'table')
  H.utils.check_type('options.global_mappings', config.options.global_mappings, 'boolean')
  H.utils.check_type('options.cwd_only', config.options.cwd_only, 'boolean')
  H.utils.check_type('options.wrap_edges', config.options.wrap_edges, 'boolean')
  H.utils.check_type('options.default_view', config.options.default_view, 'string')
  if not vim.tbl_contains({ 'list', 'preview' }, config.options.default_view) then
    H.utils.error('`options.default_view` should be "list" or "preview", not "' .. config.options.default_view .. '"')
  end

  H.utils.check_type('window', config.window, 'table')
  local is_table_or_callable = function(x)
    return x == nil or type(x) == 'table' or vim.is_callable(x)
  end
  if not is_table_or_callable(config.window.config) then
    H.utils.error('`window.config` should be table or callable, not ' .. type(config.window.config))
  end

  return config
end

---Apply configuration to Jumppack
---@param config Config Configuration to apply
function H.config.apply(config)
  Jumppack.config = config
end

---Get merged configuration
---@param config Config|nil Override configuration
---@return Config Merged configuration
function H.config.get(config)
  return vim.tbl_deep_extend('force', Jumppack.config, vim.b.minipick_config or {}, config or {})
end

---Setup autocommands for Jumppack
function H.config.setup_autocommands()
  local gr = vim.api.nvim_create_augroup('Jumppack', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('VimResized', '*', Jumppack.refresh, 'Refresh on resize')
  au('ColorScheme', '*', H.config.setup_highlights, 'Ensure colors')
end

---Setup default highlight groups
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
end

--- Setup global key mappings that override default jump behavior
---
---@text Sets up global keymaps that replace Vim's default <C-o> and <C-i> jump
--- commands with Jumppack's enhanced interface. Only runs if global_mappings option
--- is enabled. The mappings support count prefixes (e.g., 3<C-o> for 3 jumps back).
---
---@param config Config Configuration with mappings
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
---@param opts table|nil Options to validate
---@return table Validated options
function H.config.validate_opts(opts)
  opts = opts or {}
  if type(opts) ~= 'table' then
    H.utils.error('Jumppack options should be table.')
  end

  opts = vim.deepcopy(H.config.get(opts))

  local validate_callable = function(x, x_name)
    if not vim.is_callable(x) then
      H.utils.error(string.format('`%s` should be callable.', x_name))
    end
  end

  -- Source
  local source = opts.source

  if source then
    local items = source.items or {}
    local is_valid_items = vim.islist(items) or vim.is_callable(items)
    if not is_valid_items then
      H.utils.error('`source.items` should be array or callable.')
    end

    source.name = tostring(source.name or '<No name>')

    if type(source.cwd) == 'string' then
      source.cwd = H.utils.full_path(source.cwd)
    end
    if source.cwd == nil then
      source.cwd = vim.fn.getcwd()
    end
    if vim.fn.isdirectory(source.cwd) == 0 then
      H.utils.error('`source.cwd` should be a valid directory path.')
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
      H.utils.error('`mappings` should have only string fields.')
    end
    if type(x) ~= 'string' then
      H.utils.error(string.format('Mapping for action "%s" should be string.', field))
    end
  end

  -- Window
  local win_config = opts.window.config
  local is_valid_winconfig = win_config == nil or type(win_config) == 'table' or vim.is_callable(win_config)
  if not is_valid_winconfig then
    H.utils.error('`window.config` should be table or callable.')
  end

  return opts
end

-- ============================================================================
-- INSTANCE MANAGEMENT
-- ============================================================================

---Create new picker instance
---@param opts table Validated picker options
---@return Instance New picker instance
function H.instance.create(opts)
  -- Create buffer
  local buf_id = H.window.create_buffer()

  -- Create window
  local win_target = vim.api.nvim_get_current_win()
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
  }

  return instance
end

---Run main picker event loop
---@param instance Instance Picker instance
---@return JumpItem|nil Selected item or nil if aborted
function H.instance.run_loop(instance)
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', { pattern = 'JumppackStart' })
  end)

  local is_aborted = false
  for _ = 1, 1000000 do
    H.instance.update(instance)

    local char = H.utils.getcharstr(10)
    is_aborted = char == nil
    if is_aborted then
      break
    end

    local cur_action = instance.action_keys[char] or {}
    is_aborted = cur_action.name == 'stop'

    if cur_action.func then
      local should_stop = cur_action.func(instance)
      if should_stop then
        break
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
---@param instance Instance Picker instance
---@param update_window boolean|nil Whether to update window config
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

-- ============================================================================
-- WINDOW MANAGEMENT
-- ============================================================================

---Create scratch buffer for picker
---@return number Buffer ID
function H.window.create_buffer()
  local buf_id = H.utils.create_scratch_buf('main')
  vim.bo[buf_id].filetype = 'minipick'
  return buf_id
end

---Create floating window for picker
---@param buf_id number Buffer ID to display
---@param win_config table|function|nil Window configuration
---@param cwd string Current working directory
---@return number Window ID
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
---@param win_config table|function|nil Window config or callable
---@param is_for_open boolean|nil Whether config is for opening window
---@return table Computed window configuration
function H.window.compute_config(win_config, is_for_open)
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  local default_config = {
    relative = 'editor',
    anchor = 'SW',
    width = math.floor(0.618 * max_width),
    height = math.floor(0.618 * max_height),
    col = 0,
    row = max_height + (has_tabline and 1 or 0),
    border = (vim.fn.exists('+winborder') == 1 and vim.o.winborder ~= '') and vim.o.winborder or 'single',
    style = 'minimal',
    noautocmd = is_for_open,
    -- Use high enough value to be on top of built-in windows (pmenu, etc.)
    zindex = 251,
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
---@param instance Instance Picker instance
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
  H.timers.focus:start(1000, 1000, track)
end

---Set items and initial selection for instance
---@param instance Instance Picker instance
---@param items JumpItem[] Jump items
---@param initial_selection number|nil Initial selection index
function H.instance.set_items(instance, items, initial_selection)
  instance.items = items

  if #items > 0 then
    -- Use provided initial selection or default to 1
    local initial_ind = initial_selection or 1
    H.instance.set_selection(instance, initial_ind)
    -- Force update with the new index
    H.instance.set_selection(instance, initial_ind, true)
    -- Show preview by default instead of main
    H.display.render_preview(instance)
  end

  H.instance.update(instance)
end

---Convert jump item to display string
---@param item JumpItem Jump item to convert
---@return string Display string
function H.display.item_to_string(item)
  -- For jump items, construct the display text
  if item.offset ~= nil and item.lnum then
    local filename = vim.fn.fnamemodify(item.path, ':.')
    local line_content = ''
    if vim.fn.bufloaded(item.bufnr) == 1 then
      local lines = vim.fn.getbufline(item.bufnr, item.lnum)
      if #lines > 0 then
        line_content = vim.trim(lines[1])
      end
    end

    if item.offset < 0 then
      return string.format('← %d  %s:%d %s', math.abs(item.offset), filename, item.lnum, line_content)
    elseif item.offset == 0 then
      return string.format('[CURRENT] %s:%d %s', filename, item.lnum, line_content)
    elseif item.offset > 0 then
      return string.format('→ %d  %s:%d %s', item.offset, filename, item.lnum, line_content)
    end
  end

  return item.text
end

---Set current selection index
---@param instance Instance Picker instance
---@param ind number Selection index
---@param force_update boolean|nil Force visible range update
function H.instance.set_selection(instance, ind, force_update)
  if instance.items == nil or #instance.items == 0 then
    instance.current_ind, instance.visible_range = nil, {}
    return
  end

  -- Wrap index around edges
  local n_matches = #instance.items
  ind = (ind - 1) % n_matches + 1

  -- (Re)Compute visible range (centers current index if it is currently outside)
  local from, to = instance.visible_range.from, instance.visible_range.to
  local needs_update = from == nil or to == nil or not (from <= ind and ind <= to)
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
---@param instance Instance Picker instance
function H.display.update_lines(instance)
  local buf_id, win_id = instance.buffers.main, instance.windows.main
  if not (H.utils.is_valid_buf(buf_id) and H.utils.is_valid_win(win_id)) then
    return
  end

  local visible_range = instance.visible_range
  if instance.items == nil or visible_range.from == nil or visible_range.to == nil then
    instance.shown_inds = {}
    instance.opts.source.show(buf_id, {})
    return
  end

  -- Construct target items
  local items_to_show, items, shown_inds = {}, instance.items, {}
  local cur_ind, cur_line = instance.current_ind, nil
  local from = visible_range.from
  local to = visible_range.to
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

  local cur_opts = { end_row = cur_line, end_col = 0, hl_eol = true, hl_group = 'JumppackMatchCurrent', priority = 201 }
  H.utils.set_extmark(buf_id, ns_id, cur_line - 1, 0, cur_opts)
end

---Normalize key mappings for actions
---@param mappings ConfigMappings Key mappings
---@return table Normalized action mappings
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
---@param instance Instance Picker instance
function H.display.update_border(instance)
  local win_id = instance.windows.main
  if not H.utils.is_valid_win(win_id) then
    return
  end

  -- Compute main text managing views separately and truncating from left
  local view_state, win_width = instance.view_state, vim.api.nvim_win_get_width(win_id)
  local config = {}

  local has_items = instance.items ~= nil
  if view_state == 'preview' and has_items and instance.current_ind then
    local current_item = instance.items[instance.current_ind]
    if current_item then
      local stritem_cur = H.display.item_to_string(current_item) or ''
      -- Sanitize title
      stritem_cur = stritem_cur:gsub('%z', '│'):gsub('%s', ' ')
      config = { title = { { H.utils.fit_to_width(' ' .. stritem_cur .. ' ', win_width), 'JumppackBorderText' } } }
    end
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
---@param instance Instance Picker instance
---@param win_id number Window ID
---@return table Footer content
function H.display.compute_footer(instance, win_id)
  local info = H.display.get_general_info(instance)
  local source_name = string.format(' %s ', info.source_name)
  local inds = string.format(' %s|%s', info.relative_current_ind, info.n_total)
  local win_width, source_width, inds_width =
    vim.api.nvim_win_get_width(win_id), vim.fn.strchars(source_name), vim.fn.strchars(inds)

  local footer = { { H.utils.fit_to_width(source_name, win_width), 'JumppackBorderText' } }
  local n_spaces_between = win_width - (source_width + inds_width)
  if n_spaces_between > 0 then
    footer[2] = { H.utils.win_get_bottom_border(win_id):rep(n_spaces_between), 'JumppackBorder' }
    footer[3] = { inds, 'JumppackBorderText' }
  end
  return footer
end

---Destroy picker instance and cleanup
---@param instance Instance Picker instance
function H.instance.destroy(instance)
  vim.tbl_map(function(timer)
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

-- ============================================================================
-- ACTION HANDLERS
-- ============================================================================

H.actions = {
  jump_back = function(instance, _)
    H.instance.move_selection(instance, 1)
  end,
  jump_forward = function(instance, _)
    H.instance.move_selection(instance, -1)
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
      return H.display.render_main(instance)
    end
    H.display.render_preview(instance)
  end,

  stop = function(_, _)
    return true
  end,
}

---Choose current item with optional pre-command
---@param instance Instance Picker instance
---@param pre_command string|nil Command to execute before choosing
---@return boolean True if should stop picker
function H.actions.choose(instance, pre_command)
  local cur_item = H.instance.get_selection(instance)
  if cur_item == nil then
    return true
  end

  local win_id_target = instance.windows.target
  if pre_command ~= nil and H.utils.is_valid_win(win_id_target) then
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
      H.utils.error('Error during choose:\n' .. res)
    end)
  end
  -- Error or returning nothing, `nil`, or `false` should lead to instance stop
  return not (ok and res)
end

---Move current selection by offset or to position
---@param instance Instance Picker instance
---@param by number Movement offset
---@param to number|nil Target position
function H.instance.move_selection(instance, by, to)
  if instance.items == nil then
    return
  end
  local n_matches = #instance.items
  if n_matches == 0 then
    return
  end

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
---@param instance Instance Picker instance
---@return JumpItem|nil Current selection or nil
function H.instance.get_selection(instance)
  if instance.items == nil then
    return nil
  end
  return instance.items[instance.current_ind]
end

---Render main buffer view
---@param instance Instance Picker instance
function H.display.render_main(instance)
  H.utils.set_winbuf(instance.windows.main, instance.buffers.main)
  instance.view_state = 'main'
end

---Get general information about picker state
---@param instance Instance Picker instance
---@return table General information
function H.display.get_general_info(instance)
  local has_items = instance.items ~= nil
  return {
    source_name = instance.opts.source.name or '---',
    source_cwd = vim.fn.fnamemodify(instance.opts.source.cwd, ':~') or '---',
    n_total = has_items and #instance.items or '-',
    relative_current_ind = has_items and instance.current_ind or '-',
  }
end

---Render preview buffer view
---@param instance Instance Picker instance
function H.display.render_preview(instance)
  local preview = instance.opts.source.preview
  local item = H.instance.get_selection(instance)
  if item == nil then
    return
  end

  local win_id, buf_id = instance.windows.main, H.utils.create_scratch_buf('preview')
  vim.bo[buf_id].bufhidden = 'wipe'
  H.utils.set_winbuf(win_id, buf_id)
  preview(buf_id, item)
  instance.buffers.preview = buf_id
  instance.view_state = 'preview'
end

---Get icon for item
---@param item JumpItem Item to get icon for
---@param icons table Icon configuration
---@return table Icon data with text and highlight
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
---@param path string File path
---@return string Type: 'file', 'directory', or 'none'
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

function H.display.preview_should_highlight(buf_id)
  -- Highlight if buffer size is not too big, both in total and per line
  local buf_size = vim.api.nvim_buf_call(buf_id, function()
    return vim.fn.line2byte(vim.fn.line('$') + 1)
  end)
  return buf_size <= 1000000 and buf_size <= 1000 * vim.api.nvim_buf_line_count(buf_id)
end

function H.display.preview_highlight_region(buf_id, lnum, col, end_lnum, end_col)
  -- Highlight line
  if lnum == nil then
    return
  end
  local hl_line_opts = { end_row = lnum, end_col = 0, hl_eol = true, hl_group = 'JumppackPreviewLine', priority = 201 }
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

  local hl_region_opts = { end_row = ext_end_row, end_col = ext_end_col, priority = 202 }
  hl_region_opts.hl_group = 'JumppackPreviewRegion'
  H.utils.set_extmark(buf_id, H.ns_id.preview, lnum - 1, col - 1, hl_region_opts)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Display error message
---@param msg string Error message
function H.utils.error(msg)
  error('(jumppack) ' .. msg, 0)
end

---Check value type and error if invalid
---@param name string Parameter name
---@param val any Value to check
---@param ref string Expected type
---@param allow_nil boolean|nil Allow nil values
function H.utils.check_type(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then
    return
  end
  H.utils.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

function H.utils.set_buf_name(buf_id, name)
  vim.api.nvim_buf_set_name(buf_id, 'jumppack://' .. buf_id .. '/' .. name)
end

---Display notification message
---@param msg string Message to display
---@param level_name string|nil Log level name
function H.utils.notify(msg, level_name)
  vim.notify('(jumppack) ' .. msg, vim.log.levels[level_name])
end

---Check if buffer ID is valid
---@param buf_id number Buffer ID
---@return boolean True if valid
function H.utils.is_valid_buf(buf_id)
  return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id)
end

---Check if window ID is valid
---@param win_id number Window ID
---@return boolean True if valid
function H.utils.is_valid_win(win_id)
  return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id)
end

---Create scratch buffer
---@param name string Buffer name
---@return number Buffer ID
function H.utils.create_scratch_buf(name)
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.utils.set_buf_name(buf_id, name)
  vim.bo[buf_id].matchpairs = ''
  vim.b[buf_id].minicursorword_disable = true
  vim.b[buf_id].miniindentscope_disable = true
  return buf_id
end

function H.utils.set_buflines(buf_id, lines)
  pcall(vim.api.nvim_buf_set_lines, buf_id, 0, -1, false, lines)
end

function H.utils.set_winbuf(win_id, buf_id)
  vim.api.nvim_win_set_buf(win_id, buf_id)
end

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
  return vim.str_byteindex(line_str, utf_index, false)
end

function H.utils.full_path(path)
  return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1'))
end

return Jumppack
