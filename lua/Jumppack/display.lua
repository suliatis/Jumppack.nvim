---@brief [[
--- Display and rendering functions for Jumppack plugin.
--- Handles all visual formatting, icon display, preview rendering, and buffer updates.
--- This module depends on utils, window, filters, and instance namespaces.
---@brief ]]

local Utils = require('Jumppack.utils')
local H = {}

-- Highlight priority constants
local PRIORITY_CURRENT_MATCH = 201
local PRIORITY_PREVIEW_LINE = 201
local PRIORITY_REGION = 202

-- Performance limits
local HIGHLIGHT_MAX_FILESIZE = 1000000
local HIGHLIGHT_MAX_LINES = 1000

-- Symbol constants
local SYMBOL_CURRENT = '●'
local SYMBOL_HIDDEN = '✗'
local SYMBOL_UP = '↑'
local SYMBOL_DOWN = '↓'
local SYMBOL_SEPARATOR = '│'
local SEPARATOR_SPACED = ' │ '

-- Dependencies (will be injected)
local ns_id = {}
local filters = nil
local instance_module = nil

--Set namespace IDs for this module
-- namespaces: Table with ranges and preview namespace IDs
function H.set_namespaces(namespaces)
  ns_id = namespaces
end

--Set filters module reference
-- filters_module: Filters module reference
function H.set_filters(filters_module)
  filters = filters_module
end

--Set instance module reference
-- inst_module: Instance module reference
function H.set_instance(inst_module)
  instance_module = inst_module
end

--- Smart filename display that handles ambiguous names
---
-- Get smart filename for display
-- filepath: Full file path
-- cwd: Current working directory (optional)
-- returns: Smart filename string
function H.smart_filename(filepath, cwd)
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
  local full_path = Utils.full_path(filepath)
  local full_cwd = Utils.full_path(cwd)

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
function H.get_position_marker(item)
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
function H.get_line_preview(item)
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

--Convert jump item to display string with format: [indicator] [icon] [path/name] [lnum:col]
-- item: Jump item to convert
-- opts: Display options with show_preview, show_icons, icons, cwd fields
-- returns: Display string
function H.item_to_string(item, opts)
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
      indicator = H.get_position_marker(item)
    end

    -- Get icon
    local icon = ''
    if show_icons then
      local icon_data = H.get_icon(item, icons)
      icon = icon_data.text or ' '
    end

    -- Get smart filename
    local filename = H.smart_filename(item.path, opts.cwd)

    -- Get position info
    local position = string.format('%d:%d', item.lnum, item.col or 1)

    -- Build core format: [indicator] [icon] [path/name] [lnum:col]
    local core_format = string.format('%s %s%s %s', indicator, icon, filename, position)

    if show_preview then
      -- List mode: add line preview after core format
      local line_content = H.get_line_preview(item)
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

--Update buffer lines with current items
-- instance: Picker instance
function H.update_lines(instance)
  -- Early validation - guard clauses
  if not instance then
    return
  end

  local buf_id, win_id = instance.buffers.main, instance.windows.main
  if not (Utils.is_valid_buf(buf_id) and Utils.is_valid_win(win_id)) then
    return
  end

  -- Handle empty items case - show message instead of returning early
  if not instance.items or #instance.items == 0 then
    local filter_status = filters.get_status_text(instance.filters)
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

  local ranges_ns = ns_id.ranges
  Utils.clear_namespace(buf_id, ranges_ns)

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
  Utils.set_extmark(buf_id, ranges_ns, cur_line - 1, 0, cur_opts)
end

--Update window border text
-- instance: Picker instance
function H.update_border(instance)
  local win_id = instance.windows.main
  if not Utils.is_valid_win(win_id) then
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
        local stritem_cur = H.item_to_string(current_item, {
          show_preview = false,
          show_icons = true,
          icons = { file = ' ', none = '  ' },
          cwd = instance.opts.source.cwd,
        }) or ''
        -- Sanitize title
        stritem_cur = stritem_cur:gsub('%z', SYMBOL_SEPARATOR):gsub('%s', ' ')
        config = { title = { { Utils.fit_to_width(' ' .. stritem_cur .. ' ', win_width), 'JumppackBorderText' } } }
      end
    end
  else
    -- Explicitly clear title in list mode
    config.title = ''
  end

  -- Compute helper footer
  local nvim_has_window_footer = vim.fn.has('nvim-0.10') == 1
  if nvim_has_window_footer then
    config.footer, config.footer_pos = H.compute_footer(instance, win_id), 'left'
  end

  vim.api.nvim_win_set_config(win_id, config)
  vim.wo[win_id].list = true
end

--Compute footer content for window
-- instance: Picker instance
-- win_id: Window ID
-- returns: Footer content
function H.compute_footer(instance, win_id)
  local info = H.get_general_info(instance)
  local source_name = string.format(' %s ', info.source_name)
  local status_text = string.format(' %s ', info.status_text) -- Format: ↑3●↓4 │ [f][c] (selected item position)

  local win_width = vim.api.nvim_win_get_width(win_id)
  local source_width = vim.fn.strchars(source_name)
  local status_width = vim.fn.strchars(status_text)

  local footer = { { Utils.fit_to_width(source_name, win_width), 'JumppackBorderText' } }
  local n_spaces_between = win_width - (source_width + status_width)
  if n_spaces_between > 0 then
    footer[2] = { Utils.win_get_bottom_border(win_id):rep(n_spaces_between), 'JumppackBorder' }
    footer[3] = { status_text, 'JumppackBorderText' }
  end
  return footer
end

--Render list buffer view
-- instance: Picker instance
function H.render_list(instance)
  Utils.set_winbuf(instance.windows.main, instance.buffers.main)
  instance.view_state = 'list'
  H.update_border(instance)
end

--Render current view based on instance view state
-- instance: Picker instance
function H.render(instance)
  if instance.view_state == 'preview' then
    H.render_preview(instance)
  else
    H.render_list(instance)
  end
end

--Get general information about picker state
-- instance: Picker instance
-- returns: General information including position indicator for selected item
function H.get_general_info(instance)
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
  local filter_text = filters.get_status_text(instance.filters)
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

--Render preview buffer view
-- instance: Picker instance
function H.render_preview(instance)
  -- Early validation - guard clause
  local item = instance_module.get_selection(instance)
  if not item then
    return
  end

  local preview = instance.opts.source.preview

  local win_id, buf_id = instance.windows.main, Utils.create_scratch_buf('preview')
  vim.bo[buf_id].bufhidden = 'wipe'
  Utils.set_winbuf(win_id, buf_id)
  preview(buf_id, item)
  instance.buffers.preview = buf_id
  instance.view_state = 'preview'
  H.update_border(instance)
end

--Get icon for item
-- item: Item to get icon for
-- icons: Icon configuration
-- returns: Icon data with text and highlight
function H.get_icon(item, icons)
  local path = item.path or ''
  local path_type = Utils.get_fs_type(path)
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

--- Set lines in preview buffer with syntax highlighting
-- buf_id: Preview buffer id
-- lines: Lines to display
-- extra: Extra info with lnum, col, end_lnum, end_col, filetype, path
function H.preview_set_lines(buf_id, lines, extra)
  -- Lines
  Utils.set_buflines(buf_id, lines)

  -- Highlighting
  H.preview_highlight_region(buf_id, extra.lnum, extra.col, extra.end_lnum, extra.end_col)

  if H.preview_should_highlight(buf_id) then
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
  Utils.set_cursor(win_id, extra.lnum, extra.col)
  local pos_keys = ({ top = 'zt', center = 'zz', bottom = 'zb' })[extra.line_position] or 'zt'
  pcall(vim.api.nvim_win_call, win_id, function()
    vim.cmd('normal! ' .. pos_keys)
  end)
end

--- Check if preview buffer should be syntax highlighted based on size limits
-- buf_id: Buffer id to check
-- returns: # True if buffer should be highlighted
function H.preview_should_highlight(buf_id)
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
function H.preview_highlight_region(buf_id, lnum, col, end_lnum, end_col)
  -- Highlight line
  if lnum == nil then
    return
  end
  local hl_line_opts =
    { end_row = lnum, end_col = 0, hl_eol = true, hl_group = 'JumppackPreviewLine', priority = PRIORITY_PREVIEW_LINE }
  Utils.set_extmark(buf_id, ns_id.preview, lnum - 1, 0, hl_line_opts)

  -- Highlight position/region
  if col == nil then
    return
  end

  local ext_end_row, ext_end_col = lnum - 1, col
  if end_lnum ~= nil and end_col ~= nil then
    ext_end_row, ext_end_col = end_lnum - 1, end_col - 1
  end
  local bufline = vim.fn.getbufline(buf_id, ext_end_row + 1)[1]
  ext_end_col = Utils.get_next_char_bytecol(bufline, ext_end_col)

  local hl_region_opts = { end_row = ext_end_row, end_col = ext_end_col, priority = PRIORITY_REGION }
  hl_region_opts.hl_group = 'JumppackPreviewRegion'
  Utils.set_extmark(buf_id, ns_id.preview, lnum - 1, col - 1, hl_region_opts)
end

return H
