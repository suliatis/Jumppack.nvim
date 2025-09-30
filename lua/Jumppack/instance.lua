-- Instance management module
-- Handles lifecycle and state of the picker instance (singleton pattern)

local H = {}
H.utils = require('Jumppack.utils')
H.window = require('Jumppack.window')
H.display = require('Jumppack.display')
H.filters = require('Jumppack.filters')

-- Forward declarations for injected dependencies
local Jumppack_config = nil
local H_config = nil

-- Event loop configuration
local LOOP_MAX_ITERATIONS = 1000000 -- Prevent infinite loops in run_loop
local INPUT_DELAY_MS = 10 -- Responsive input without CPU spinning

-- Timer intervals
local FOCUS_CHECK_INTERVAL = 1000 -- Focus tracking timer interval (ms)

-- Singleton instance
local active = nil

-- Cache for instance operations
local cache = {}

-- Timers
local timers = {
  ---@diagnostic disable-next-line: undefined-field
  focus = vim.uv.new_timer(),
  ---@diagnostic disable-next-line: undefined-field
  getcharstr = vim.uv.new_timer(),
}

--Get active instance
-- returns: Active instance or nil
function H.get_active()
  return active
end

--Set active instance
-- instance: Instance to set as active
function H.set_active(instance)
  active = instance
end

--Create new picker instance
-- opts: Validated picker options
-- returns: New picker instance
function H.create(opts)
  local log = H.utils.get_logger()
  log.trace('Creating picker instance')

  -- Create buffer
  local buf_id = H.window.create_buffer()

  -- Create window and store original context
  local win_target = vim.api.nvim_get_current_win()
  -- Get the file path from the target window's buffer to ensure correct context
  local original_file = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win_target))
  local original_cwd = vim.fn.getcwd() -- Store current working directory
  local win_id = H.window.create_window(buf_id, opts.window.config, opts.source.cwd, cache)

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
    action_keys = H_config.normalize_mappings(opts.mappings),

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

  log.trace(
    'Created instance: buf_id=',
    buf_id,
    'win_id=',
    win_id,
    'win_target=',
    win_target,
    'view_state=',
    instance.view_state
  )

  return instance
end

--Run main picker event loop
-- instance: Picker instance
-- returns: Selected item or nil if aborted
function H.run_loop(instance)
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', { pattern = 'JumppackStart' })
  end)

  local is_aborted = false
  ---@diagnostic disable-next-line: unused-local
  for _ = 1, LOOP_MAX_ITERATIONS do
    H.update(instance)

    local char = H.utils.getcharstr(INPUT_DELAY_MS, cache, timers.getcharstr, active)
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
        H.start_count_timeout(instance)
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
        H.clear_count_timeout(instance)

        local should_stop = cur_action.func(instance, count)
        if should_stop then
          break
        end
      else
        -- Unknown character - reset count
        instance.pending_count = ''
        H.clear_count_timeout(instance)
      end
    end
  end

  local item
  if not is_aborted then
    item = H.get_selection(instance)
  end
  H.destroy(instance)
  return item
end

--Update picker instance display
-- instance: Picker instance
-- update_window: Whether to update window config
function H.update(instance, update_window)
  if update_window then
    local config = H.window.compute_config(instance.opts.window.config)
    vim.api.nvim_win_set_config(instance.windows.main, config)
    H.set_selection(instance, instance.current_ind, true)
  end
  H.display.update_border(instance)
  H.display.update_lines(instance)
  H.utils.redraw()
end

--Track focus loss for picker instance
-- instance: Picker instance
function H.track_focus(instance)
  local log = H.utils.get_logger()
  log.trace('Starting focus tracking')
  local track = vim.schedule_wrap(function()
    local is_cur_win = vim.api.nvim_get_current_win() == instance.windows.main
    local is_proper_focus = is_cur_win and (cache.is_in_getcharstr or vim.fn.mode() ~= 'n')
    if is_proper_focus then
      return
    end
    log.trace('Focus lost, destroying instance')
    if cache.is_in_getcharstr then
      -- sends <C-c>
      return vim.api.nvim_feedkeys('\3', 't', true)
    end
    H.destroy(instance)
  end)
  timers.focus:start(FOCUS_CHECK_INTERVAL, FOCUS_CHECK_INTERVAL, track)
end

--Set items and initial selection for instance
-- instance: Picker instance
-- items: Jump items
-- initial_selection: Initial selection index
function H.set_items(instance, items, initial_selection)
  local log = H.utils.get_logger()
  log.trace('set_items: items_count=', #items, 'initial_selection=', initial_selection)

  -- Store original items before any filtering for session state
  instance.original_items = vim.deepcopy(items)
  instance.original_initial_selection = initial_selection

  -- Apply current filter settings to items immediately
  local filtered_items = H.filters.apply(items, instance.filters, instance.filter_context)
  instance.items = filtered_items

  log.trace('set_items: filtered_items_count=', #filtered_items)

  if #filtered_items > 0 then
    -- Calculate initial selection that works with filtered items
    local initial_ind = H.calculate_filtered_initial_selection(items, filtered_items, initial_selection)
    log.trace('set_items: calculated_initial_ind=', initial_ind)
    H.set_selection(instance, initial_ind)
    -- Force update with the new index
    H.set_selection(instance, initial_ind, true)
    -- Show preview by default instead of main
    H.display.render(instance)
  end

  H.update(instance)
end

--Calculate initial selection when items are filtered
-- original_items: Original items
-- filtered_items: Filtered items
-- original_selection: Original selection index
-- returns: Adjusted selection index
function H.calculate_filtered_initial_selection(original_items, filtered_items, original_selection)
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

--Apply filters and update display
-- instance: Picker instance
function H.apply_filters_and_update(instance)
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
    local new_selection = H.find_best_selection(instance, filtered_items)
    H.set_selection(instance, new_selection, true)

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

  H.update(instance)
end

--Find best selection index when items are filtered
-- instance: Picker instance
-- filtered_items: Filtered items
-- returns: Best selection index
function H.find_best_selection(instance, filtered_items)
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

--Start or restart count timeout timer
-- instance: Picker instance
function H.start_count_timeout(instance)
  -- Clear existing timer
  H.clear_count_timeout(instance)

  -- Get timeout from config
  local timeout_ms = Jumppack_config.options.count_timeout_ms or 1000

  -- Start new timer
  instance.count_timer = vim.fn.timer_start(timeout_ms, function()
    instance.pending_count = ''
    instance.count_timer = nil
    H.display.render(instance)
  end)
end

--Clear count timeout timer
-- instance: Picker instance
function H.clear_count_timeout(instance)
  if instance.count_timer then
    vim.fn.timer_stop(instance.count_timer)
    instance.count_timer = nil
  end
end

--Set current selection index
-- instance: Picker instance
-- ind: Selection index
-- force_update: Force visible range update
function H.set_selection(instance, ind, force_update)
  local log = H.utils.get_logger()
  -- Early validation - guard clause
  if not instance or not instance.items or #instance.items == 0 then
    log.trace('set_selection: empty items or invalid instance')
    if instance then
      instance.current_ind, instance.visible_range = nil, {}
    end
    return
  end

  local old_ind = instance.current_ind

  -- Wrap index around edges (trusted state after validation)
  local n_matches = #instance.items
  ind = (ind - 1) % n_matches + 1

  log.trace('set_selection: old_ind=', old_ind, 'new_ind=', ind, 'force_update=', force_update)

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

--Move current selection by offset or to position
-- instance: Picker instance
-- by: Movement offset
-- to: Target position
function H.move_selection(instance, by, to)
  local log = H.utils.get_logger()
  -- Early validation - guard clauses
  if not instance or not instance.items or #instance.items == 0 then
    log.trace('move_selection: empty items or invalid instance')
    return
  end

  local n_matches = #instance.items

  if to == nil then
    local wrap_edges = Jumppack_config.options and Jumppack_config.options.wrap_edges
    to = instance.current_ind

    log.trace('move_selection: by=', by, 'from=', to, 'wrap_edges=', wrap_edges)

    if wrap_edges then
      -- Wrap around edges when enabled
      if to == 1 and by < 0 then
        to = n_matches
        log.trace('move_selection: wrapped to end')
      elseif to == n_matches and by > 0 then
        to = 1
        log.trace('move_selection: wrapped to start')
      else
        to = to + by
      end
    else
      -- No wrapping when disabled - clamp to edges
      to = to + by
      if to < 1 or to > n_matches then
        log.debug('move_selection: edge reached, no wrap, clamping')
      end
    end

    to = math.min(math.max(to, 1), n_matches)
  end

  log.trace('move_selection: final selection=', to)

  H.set_selection(instance, to)

  -- Update not main buffer(s)
  if instance.view_state == 'preview' then
    H.display.render_preview(instance)
  end
end

--Get currently selected item
-- instance: Picker instance
-- returns: Current selection or nil
function H.get_selection(instance)
  -- Early validation - return nil for invalid state
  if not instance or not instance.items or #instance.items == 0 then
    return nil
  end
  return instance.items[instance.current_ind]
end

--Destroy picker instance and cleanup
-- instance: Picker instance
function H.destroy(instance)
  local log = H.utils.get_logger()
  log.debug('destroy: cleaning up instance')
  log.info('Picker closed')

  vim.tbl_map(function(timer)
    ---@diagnostic disable-next-line: undefined-field
    pcall(vim.uv.timer_stop, timer)
  end, timers)

  -- Show cursor (work around `guicursor=''` actually leaving cursor hidden)
  if cache.guicursor == '' then
    vim.cmd('set guicursor=a: | redraw')
  end
  pcall(function()
    vim.o.guicursor = cache.guicursor
  end)

  if instance == nil then
    log.trace('destroy: instance already nil')
    return
  end

  vim.api.nvim_exec_autocmds('User', { pattern = 'JumppackStop' })
  active = nil

  H.utils.set_curwin(instance.windows.target)
  pcall(vim.api.nvim_win_close, instance.windows.main, true)
  pcall(vim.api.nvim_buf_delete, instance.buffers.main, { force = true })
  instance.windows, instance.buffers = {}, {}

  log.debug('destroy: cleanup complete')
end

-- Dependency injection (only for config from init.lua)
function H.set_config(config)
  Jumppack_config = config
end

function H.set_config_module(config_module)
  H_config = config_module
end

function H.get_cache()
  return cache
end

function H.get_timers()
  return timers
end

return H
