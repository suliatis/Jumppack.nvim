---@diagnostic disable: duplicate-set-field

local MiniTest = require('mini.test')

local H = {}

local original_getjumplist = vim.fn.getjumplist
local original_notify = vim.notify
--- Creates a test suite with automatic plugin state cleanup
--- Resets plugin state before each test and restores original functions after
--- @return table MiniTest set with configured hooks
H.create_test_suite = function()
  return MiniTest.new_set({
    hooks = {
      pre_case = function()
        package.loaded['lua.Jumppack'] = nil
        _G.Jumppack = nil
        vim.notify = function() end
      end,
      post_case = function()
        H.force_cleanup_instance()
        vim.fn.getjumplist = original_getjumplist
        vim.notify = original_notify
      end,
    },
  })
end

--- Creates a test buffer with optional content
--- @param name string|nil Buffer name (will be made unique)
--- @param lines table|nil Array of lines to set in buffer
--- @return number Buffer handle
H.create_test_buffer = function(name, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  if name then
    local unique_name = name .. '_' .. tostring(buf)
    vim.api.nvim_buf_set_name(buf, unique_name)
  end
  if lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  return buf
end

--- Mocks vim.fn.getjumplist with provided entries and position
--- @param entries table Array of jump entries {bufnr, lnum, col}
--- @param position number Current position in jumplist
H.create_mock_jumplist = function(entries, position)
  vim.fn.getjumplist = function()
    return { entries or {}, position or 0 }
  end
end

--- Safely deletes multiple buffers
--- @param buffers table Array of buffer handles to delete
H.cleanup_buffers = function(buffers)
  for _, buf in ipairs(buffers) do
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

--- Starts Jumppack and optionally verifies resulting state
--- @param opts table Options to pass to Jumppack.start
--- @param expected table|nil Expected state structure to verify
--- @return table|nil Current plugin state
H.start_and_verify = function(opts, expected)
  local Jumppack = require('lua.Jumppack')
  Jumppack.start(opts)
  vim.wait(10)
  local state = Jumppack.get_state()
  if expected and state then
    H.verify_state(state, expected)
  end
  return state
end

--- Forces cleanup of plugin instance state
--- Attempts graceful cleanup first, then forces state reset
H.force_cleanup_instance = function()
  if _G.Jumppack and _G.Jumppack.is_active and _G.Jumppack.is_active() then
    pcall(function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end)
    vim.wait(100, function()
      return not _G.Jumppack.is_active()
    end)
  end

  if package.loaded['lua.Jumppack'] then
    local Jumppack = require('lua.Jumppack')
    pcall(function()
      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(50)
      end
    end)
  end

  _G.Jumppack = nil
end

--- Creates realistic jumplist data for testing scenarios
--- @param scenario string Scenario type: 'empty', 'single_file', 'multiple_files', 'cross_directory', 'with_hidden', 'large_list'
--- @param opts table|nil Options: {position: number, count: number}
--- @return table Metadata: {entries, position, scenario, buffers}
H.create_realistic_jumplist = function(scenario, opts)
  opts = opts or {}
  local entries = {}
  local position = opts.position or 0

  if scenario == 'empty' then
    entries = {}
    position = 0
  elseif scenario == 'single_file' then
    local buf = H.create_test_buffer('/project/main.lua', { 'line 1', 'line 2', 'line 3', 'line 4', 'line 5' })
    entries = {
      { bufnr = buf, lnum = 1, col = 0 },
      { bufnr = buf, lnum = 3, col = 4 },
      { bufnr = buf, lnum = 5, col = 0 },
    }
    position = opts.position or 1
  elseif scenario == 'multiple_files' then
    local buf1 = H.create_test_buffer('/project/main.lua', { 'main code' })
    local buf2 = H.create_test_buffer('/project/utils.lua', { 'utility functions' })
    local buf3 = H.create_test_buffer('/project/config.lua', { 'configuration' })
    entries = {
      { bufnr = buf1, lnum = 1, col = 0 },
      { bufnr = buf2, lnum = 1, col = 0 },
      { bufnr = buf3, lnum = 1, col = 0 },
      { bufnr = buf1, lnum = 2, col = 0 },
    }
    position = opts.position or 2
  elseif scenario == 'cross_directory' then
    local buf1 = H.create_test_buffer('/project/src/main.lua', { 'main code' })
    local buf2 = H.create_test_buffer('/project/tests/spec.lua', { 'test code' })
    local buf3 = H.create_test_buffer('/other/external.lua', { 'external code' })
    entries = {
      { bufnr = buf1, lnum = 1, col = 0 },
      { bufnr = buf2, lnum = 5, col = 2 },
      { bufnr = buf3, lnum = 10, col = 0 },
      { bufnr = buf1, lnum = 20, col = 4 },
    }
    position = opts.position or 2
  elseif scenario == 'with_hidden' then
    local buf1 = H.create_test_buffer('/project/main.lua', { 'main code' })
    local buf2 = H.create_test_buffer('/project/hidden.lua', { 'hidden file' })
    local buf3 = H.create_test_buffer('/project/visible.lua', { 'visible file' })
    entries = {
      { bufnr = buf1, lnum = 1, col = 0 },
      { bufnr = buf2, lnum = 1, col = 0, hidden = true },
      { bufnr = buf3, lnum = 1, col = 0 },
    }
    position = opts.position or 1
  elseif scenario == 'large_list' then
    local buffers = {}
    for i = 1, (opts.count or 20) do
      buffers[i] = H.create_test_buffer('/project/file' .. i .. '.lua', { 'content ' .. i })
    end
    entries = {}
    for i, buf in ipairs(buffers) do
      table.insert(entries, { bufnr = buf, lnum = i, col = 0 })
      if i % 3 == 0 then
        table.insert(entries, { bufnr = buf, lnum = i + 1, col = 2 })
      end
    end
    position = opts.position or 5
  else
    error('Unknown jumplist scenario: ' .. tostring(scenario))
  end

  H.create_mock_jumplist(entries, position)
  return {
    entries = entries,
    position = position,
    scenario = scenario,
    buffers = vim.tbl_map(function(entry)
      return entry.bufnr
    end, entries),
  }
end

--- Validates workflow state with detailed assertions
--- @param instance table Plugin instance to validate
--- @param expected table Expected state: {context, items_count, filters, selection_index, view_state, has_item_with_path, no_item_with_path}
H.assert_workflow_state = function(instance, expected)
  local context = expected.context or 'workflow validation'
  MiniTest.expect.equality(type(instance), 'table', context .. ': instance should be table')
  MiniTest.expect.equality(type(instance.items), 'table', context .. ': items should be table')
  MiniTest.expect.equality(type(instance.selection), 'table', context .. ': selection should be table')
  MiniTest.expect.equality(type(instance.filters), 'table', context .. ': filters should be table')

  if expected.filters then
    for filter_name, filter_value in pairs(expected.filters) do
      MiniTest.expect.equality(
        instance.filters[filter_name],
        filter_value,
        context .. ': filter ' .. filter_name .. ' should be ' .. tostring(filter_value)
      )
    end
  end

  if expected.items_count then
    MiniTest.expect.equality(
      #instance.items,
      expected.items_count,
      context .. ': should have ' .. expected.items_count .. ' items, got ' .. #instance.items
    )
  end

  if expected.selection_index then
    MiniTest.expect.equality(
      instance.selection.index,
      expected.selection_index,
      context .. ': selection index should be ' .. expected.selection_index
    )
  end

  if expected.view_state then
    MiniTest.expect.equality(
      instance.view_state,
      expected.view_state,
      context .. ': view state should be ' .. expected.view_state
    )
  end

  if #instance.items > 0 then
    MiniTest.expect.equality(
      instance.selection.index >= 1 and instance.selection.index <= #instance.items,
      true,
      context .. ': selection index ' .. instance.selection.index .. ' should be between 1 and ' .. #instance.items
    )
  end

  if expected.has_item_with_path then
    local found = false
    for _, item in ipairs(instance.items) do
      if item.path and item.path:find(expected.has_item_with_path, 1, true) then
        found = true
        break
      end
    end
    MiniTest.expect.equality(
      found,
      true,
      context .. ': should have item with path containing "' .. expected.has_item_with_path .. '"'
    )
  end

  if expected.no_item_with_path then
    local found = false
    for _, item in ipairs(instance.items) do
      if item.path and item.path:find(expected.no_item_with_path, 1, true) then
        found = true
        break
      end
    end
    MiniTest.expect.equality(
      found,
      false,
      context .. ': should not have item with path containing "' .. expected.no_item_with_path .. '"'
    )
  end
end

--- Creates comprehensive test data for filter testing
--- @param opts table|nil Options for test data creation
--- @return table Test data structure with items, buffers, and context
H.create_filter_test_data = function(opts)
  opts = opts or {}
  local buf_current = H.create_test_buffer('/project/current.lua', { 'current file content' })
  local buf_same_dir = H.create_test_buffer('/project/other.lua', { 'same directory file' })
  local buf_sub_dir = H.create_test_buffer('/project/src/main.lua', { 'subdirectory file' })
  local buf_parent_dir = H.create_test_buffer('/other/external.lua', { 'external file' })
  local buf_hidden = H.create_test_buffer('/project/hidden.lua', { 'hidden content' })

  local items = {
    {
      path = '/project/current.lua',
      lnum = 1,
      col = 0,
      bufnr = buf_current,
      offset = 0,
      is_current = true,
      text = 'current file content',
    },
    {
      path = '/project/other.lua',
      lnum = 5,
      col = 4,
      bufnr = buf_same_dir,
      offset = -1,
      is_current = false,
      text = 'same directory file',
    },
    {
      path = '/project/src/main.lua',
      lnum = 10,
      col = 0,
      bufnr = buf_sub_dir,
      offset = -2,
      is_current = false,
      text = 'subdirectory file',
    },
    {
      path = '/other/external.lua',
      lnum = 3,
      col = 2,
      bufnr = buf_parent_dir,
      offset = 1,
      is_current = false,
      text = 'external file',
    },
    {
      path = '/project/hidden.lua',
      lnum = 7,
      col = 0,
      bufnr = buf_hidden,
      offset = -3,
      is_current = false,
      hidden = true,
      text = 'hidden content',
    },
  }

  -- Add additional items if requested
  if opts.add_duplicates then
    table.insert(items, {
      path = '/project/current.lua',
      lnum = 15,
      col = 6,
      bufnr = buf_current,
      offset = 2,
      is_current = false,
      text = 'current file content (different line)',
    })
  end

  if opts.add_more_external then
    local buf_far = H.create_test_buffer('/far/away/file.lua', { 'far away file' })
    table.insert(items, {
      path = '/far/away/file.lua',
      lnum = 1,
      col = 0,
      bufnr = buf_far,
      offset = 3,
      is_current = false,
      text = 'far away file',
    })
  end

  local filter_context = {
    original_file = '/project/current.lua',
    original_cwd = '/project',
  }

  local filter_combinations = {
    { file_only = false, cwd_only = false, show_hidden = false }, -- 000
    { file_only = false, cwd_only = false, show_hidden = true }, -- 001
    { file_only = false, cwd_only = true, show_hidden = false }, -- 010
    { file_only = false, cwd_only = true, show_hidden = true }, -- 011
    { file_only = true, cwd_only = false, show_hidden = false }, -- 100
    { file_only = true, cwd_only = false, show_hidden = true }, -- 101
    { file_only = true, cwd_only = true, show_hidden = false }, -- 110
    { file_only = true, cwd_only = true, show_hidden = true }, -- 111
  }

  local expected_results = {
    [1] = { count = 4, has_current = true, has_external = true, has_hidden = false }, -- 000
    [2] = { count = 5, has_current = true, has_external = true, has_hidden = true }, -- 001
    [3] = { count = 3, has_current = true, has_external = false, has_hidden = false }, -- 010
    [4] = { count = 4, has_current = true, has_external = false, has_hidden = true }, -- 011
    [5] = { count = 1, has_current = true, has_external = false, has_hidden = false }, -- 100
    [6] = { count = 1, has_current = true, has_external = false, has_hidden = false }, -- 101 (no hidden current)
    [7] = { count = 1, has_current = true, has_external = false, has_hidden = false }, -- 110
    [8] = { count = 1, has_current = true, has_external = false, has_hidden = false }, -- 111 (no hidden current)
  }

  return {
    items = items,
    filter_context = filter_context,
    filter_combinations = filter_combinations,
    expected_results = expected_results,
    buffers = { buf_current, buf_same_dir, buf_sub_dir, buf_parent_dir, buf_hidden },
  }
end

--- Mocks vim functions with provided overrides
--- @param mocks table Mock specifications: {current_file, cwd, buffer_names}
--- @return table Original functions for restoration
H.mock_vim_functions = function(mocks)
  mocks = mocks or {}
  local original_functions = {}

  if mocks.current_file then
    original_functions.expand = vim.fn.expand
    vim.fn.expand = function(pattern)
      if pattern == '%:p' then
        return mocks.current_file
      end
      return original_functions.expand(pattern)
    end
  end

  if mocks.cwd then
    original_functions.getcwd = vim.fn.getcwd
    vim.fn.getcwd = function()
      return mocks.cwd
    end
  end

  if mocks.buffer_names then
    original_functions.buf_get_name = vim.api.nvim_buf_get_name
    vim.api.nvim_buf_get_name = function(bufnr)
      if mocks.buffer_names[bufnr] then
        return mocks.buffer_names[bufnr]
      end
      return original_functions.buf_get_name(bufnr)
    end
  end

  return original_functions
end

--- Restores original vim functions from mocks
--- @param original_functions table Original functions returned by mock_vim_functions
H.restore_vim_functions = function(original_functions)
  if original_functions.expand then
    vim.fn.expand = original_functions.expand
  end
  if original_functions.getcwd then
    vim.fn.getcwd = original_functions.getcwd
  end
  if original_functions.buf_get_name then
    vim.api.nvim_buf_get_name = original_functions.buf_get_name
  end
end

--- Creates test items from specification array
--- @param spec table Array of item specs with optional properties
--- @return table Array of formatted test items
H.create_test_items = function(spec)
  local items = {}

  for i, item_spec in ipairs(spec) do
    local item = {
      path = item_spec.path or ('/test/file' .. i .. '.lua'),
      lnum = item_spec.lnum or i,
      col = item_spec.col or 0,
      bufnr = item_spec.bufnr or i,
      offset = item_spec.offset or (i - math.ceil(#spec / 2)),
      is_current = item_spec.is_current or false,
      text = item_spec.text or ('line content ' .. i),
    }

    if item_spec.hidden then
      item.hidden = true
    end

    table.insert(items, item)
  end

  return items
end

--- Waits for condition to become true within timeout
--- @param condition_fn function Function that returns true when condition is met
--- @param timeout_ms number|nil Timeout in milliseconds (default: 1000)
--- @param interval_ms number|nil Check interval in milliseconds (default: 10)
--- @return boolean True if condition was met, false if timeout
H.wait_for_state = function(condition_fn, timeout_ms, interval_ms)
  timeout_ms = timeout_ms or 1000
  interval_ms = interval_ms or 10

  local start_time = vim.loop.now()

  while vim.loop.now() - start_time < timeout_ms do
    if condition_fn() then
      return true
    end
    vim.wait(interval_ms)
  end

  return false
end

--- Simulates sequence of user actions for workflow testing
--- @param instance table Plugin instance
--- @param actions table Array of action specifications
--- @return table Workflow execution results
H.simulate_user_workflow = function(instance, actions)
  local results = {}

  for i, action in ipairs(actions) do
    local action_name = action.action or 'unknown'
    local params = action.params or {}

    local before_state = {
      items_count = #instance.items,
      selection_index = instance.selection.index,
      filters = vim.deepcopy(instance.filters),
    }

    local success = pcall(function()
      if action_name == 'move_selection' then
        if instance.H and instance.H.instance and instance.H.instance.move_selection then
          instance.H.instance.move_selection(instance, params.by, params.to)
        end
      elseif action_name == 'toggle_filter' then
        if params.filter_type and instance.H and instance.H.actions then
          local toggle_fn = instance.H.actions['toggle_' .. params.filter_type .. '_filter']
          if toggle_fn then
            toggle_fn(instance, {})
          end
        end
      elseif action_name == 'wait' then
        vim.wait(params.ms or 10)
      end
    end)

    table.insert(results, {
      action = action_name,
      params = params,
      success = success,
      before_state = before_state,
      after_state = {
        items_count = #instance.items,
        selection_index = instance.selection.index,
        filters = vim.deepcopy(instance.filters),
      },
    })

    vim.wait(5)
  end

  return results
end

--- Verifies plugin state structure and optional expected values
--- @param state table Plugin state to verify
--- @param expected table|nil Expected values: {items_count, selection_index, source_name}
H.verify_state = function(state, expected)
  MiniTest.expect.equality(type(state), 'table')
  MiniTest.expect.equality(type(state.items), 'table')
  MiniTest.expect.equality(type(state.selection), 'table')
  MiniTest.expect.equality(type(state.general_info), 'table')

  MiniTest.expect.equality(type(state.selection.index), 'number')

  MiniTest.expect.equality(type(state.general_info.source_name), 'string')
  MiniTest.expect.equality(type(state.general_info.source_cwd), 'string')

  if expected then
    if expected.items_count then
      MiniTest.expect.equality(#state.items, expected.items_count)
    end
    if expected.selection_index then
      MiniTest.expect.equality(state.selection.index, expected.selection_index)
    end
    if expected.source_name then
      MiniTest.expect.equality(state.general_info.source_name, expected.source_name)
    end
  end
end

--- Waits for async operations to complete (scheduled functions, UI updates)
--- @param ms number|nil Wait time in milliseconds (default: 50)
H.wait_for_async = function(ms)
  ms = ms or 50
  vim.wait(ms)
  vim.cmd('redraw')
end

return H
