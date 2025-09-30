---@brief [[
--- Filter system for Jumppack plugin.
--- Manages filtering of jump items by file, directory, and visibility.
--- This module depends only on utils.
---@brief ]]

local Utils = require('Jumppack.utils')
local H = {}

-- Filter status symbols
local FILTER_BRACKET_OPEN = '[' -- Filter status opening bracket
local FILTER_BRACKET_CLOSE = ']' -- Filter status closing bracket
local FILTER_SEPARATOR = ',' -- Filter indicator separator
local FILTER_FILE = 'f' -- File-only filter indicator
local FILTER_CWD = 'c' -- Current directory filter indicator
local FILTER_HIDDEN = '.' -- Show hidden filter indicator

-- Optional logging support (injected from main module)
-- luacheck: push ignore 212
local log = {
  trace = function(...) end,
  debug = function(...) end,
  info = function(...) end,
  warn = function(...) end,
}
-- luacheck: pop

--Set logger for this module (optional)
-- logger: Logger implementation with trace, debug, info, warn functions
function H.set_logger(logger)
  if logger then
    log = logger
  end
end

--Apply filters to jump items
-- items: Jump items to filter
-- filters: Filter state
-- filter_context: Filter context with original_file and original_cwd
-- returns: Filtered jump items
function H.apply(items, filters, filter_context)
  if not items or #items == 0 then
    log.trace('filters.apply: empty items')
    return items
  end

  log.debug(
    'filters.apply: items_count=',
    #items,
    'file_only=',
    filters.file_only,
    'cwd_only=',
    filters.cwd_only,
    'show_hidden=',
    filters.show_hidden
  )

  local filtered = {}
  -- Use stored context instead of runtime evaluation to avoid picker buffer context
  local current_file = filter_context and filter_context.original_file or vim.fn.expand('%:p')
  local cwd = filter_context and filter_context.original_cwd or vim.fn.getcwd()

  -- Normalize current file path for robust comparison
  current_file = Utils.full_path(current_file)

  for _, item in ipairs(items) do
    local should_include = true

    -- File filter: only show jumps in current file
    local item_path = Utils.full_path(item.path)
    if filters.file_only and item_path ~= current_file then
      should_include = false
    end

    -- CWD filter: only show jumps in current directory
    if should_include and filters.cwd_only then
      local item_dir = vim.fn.fnamemodify(item_path, ':h')
      if not vim.startswith(Utils.full_path(item_dir), Utils.full_path(cwd)) then
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

  log.debug('filters.apply: filtered from', #items, 'to', #filtered, 'items')
  if #filtered == 0 then
    log.warn('filters.apply: all items filtered out')
  end

  return filtered
end

--Get filter status text for display
-- filters: Filter state
-- returns: Filter status text
function H.get_status_text(filters)
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

--Toggle file-only filter state
-- filters: Filter state to modify
-- returns: Modified filter state
function H.toggle_file(filters)
  filters.file_only = not filters.file_only
  log.debug('toggle_file: file_only=', filters.file_only)
  log.info('File filter', filters.file_only and 'enabled' or 'disabled')
  return filters
end

--Toggle current working directory filter state
-- filters: Filter state to modify
-- returns: Modified filter state
function H.toggle_cwd(filters)
  filters.cwd_only = not filters.cwd_only
  log.debug('toggle_cwd: cwd_only=', filters.cwd_only)
  log.info('CWD filter', filters.cwd_only and 'enabled' or 'disabled')
  return filters
end

--Toggle show hidden items filter state
-- filters: Filter state to modify
-- returns: Modified filter state
function H.toggle_hidden(filters)
  filters.show_hidden = not filters.show_hidden
  log.debug('toggle_hidden: show_hidden=', filters.show_hidden)
  log.info('Show hidden', filters.show_hidden and 'enabled' or 'disabled')
  return filters
end

---Reset all filter states to defaults
-- filters: Filter state to reset
-- returns: Reset filter state
function H.reset(filters)
  log.debug('reset: resetting all filters')
  log.info('All filters reset')
  filters.file_only = false
  filters.cwd_only = false
  filters.show_hidden = false -- Default to hiding hidden items
  return filters
end

--Check if any filter is currently active
-- filters: Filter state to check
-- returns: True if any filter is active
function H.is_active(filters)
  return filters.file_only or filters.cwd_only or filters.show_hidden
end

--Get list of currently active filters
-- filters: Filter state to check
-- returns: List of active filter names
function H.get_active_list(filters)
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

return H
