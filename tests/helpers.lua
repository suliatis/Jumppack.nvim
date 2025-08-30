---@diagnostic disable: duplicate-set-field

local MiniTest = require('mini.test')

-- Test helper namespace (like production code)
local H = {}

-- ============================================================================
-- TEST SETUP CONFIGURATION
-- ============================================================================

-- Store original functions needed for test setup
local original_getjumplist = vim.fn.getjumplist
local original_notify = vim.notify

-- Create configured test suite with proper hooks
H.create_test_suite = function()
  return MiniTest.new_set({
    hooks = {
      pre_case = function()
        -- Reset plugin state before each test
        package.loaded['lua.Jumppack'] = nil
        _G.Jumppack = nil
        -- Suppress vim.notify during tests to keep output clean
        vim.notify = function() end
      end,
      post_case = function()
        H.force_cleanup_instance()
        vim.fn.getjumplist = original_getjumplist
        -- Restore original notify
        vim.notify = original_notify
      end,
    },
  })
end

-- ============================================================================
-- SETUP & TEARDOWN HELPERS
-- ============================================================================
H.create_test_buffer = function(name, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  if name then
    -- Make buffer names unique to avoid conflicts
    local unique_name = name .. '_' .. tostring(buf)
    vim.api.nvim_buf_set_name(buf, unique_name)
  end
  if lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  return buf
end

H.create_mock_jumplist = function(entries, position)
  vim.fn.getjumplist = function()
    return { entries or {}, position or 0 }
  end
end

H.cleanup_buffers = function(buffers)
  for _, buf in ipairs(buffers) do
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

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

H.force_cleanup_instance = function()
  -- Try graceful cleanup first through normal API
  if _G.Jumppack and _G.Jumppack.is_active and _G.Jumppack.is_active() then
    pcall(function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end)
    vim.wait(100, function()
      return not _G.Jumppack.is_active()
    end)
  end

  -- Force cleanup by resetting the module state
  if package.loaded['lua.Jumppack'] then
    local Jumppack = require('lua.Jumppack')
    -- Use public API or reset module state
    pcall(function()
      if Jumppack.is_active() then
        -- Force stop if still active after escape key
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(50)
      end
    end)
  end

  -- Clear any remaining global state
  _G.Jumppack = nil
end

-- ============================================================================
-- DATA CREATION HELPERS
-- ============================================================================

H.create_realistic_jumplist = function(scenario, opts)
  opts = opts or {}
  local entries = {}
  local position = opts.position or 0

  if scenario == 'empty' then
    -- Empty jumplist
    entries = {}
    position = 0
  elseif scenario == 'single_file' then
    -- Single file with multiple positions
    local buf = H.create_test_buffer('/project/main.lua', { 'line 1', 'line 2', 'line 3', 'line 4', 'line 5' })
    entries = {
      { bufnr = buf, lnum = 1, col = 0 },
      { bufnr = buf, lnum = 3, col = 4 },
      { bufnr = buf, lnum = 5, col = 0 },
    }
    position = opts.position or 1
  elseif scenario == 'multiple_files' then
    -- Multiple files in same directory
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
    -- Files across different directories
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
    -- Files with some items marked as hidden
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
    -- Large jumplist for performance testing
    local buffers = {}
    for i = 1, (opts.count or 20) do
      buffers[i] = H.create_test_buffer('/project/file' .. i .. '.lua', { 'content ' .. i })
    end
    entries = {}
    for i, buf in ipairs(buffers) do
      table.insert(entries, { bufnr = buf, lnum = i, col = 0 })
      if i % 3 == 0 then -- Add some repeated files
        table.insert(entries, { bufnr = buf, lnum = i + 1, col = 2 })
      end
    end
    position = opts.position or 5
  else
    error('Unknown jumplist scenario: ' .. tostring(scenario))
  end

  -- Apply the mock jumplist
  H.create_mock_jumplist(entries, position)

  -- Return metadata for test verification
  return {
    entries = entries,
    position = position,
    scenario = scenario,
    buffers = vim.tbl_map(function(entry)
      return entry.bufnr
    end, entries),
  }
end

-- ============================================================================
-- VALIDATION & ASSERTION HELPERS
-- ============================================================================

H.assert_workflow_state = function(instance, expected)
  local context = expected.context or 'workflow validation'

  -- Validate instance structure
  MiniTest.expect.equality(type(instance), 'table', context .. ': instance should be table')
  MiniTest.expect.equality(type(instance.items), 'table', context .. ': items should be table')
  MiniTest.expect.equality(type(instance.selection), 'table', context .. ': selection should be table')
  MiniTest.expect.equality(type(instance.filters), 'table', context .. ': filters should be table')

  -- Check filter state if provided
  if expected.filters then
    for filter_name, filter_value in pairs(expected.filters) do
      MiniTest.expect.equality(
        instance.filters[filter_name],
        filter_value,
        context .. ': filter ' .. filter_name .. ' should be ' .. tostring(filter_value)
      )
    end
  end

  -- Check items count if provided
  if expected.items_count then
    MiniTest.expect.equality(
      #instance.items,
      expected.items_count,
      context .. ': should have ' .. expected.items_count .. ' items, got ' .. #instance.items
    )
  end

  -- Check selection index if provided
  if expected.selection_index then
    MiniTest.expect.equality(
      instance.selection.index,
      expected.selection_index,
      context .. ': selection index should be ' .. expected.selection_index
    )
  end

  -- Check view state if provided
  if expected.view_state then
    MiniTest.expect.equality(
      instance.view_state,
      expected.view_state,
      context .. ': view state should be ' .. expected.view_state
    )
  end

  -- Check that selection is within bounds
  if #instance.items > 0 then
    MiniTest.expect.equality(
      instance.selection.index >= 1 and instance.selection.index <= #instance.items,
      true,
      context .. ': selection index ' .. instance.selection.index .. ' should be between 1 and ' .. #instance.items
    )
  end

  -- Check specific items if provided
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

  -- Check that no item has specific path if provided
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

H.create_filter_test_data = function(opts)
  opts = opts or {}

  -- Create test buffers for different scenarios
  local buf_current = H.create_test_buffer('/project/current.lua', { 'current file content' })
  local buf_same_dir = H.create_test_buffer('/project/other.lua', { 'same directory file' })
  local buf_sub_dir = H.create_test_buffer('/project/src/main.lua', { 'subdirectory file' })
  local buf_parent_dir = H.create_test_buffer('/other/external.lua', { 'external file' })
  local buf_hidden = H.create_test_buffer('/project/hidden.lua', { 'hidden content' })

  -- Standard item structure for filter testing
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

  -- Filter context for testing
  local filter_context = {
    original_file = '/project/current.lua',
    original_cwd = '/project',
  }

  -- All possible filter combinations (as in TASKS.md)
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

  -- Expected results for each combination
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

-- ============================================================================
-- MOCK MANAGEMENT HELPERS
-- ============================================================================

H.mock_vim_functions = function(mocks)
  mocks = mocks or {}
  local original_functions = {}

  -- Mock vim.fn.expand
  if mocks.current_file then
    original_functions.expand = vim.fn.expand
    vim.fn.expand = function(pattern)
      if pattern == '%:p' then
        return mocks.current_file
      end
      return original_functions.expand(pattern)
    end
  end

  -- Mock vim.fn.getcwd
  if mocks.cwd then
    original_functions.getcwd = vim.fn.getcwd
    vim.fn.getcwd = function()
      return mocks.cwd
    end
  end

  -- Mock vim.api.nvim_buf_get_name
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

    -- Add optional properties
    if item_spec.hidden then
      item.hidden = true
    end

    table.insert(items, item)
  end

  return items
end

-- ============================================================================
-- WORKFLOW HELPERS
-- ============================================================================

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

H.simulate_user_workflow = function(instance, actions)
  -- Simulate a sequence of user actions for workflow testing
  local results = {}

  for i, action in ipairs(actions) do
    local action_name = action.action or 'unknown'
    local params = action.params or {}

    -- Record state before action
    local before_state = {
      items_count = #instance.items,
      selection_index = instance.selection.index,
      filters = vim.deepcopy(instance.filters),
    }

    -- Perform action
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

    -- Record results
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

    -- Small delay to allow state updates
    vim.wait(5)
  end

  return results
end

H.verify_state = function(state, expected)
  MiniTest.expect.equality(type(state), 'table')
  MiniTest.expect.equality(type(state.items), 'table')
  MiniTest.expect.equality(type(state.selection), 'table')
  MiniTest.expect.equality(type(state.general_info), 'table')

  -- Verify selection structure
  MiniTest.expect.equality(type(state.selection.index), 'number')

  -- Verify general_info structure
  MiniTest.expect.equality(type(state.general_info.source_name), 'string')
  MiniTest.expect.equality(type(state.general_info.source_cwd), 'string')

  -- Check expected values if provided
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

return H
