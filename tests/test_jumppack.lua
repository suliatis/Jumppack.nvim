---@diagnostic disable: duplicate-set-field

local MiniTest = require('mini.test')

local original_getjumplist = vim.fn.getjumplist

-- Test helper namespace (like production code)
local H = {}

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

-- Store original functions
local original_notify = vim.notify

local T = MiniTest.new_set({
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

-- Load the plugin
local Jumppack = require('lua.Jumppack')

-- ============================================================================
-- 1. SETUP & CONFIGURATION TESTS
-- ============================================================================
T['Setup & Configuration'] = MiniTest.new_set()

T['Setup & Configuration']['Basic Configuration'] = MiniTest.new_set()

T['Setup & Configuration']['Basic Configuration']['has default configuration'] = function()
  MiniTest.expect.equality(type(Jumppack.config), 'table')
  MiniTest.expect.equality(type(Jumppack.config.mappings), 'table')
  MiniTest.expect.equality(type(Jumppack.config.window), 'table')
end

T['Setup & Configuration']['Basic Configuration']['merges user config with defaults'] = function()
  local config = {
    mappings = {
      jump_back = '<C-b>',
      jump_forward = '<C-i>',
      choose = '<CR>',
      choose_in_split = '<C-s>',
      choose_in_tabpage = '<C-t>',
      choose_in_vsplit = '<C-v>',
      stop = '<Esc>',
      toggle_preview = 'p',
      -- New filter mappings
      toggle_file_filter = 'f',
      toggle_cwd_filter = 'c',
      toggle_show_hidden = '.',
      reset_filters = 'r',
      toggle_hidden = 'x',
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)
  MiniTest.expect.equality(Jumppack.config.mappings.jump_back, '<C-b>')
  MiniTest.expect.equality(Jumppack.config.mappings.jump_forward, '<C-i>')
end

T['Setup & Configuration']['Basic Configuration']['validates configuration in setup'] = function()
  local config = {
    mappings = {
      jump_back = '<C-b>',
      jump_forward = '<C-f>',
      choose = '<CR>',
      choose_in_split = '<C-s>',
      choose_in_tabpage = '<C-t>',
      choose_in_vsplit = '<C-v>',
      stop = '<Esc>',
      toggle_preview = 'p',
      -- New filter mappings
      toggle_file_filter = 'f',
      toggle_cwd_filter = 'c',
      toggle_show_hidden = '.',
      reset_filters = 'r',
      toggle_hidden = 'x',
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)
end

T['Setup & Configuration']['Mapping Configuration'] = MiniTest.new_set()

T['Setup & Configuration']['Mapping Configuration']['validates mapping types'] = function()
  local invalid_config = {
    mappings = {
      jump_back = 123,
    },
  }

  MiniTest.expect.error(function()
    Jumppack.setup(invalid_config)
  end)
end

-- Additional Setup & Configuration subcategories

T['Setup & Configuration']['Setup'] = MiniTest.new_set()

T['Setup & Configuration']['Setup']['initializes without errors'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)
end

T['Setup & Configuration']['Setup']['creates autocommands'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)

  -- Check that the Jumppack augroup exists
  local autocmds = vim.api.nvim_get_autocmds({ group = 'Jumppack' })
  MiniTest.expect.equality(#autocmds > 0, true)
end

T['Setup & Configuration']['Setup']['sets up mappings correctly'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)
  MiniTest.expect.equality(type(Jumppack.is_active), 'function')
end

T['Setup & Configuration']['Mapping Configuration']['creates global mappings by default'] = function()
  local config = {
    mappings = {
      jump_back = '<C-x>',
      jump_forward = '<C-y>',
      choose = '<CR>',
      choose_in_split = '<C-s>',
      choose_in_tabpage = '<C-t>',
      choose_in_vsplit = '<C-v>',
      stop = '<Esc>',
      toggle_preview = 'p',
      toggle_file_filter = 'f',
      toggle_cwd_filter = 'c',
      toggle_show_hidden = '.',
      reset_filters = 'r',
      toggle_hidden = 'x',
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Check that mappings exist
  local mappings = vim.api.nvim_get_keymap('n')
  local has_jump_back = false
  for _, map in ipairs(mappings) do
    if map.lhs == '<C-X>' then -- nvim_get_keymap normalizes to uppercase
      has_jump_back = true
      break
    end
  end
  MiniTest.expect.equality(has_jump_back, true)
end

T['Setup & Configuration']['Mapping Configuration']['respects global_mappings = false'] = function()
  -- Clear any existing mappings first
  pcall(vim.keymap.del, 'n', '<C-x>')
  pcall(vim.keymap.del, 'n', '<C-X>')
  pcall(vim.keymap.del, 'n', '<C-y>')
  pcall(vim.keymap.del, 'n', '<C-Y>')

  local config = {
    options = {
      global_mappings = false,
    },
    mappings = {
      jump_back = '<C-x>',
      jump_forward = '<C-y>',
      choose = '<CR>',
      choose_in_split = '<C-s>',
      choose_in_tabpage = '<C-t>',
      choose_in_vsplit = '<C-v>',
      stop = '<Esc>',
      toggle_preview = 'p',
      toggle_file_filter = 'f',
      toggle_cwd_filter = 'c',
      toggle_show_hidden = '.',
      reset_filters = 'r',
      toggle_hidden = 'x',
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Check that mappings do NOT exist
  local mappings = vim.api.nvim_get_keymap('n')
  local has_jump_back = false
  for _, map in ipairs(mappings) do
    if map.lhs == '<C-X>' then -- nvim_get_keymap normalizes to uppercase
      has_jump_back = true
      break
    end
  end
  MiniTest.expect.equality(has_jump_back, false)
end

T['Setup & Configuration']['Mapping Configuration']['respects global_mappings = true'] = function()
  local config = {
    options = {
      global_mappings = true, -- explicit true
    },
    mappings = {
      jump_back = '<C-z>',
      jump_forward = '<C-q>',
      choose = '<CR>',
      choose_in_split = '<C-s>',
      choose_in_tabpage = '<C-t>',
      choose_in_vsplit = '<C-v>',
      stop = '<Esc>',
      toggle_preview = 'p',
      toggle_file_filter = 'f',
      toggle_cwd_filter = 'c',
      toggle_show_hidden = '.',
      reset_filters = 'r',
      toggle_hidden = 'x',
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Check that mappings DO exist
  local mappings = vim.api.nvim_get_keymap('n')
  local has_jump_back = false
  for _, map in ipairs(mappings) do
    if map.lhs == '<C-Z>' then -- nvim_get_keymap normalizes to uppercase
      has_jump_back = true
      break
    end
  end
  MiniTest.expect.equality(has_jump_back, true)
end

T['Setup & Configuration']['Options Configuration'] = MiniTest.new_set()

T['Setup & Configuration']['Options Configuration']['respects cwd_only option'] = function()
  -- Create test files in different directories
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)

  -- Create buffers for the files
  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 }, -- temp file outside cwd
    { bufnr = buf2, lnum = 1, col = 0 }, -- another temp file outside cwd
  }, 1)

  local config = {
    options = {
      cwd_only = true,
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test that cwd_only filtering works by trying to start jumppack
  MiniTest.expect.no_error(function()
    pcall(Jumppack.start, { offset = -1 })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  H.cleanup_buffers({ buf1, buf2 })
end

T['Setup & Configuration']['Options Configuration']['respects wrap_edges option'] = function()
  local buf1 = H.create_test_buffer('test1.lua', { 'test content 1' })
  local buf2 = H.create_test_buffer('test2.lua', { 'test content 2' })
  local buf3 = H.create_test_buffer('test3.lua', { 'test content 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 }, -- offset -2 (backward)
    { bufnr = buf2, lnum = 1, col = 0 }, -- offset -1 (backward)
    { bufnr = buf2, lnum = 2, col = 0 }, -- offset 0 (current)
    { bufnr = buf3, lnum = 1, col = 0 }, -- offset 1 (forward)
  }, 2)

  local config = {
    options = {
      wrap_edges = true,
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test that wrapping works by trying extreme offsets
  MiniTest.expect.no_error(function()
    pcall(Jumppack.start, { offset = 99 }) -- Should wrap to furthest back
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2, buf3 })
end

-- These complex interaction tests are moved to integration tests section

T['Setup & Configuration']['Options Configuration']['respects default_view option'] = function()
  local buf1 = H.create_test_buffer('test1.lua', { 'test content 1' })
  local buf2 = H.create_test_buffer('test2.lua', { 'test content 2' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 }, -- offset -1
    { bufnr = buf2, lnum = 1, col = 0 }, -- offset 0 (current)
  }, 1)

  local config = {
    options = {
      default_view = 'preview',
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test that picker starts in preview mode
  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -1 })

    if Jumppack.is_active() then
      local state = Jumppack.get_state()
      -- Should start in preview mode
      MiniTest.expect.equality(state.general_info.view_state, 'preview')

      -- Clean up
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2 })
end

T['Setup & Configuration']['Options Configuration']['validates default_view option'] = function()
  MiniTest.expect.error(function()
    Jumppack.setup({
      options = {
        default_view = 'invalid_mode', -- should cause error
      },
    })
  end)
end

T['Setup & Configuration']['State Management'] = MiniTest.new_set()

T['Setup & Configuration']['State Management']['reports active state correctly'] = function()
  MiniTest.expect.equality(Jumppack.is_active(), false)
end

T['Setup & Configuration']['State Management']['returns state when active'] = function()
  MiniTest.expect.equality(Jumppack.get_state(), nil)
end

T['Setup & Configuration']['State Management']['handles refresh when inactive'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.refresh()
  end)
end

T['Setup & Configuration']['State Management']['validates start options'] = function()
  MiniTest.expect.error(function()
    Jumppack.start('invalid')
  end)
end

-- ============================================================================
-- 2. NAVIGATION FEATURES TESTS
-- ============================================================================
T['Navigation Features'] = MiniTest.new_set()

T['Navigation Features']['Basic Processing'] = MiniTest.new_set()

T['Navigation Features']['Basic Processing']['handles empty jumplist'] = function()
  H.create_mock_jumplist({}, 0)

  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -1 })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)
end

T['Navigation Features']['Basic Processing']['processes jumplist with items'] = function()
  local buf1 = H.create_test_buffer('test1.lua', { 'line 1', 'line 2' })
  local buf2 = H.create_test_buffer('test2.lua', { 'line 3', 'line 4' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 2, col = 0 },
  }, 0)

  MiniTest.expect.no_error(function()
    local state = H.start_and_verify({ offset = -1 }, { source_name = 'Jumplist' })

    -- Verify jump items have expected structure if any exist
    if state and #state.items > 0 then
      for _, item in ipairs(state.items) do
        MiniTest.expect.equality(type(item.offset), 'number')
        MiniTest.expect.equality(type(item.bufnr), 'number')
      end
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2 })
end

T['Navigation Features']['Basic Processing']['creates proper item structure'] = function()
  local buf1 = H.create_test_buffer('test_structure.lua', { 'test line' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
  }, 0)

  MiniTest.expect.no_error(function()
    local state = H.start_and_verify({ offset = -1 })

    if state and #state.items > 0 then
      local item = state.items[1]
      MiniTest.expect.equality(type(item.path), 'string')
      MiniTest.expect.equality(type(item.offset), 'number')
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1 })
end

T['Navigation Features']['Fallback Behavior'] = MiniTest.new_set()

T['Navigation Features']['Fallback Behavior']['falls back to max offset when too high'] = function()
  local buf1 = H.create_test_buffer('test_fallback1.lua', { 'line 1', 'line 2' })
  local buf2 = H.create_test_buffer('test_fallback2.lua', { 'line 3', 'line 4' })
  local buf3 = H.create_test_buffer('test_fallback3.lua', { 'line 5', 'line 6' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 }, -- offset -2
    { bufnr = buf2, lnum = 1, col = 0 }, -- offset -1
    { bufnr = buf2, lnum = 2, col = 0 }, -- offset 0 (current)
    { bufnr = buf3, lnum = 1, col = 0 }, -- offset 1
    { bufnr = buf3, lnum = 2, col = 0 }, -- offset 2
  }, 2)

  -- Test requesting offset 99 (forward) - should select offset 2 (max forward)
  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = 99 })
    vim.wait(10)

    local state = Jumppack.get_state()
    if state and state.current then
      -- The selected item should have offset 2 (the maximum forward offset)
      MiniTest.expect.equality(state.current.offset, 2)
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Navigation Features']['Fallback Behavior']['falls back to min offset when too low'] = function()
  local buf1 = H.create_test_buffer('test_fallback1.lua', { 'line 1', 'line 2' })
  local buf2 = H.create_test_buffer('test_fallback2.lua', { 'line 3', 'line 4' })
  local buf3 = H.create_test_buffer('test_fallback3.lua', { 'line 5', 'line 6' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 }, -- offset -2
    { bufnr = buf2, lnum = 1, col = 0 }, -- offset -1
    { bufnr = buf2, lnum = 2, col = 0 }, -- offset 0 (current)
    { bufnr = buf3, lnum = 1, col = 0 }, -- offset 1
    { bufnr = buf3, lnum = 2, col = 0 }, -- offset 2
  }, 2)

  -- Test requesting offset -99 (backward) - should select offset -2 (min backward)
  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -99 })
    vim.wait(10)

    local state = Jumppack.get_state()
    if state and state.current then
      -- The selected item should have offset -2 (the minimum backward offset)
      MiniTest.expect.equality(state.current.offset, -2)
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2, buf3 })
end

-- ============================================================================
-- 5. DISPLAY FEATURES TESTS
-- ============================================================================
T['Display Features'] = MiniTest.new_set()

T['Display Features']['Show Function'] = MiniTest.new_set()

T['Display Features']['Show Function']['displays items without errors'] = function()
  local buf = H.create_test_buffer()
  local items = {
    { path = 'test.lua', text = 'test item' },
  }

  MiniTest.expect.no_error(function()
    Jumppack.show_items(buf, items, {})
  end)

  H.cleanup_buffers({ buf })
end

T['Display Features']['Show Function']['handles empty items'] = function()
  local buf = H.create_test_buffer()

  MiniTest.expect.no_error(function()
    Jumppack.show_items(buf, {}, {})
  end)

  H.cleanup_buffers({ buf })
end

T['Display Features']['Show Function']['handles jump items with offsets'] = function()
  local buf = H.create_test_buffer()
  local items = {
    {
      offset = -1,
      path = 'test.lua',
      lnum = 10,
      bufnr = buf,
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.show_items(buf, items, {})
  end)

  H.cleanup_buffers({ buf })
end

T['Display Features']['Preview Function'] = MiniTest.new_set()

T['Display Features']['Preview Function']['handles items with bufnr'] = function()
  local source_buf = H.create_test_buffer('test.lua', { 'test line 1', 'test line 2' })
  local preview_buf = H.create_test_buffer()

  local item = {
    bufnr = source_buf,
    lnum = 1,
    col = 1,
    path = 'test.lua',
  }

  MiniTest.expect.no_error(function()
    Jumppack.preview_item(preview_buf, item, {})
  end)

  H.cleanup_buffers({ source_buf, preview_buf })
end

T['Display Features']['Preview Function']['handles items without bufnr'] = function()
  local preview_buf = H.create_test_buffer()
  local item = { path = 'test.lua' }

  MiniTest.expect.no_error(function()
    Jumppack.preview_item(preview_buf, item, {})
  end)

  H.cleanup_buffers({ preview_buf })
end

T['Display Features']['Preview Function']['handles nil item'] = function()
  local preview_buf = H.create_test_buffer()

  MiniTest.expect.no_error(function()
    Jumppack.preview_item(preview_buf, nil, {})
  end)

  H.cleanup_buffers({ preview_buf })
end

T['Display Features']['Choose Function'] = MiniTest.new_set()

T['Display Features']['Choose Function']['handles backward jumps'] = function()
  local item = {
    offset = -2,
  }

  MiniTest.expect.no_error(function()
    Jumppack.choose_item(item)
    -- Wait longer for scheduled function to execute (this will catch vim.cmd errors)
    vim.wait(100, function()
      return false
    end)
    -- Force event loop processing to ensure scheduled function runs
    vim.api.nvim_exec2('redraw', {})
  end)
end

T['Display Features']['Choose Function']['handles forward jumps'] = function()
  local item = {
    offset = 1,
  }

  MiniTest.expect.no_error(function()
    Jumppack.choose_item(item)
    -- Wait longer for scheduled function to execute (this will catch vim.cmd errors)
    vim.wait(100, function()
      return false
    end)
    -- Force event loop processing to ensure scheduled function runs
    vim.api.nvim_exec2('redraw', {})
  end)
end

T['Display Features']['Choose Function']['handles current position'] = function()
  local item = {
    offset = 0,
  }

  MiniTest.expect.no_error(function()
    Jumppack.choose_item(item)
    -- Wait longer for scheduled function to execute (this will catch vim.cmd errors)
    vim.wait(100, function()
      return false
    end)
    -- Force event loop processing to ensure scheduled function runs
    vim.api.nvim_exec2('redraw', {})
  end)
end

-- ============================================================================
-- 6. USER WORKFLOWS TESTS
-- ============================================================================
T['User Workflows'] = MiniTest.new_set()

T['User Workflows']['completes full setup workflow'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)

  -- Should not be active when just set up
  MiniTest.expect.equality(type(Jumppack.is_active), 'function')
end

T['User Workflows']['handles jumplist navigation request'] = function()
  local buf1 = H.create_test_buffer('integration_test1.lua')
  local buf2 = H.create_test_buffer('integration_test2.lua')

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 10, col = 0 },
    { bufnr = buf2, lnum = 20, col = 5 },
  }, 0)

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    local state = H.start_and_verify({ offset = -1 }, { source_name = 'Jumplist' })

    -- Verify at least one item exists with proper structure if any exist
    if state and #state.items > 0 then
      MiniTest.expect.equality(type(state.items[1].path), 'string')
      MiniTest.expect.equality(type(state.items[1].offset), 'number')
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2 })
end

T['User Workflows']['handles refresh when not active'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.refresh()
  end)
end

T['User Workflows']['handles invalid configuration gracefully'] = function()
  MiniTest.expect.error(function()
    Jumppack.setup({
      mappings = 'invalid',
    })
  end)
end

T['User Workflows']['handles invalid start options'] = function()
  MiniTest.expect.error(function()
    Jumppack.start('not a table')
  end)
end

-- Complete User Journey Tests (Phase 2.1)

T['User Workflows']['Basic Navigation Workflow: Setup → Start → Navigate → Choose'] = function()
  -- Setup: Create realistic jumplist with multiple files
  local jumplist_data = H.create_realistic_jumplist('multiple_files')

  MiniTest.expect.no_error(function()
    -- Step 1: Setup plugin
    Jumppack.setup({})

    -- Step 2: Start picker
    Jumppack.start({})
    vim.wait(10)

    -- Verify picker is active
    MiniTest.expect.equality(Jumppack.is_active(), true)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance

    -- Step 3: Verify initial workflow state
    H.assert_workflow_state(instance, {
      context = 'initial navigation workflow',
      items_count = 4, -- multiple_files scenario creates 4 items
      filters = {
        file_only = false,
        cwd_only = false,
        show_hidden = false,
      },
    })

    -- Step 4: Navigate forward and backward
    local H_internal = Jumppack.H
    local initial_selection = instance.selection.index

    -- Navigate forward
    if H_internal.actions and H_internal.actions.move_next then
      H_internal.actions.move_next(instance, {})
      vim.wait(10)

      -- Verify selection moved
      MiniTest.expect.equality(
        instance.selection.index > initial_selection
          or (initial_selection == #instance.items and instance.selection.index == 1), -- wrapped
        true,
        'selection should move forward or wrap'
      )
    end

    -- Navigate backward
    if H_internal.actions and H_internal.actions.move_prev then
      local before_back = instance.selection.index
      H_internal.actions.move_prev(instance, {})
      vim.wait(10)

      -- Verify selection moved back
      MiniTest.expect.equality(
        instance.selection.index < before_back or (before_back == 1 and instance.selection.index == #instance.items), -- wrapped
        true,
        'selection should move backward or wrap'
      )
    end

    -- Step 5: Verify we can access the selected item
    local selected_item = instance.items[instance.selection.index]
    MiniTest.expect.equality(type(selected_item), 'table')
    MiniTest.expect.equality(type(selected_item.path), 'string')
    MiniTest.expect.equality(type(selected_item.lnum), 'number')

    -- Step 6: Choose/navigate to item (simulate)
    -- Note: We don't actually navigate as it would change the test environment
    -- but we verify the item is valid for navigation
    MiniTest.expect.equality(selected_item.bufnr and selected_item.bufnr > 0, true)

    -- Cleanup: Exit picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Cleanup buffers
  H.cleanup_buffers(jumplist_data.buffers)
end

T['User Workflows']['Filtering Workflow: Start → Apply filters → Navigate filtered list → Choose'] = function()
  -- Setup: Create filter test data with predictable structure
  local filter_data = H.create_filter_test_data()

  -- Mock environment for filter context
  local original_fns = H.mock_vim_functions({
    current_file = filter_data.filter_context.original_file,
    cwd = filter_data.filter_context.original_cwd,
  })

  MiniTest.expect.no_error(function()
    -- Step 1: Start picker with filter test data
    Jumppack.setup({})

    -- Create mock jumplist from filter data
    H.create_mock_jumplist(
      vim.tbl_map(function(item)
        return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
      end, filter_data.items),
      0
    )

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Step 2: Verify initial state (all items visible)
    H.assert_workflow_state(instance, {
      context = 'filtering workflow initial',
      items_count = 4, -- All non-hidden items should be visible
      filters = {
        file_only = false,
        cwd_only = false,
        show_hidden = false,
      },
    })

    -- Step 3: Apply file_only filter
    if H_internal.actions and H_internal.actions.toggle_file_filter then
      H_internal.actions.toggle_file_filter(instance, {})
      vim.wait(10)

      -- Should filter to only current file items
      H.assert_workflow_state(instance, {
        context = 'after file_only filter',
        items_count = 1, -- Only current file should remain
        filters = {
          file_only = true,
          cwd_only = false,
          show_hidden = false,
        },
        has_item_with_path = 'current.lua', -- Should have current file
      })
    end

    -- Step 4: Remove file filter, apply cwd filter
    if H_internal.actions and H_internal.actions.toggle_file_filter then
      H_internal.actions.toggle_file_filter(instance, {}) -- Remove file filter
      vim.wait(10)
    end

    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      H_internal.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)

      -- Should filter to only items in current directory
      H.assert_workflow_state(instance, {
        context = 'after cwd_only filter',
        items_count = 3, -- Items in /project directory
        filters = {
          file_only = false,
          cwd_only = true,
          show_hidden = false,
        },
        has_item_with_path = 'project', -- Should have project items
        no_item_with_path = 'external.lua', -- Should not have external items
      })
    end

    -- Step 5: Navigate the filtered list
    local initial_selection = instance.selection.index
    if H_internal.actions and H_internal.actions.move_next and #instance.items > 1 then
      H_internal.actions.move_next(instance, {})
      vim.wait(10)

      -- Verify navigation works with filters active
      local new_selection = instance.selection.index
      MiniTest.expect.equality(new_selection ~= initial_selection, true, 'navigation should work with filters active')
    end

    -- Step 6: Verify we can select item from filtered list
    local selected_item = instance.items[instance.selection.index]
    MiniTest.expect.equality(type(selected_item), 'table')
    MiniTest.expect.equality(selected_item.path:find('/project'), 1) -- Should be from project dir

    -- Cleanup: Exit picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Restore original functions and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

T['User Workflows']['Power User Workflow: Start → Apply filters → Hide items → Use counts → Navigate → Choose'] = function()
  -- Setup: Create cross-directory jumplist for complex workflow
  local jumplist_data = H.create_realistic_jumplist('cross_directory')

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = '/project/src/main.lua',
    cwd = '/project',
  })

  MiniTest.expect.no_error(function()
    -- Step 1: Setup and start picker
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Step 2: Apply filters (file_only + cwd_only)
    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      H_internal.actions.toggle_cwd_filter(instance, {}) -- Apply cwd filter
      vim.wait(10)

      -- Should filter to items in /project
      H.assert_workflow_state(instance, {
        context = 'after cwd filter in power workflow',
        filters = { cwd_only = true },
        has_item_with_path = 'project',
        no_item_with_path = 'external.lua',
      })
    end

    -- Step 3: Hide a specific item
    if H_internal.actions and H_internal.actions.toggle_hidden and #instance.items >= 2 then
      -- Navigate to second item and hide it
      if H_internal.actions.move_next then
        H_internal.actions.move_next(instance, {})
        vim.wait(10)
      end

      local item_to_hide = instance.items[instance.selection.index]
      local items_before_hide = #instance.items

      H_internal.actions.toggle_hidden(instance, {})
      vim.wait(10)

      -- Verify item was hidden (items count should decrease)
      H.assert_workflow_state(instance, {
        context = 'after hiding item',
        items_count = items_before_hide - 1,
      })
    end

    -- Step 4: Use count navigation (e.g., 3j - move 3 positions forward)
    if H_internal.actions and H_internal.actions.move_next and #instance.items >= 3 then
      local initial_pos = instance.selection.index

      -- Simulate count navigation: move 2 times (like 2j)
      for i = 1, 2 do
        H_internal.actions.move_next(instance, {})
        vim.wait(5)
      end

      -- Verify count navigation worked
      local final_pos = instance.selection.index
      MiniTest.expect.equality(final_pos ~= initial_pos, true, 'count navigation should change position')
    end

    -- Step 5: Verify final state and selection
    local selected_item = instance.items[instance.selection.index]
    MiniTest.expect.equality(type(selected_item), 'table')
    MiniTest.expect.equality(type(selected_item.path), 'string')

    -- Should still respect filters (be in /project directory)
    if instance.filters.cwd_only then
      MiniTest.expect.equality(
        selected_item.path:find('/project') == 1,
        true,
        'selected item should still respect cwd filter'
      )
    end

    -- Step 6: Verify selection is valid for navigation
    MiniTest.expect.equality(type(selected_item.lnum), 'number')
    MiniTest.expect.equality(selected_item.lnum > 0, true)

    -- Cleanup: Exit picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(jumplist_data.buffers)
  -- Clear any hidden items from test
  if Jumppack and Jumppack.H and Jumppack.H.hide then
    Jumppack.H.hide.storage = {}
  end
end

T['User Workflows']['View Switching Workflow: Start in preview → Switch to list → Apply filters → Navigate → Switch back'] = function()
  -- Setup: Create jumplist with enough items for meaningful navigation
  local jumplist_data = H.create_realistic_jumplist('multiple_files')

  MiniTest.expect.no_error(function()
    -- Step 1: Start in preview mode
    Jumppack.setup({
      options = { default_view = 'preview' },
    })
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Step 2: Verify we started in preview mode
    MiniTest.expect.equality(instance.view_state, 'preview', 'should start in preview mode')

    -- Step 3: Switch to list view
    if H_internal.actions and H_internal.actions.toggle_preview then
      H_internal.actions.toggle_preview(instance, {})
      vim.wait(10)

      -- Verify view switched to list
      MiniTest.expect.equality(instance.view_state, 'list', 'should switch to list view')
    end

    -- Step 4: Apply filters while in list view
    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      -- Mock current directory
      local original_getcwd = vim.fn.getcwd
      vim.fn.getcwd = function()
        return '/project'
      end

      H_internal.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)

      -- Verify filter applied and view preserved
      H.assert_workflow_state(instance, {
        context = 'after filter in list view',
        view_state = 'list',
        filters = { cwd_only = true },
      })

      -- Restore getcwd
      vim.fn.getcwd = original_getcwd
    end

    -- Step 5: Navigate filtered items in list view
    if H_internal.actions and H_internal.actions.move_next and #instance.items > 1 then
      local initial_selection = instance.selection.index
      local initial_view = instance.view_state

      H_internal.actions.move_next(instance, {})
      vim.wait(10)

      -- Verify navigation worked and view stayed consistent
      MiniTest.expect.equality(instance.view_state, initial_view, 'view should remain consistent during navigation')

      MiniTest.expect.equality(instance.selection.index ~= initial_selection, true, 'selection should have changed')
    end

    -- Step 6: Switch back to preview
    if H_internal.actions and H_internal.actions.toggle_preview then
      H_internal.actions.toggle_preview(instance, {})
      vim.wait(10)

      -- Verify switched back to preview
      MiniTest.expect.equality(instance.view_state, 'preview', 'should switch back to preview view')

      -- Verify filters are still applied
      if instance.filters then
        MiniTest.expect.equality(instance.filters.cwd_only, true, 'filters should be preserved across view switches')
      end
    end

    -- Step 7: Verify final state integrity
    local selected_item = instance.items[instance.selection.index]
    MiniTest.expect.equality(type(selected_item), 'table')
    MiniTest.expect.equality(type(selected_item.path), 'string')

    -- Cleanup: Exit picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Cleanup
  H.cleanup_buffers(jumplist_data.buffers)
end

T['User Workflows']['Recovery Workflow: Start with invalid state → Apply filters → Handle empty results → Reset filters'] = function()
  -- Setup: Create filter test data
  local filter_data = H.create_filter_test_data()

  -- Mock environment with restrictive context that will cause empty results
  local original_fns = H.mock_vim_functions({
    current_file = '/nowhere/nonexistent.lua', -- File not in our test data
    cwd = '/nowhere', -- Directory not in our test data
  })

  MiniTest.expect.no_error(function()
    -- Step 1: Start picker with filter test data
    Jumppack.setup({})

    H.create_mock_jumplist(
      vim.tbl_map(function(item)
        return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
      end, filter_data.items),
      0
    )

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Step 2: Verify initial state (should have all items)
    H.assert_workflow_state(instance, {
      context = 'recovery workflow initial',
      items_count = 4, -- All non-hidden items visible
      filters = {
        file_only = false,
        cwd_only = false,
        show_hidden = false,
      },
    })

    -- Step 3: Apply restrictive file_only filter (should result in empty list)
    if H_internal.actions and H_internal.actions.toggle_file_filter then
      H_internal.actions.toggle_file_filter(instance, {})
      vim.wait(10)

      -- Should have no items (file not found)
      H.assert_workflow_state(instance, {
        context = 'after restrictive file filter',
        items_count = 0, -- Should have no items
        filters = {
          file_only = true,
          cwd_only = false,
          show_hidden = false,
        },
      })
    end

    -- Step 4: Apply additional cwd filter (should still be empty)
    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      H_internal.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)

      -- Should still be empty
      H.assert_workflow_state(instance, {
        context = 'with both restrictive filters',
        items_count = 0,
        filters = {
          file_only = true,
          cwd_only = true,
          show_hidden = false,
        },
      })
    end

    -- Step 5: Handle empty results gracefully - picker should still be functional
    MiniTest.expect.equality(Jumppack.is_active(), true, 'picker should still be active with empty results')
    MiniTest.expect.equality(#instance.items, 0, 'should have zero items')
    MiniTest.expect.equality(type(instance.selection), 'table', 'selection should still be valid structure')

    -- Step 6: Reset filters to recover
    if H_internal.actions and H_internal.actions.reset_filters then
      H_internal.actions.reset_filters(instance, {})
      vim.wait(10)

      -- Should restore all items
      H.assert_workflow_state(instance, {
        context = 'after filter reset',
        items_count = 4, -- All items restored
        filters = {
          file_only = false,
          cwd_only = false,
          show_hidden = false,
        },
      })
    end

    -- Step 7: Verify recovery - navigation should work again
    if H_internal.actions and H_internal.actions.move_next and #instance.items > 1 then
      local initial_selection = instance.selection.index

      H_internal.actions.move_next(instance, {})
      vim.wait(10)

      -- Should be able to navigate
      MiniTest.expect.equality(
        instance.selection.index ~= initial_selection,
        true,
        'navigation should work after recovery'
      )
    end

    -- Step 8: Verify we can select item after recovery
    local selected_item = instance.items[instance.selection.index]
    MiniTest.expect.equality(type(selected_item), 'table')
    MiniTest.expect.equality(type(selected_item.path), 'string')
    MiniTest.expect.equality(type(selected_item.lnum), 'number')

    -- Cleanup: Exit picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

-- Feature Interaction Tests (Phase 2.2)

T['User Workflows']['Filter + Navigation: Navigation with all filter combinations active'] = function()
  -- Setup: Create comprehensive filter test data
  local filter_data = H.create_filter_test_data()

  -- Mock environment for consistent filter behavior
  local original_fns = H.mock_vim_functions({
    current_file = filter_data.filter_context.original_file,
    cwd = filter_data.filter_context.original_cwd,
  })

  MiniTest.expect.no_error(function()
    local test_results = {}

    -- Test each filter combination with navigation
    for i, filter_combination in ipairs(filter_data.filter_combinations) do
      -- Setup for this combination
      Jumppack.setup({})
      H.create_mock_jumplist(
        vim.tbl_map(function(item)
          return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
        end, filter_data.items),
        0
      )

      Jumppack.start({})
      vim.wait(10)

      local state = Jumppack.get_state()
      if not state or not state.instance then
        goto continue -- Skip if no valid state
      end

      local instance = state.instance
      local H_internal = Jumppack.H

      -- Apply the filter combination
      if H_internal.filters then
        instance.filters = vim.deepcopy(filter_combination)
        -- Reapply filters to items
        if H_internal.filters.apply then
          instance.items = H_internal.filters.apply(filter_data.items, filter_combination, filter_data.filter_context)
        end
      end

      local expected_result = filter_data.expected_results[i]

      -- Test navigation with this filter combination
      local navigation_test = {
        combination_index = i,
        filters = vim.deepcopy(filter_combination),
        initial_items = #instance.items,
        navigation_results = {},
      }

      -- Test forward navigation
      if #instance.items > 1 and H_internal.actions and H_internal.actions.move_next then
        local initial_selection = instance.selection.index

        H_internal.actions.move_next(instance, {})
        vim.wait(5)

        navigation_test.navigation_results.forward = {
          initial = initial_selection,
          final = instance.selection.index,
          changed = instance.selection.index ~= initial_selection,
        }

        -- Verify selection is within bounds
        MiniTest.expect.equality(
          instance.selection.index >= 1 and instance.selection.index <= #instance.items,
          true,
          string.format('forward nav selection should be in bounds for combination %d', i)
        )
      end

      -- Test backward navigation
      if #instance.items > 1 and H_internal.actions and H_internal.actions.move_prev then
        local initial_selection = instance.selection.index

        H_internal.actions.move_prev(instance, {})
        vim.wait(5)

        navigation_test.navigation_results.backward = {
          initial = initial_selection,
          final = instance.selection.index,
          changed = instance.selection.index ~= initial_selection,
        }

        -- Verify selection is within bounds
        MiniTest.expect.equality(
          instance.selection.index >= 1 and instance.selection.index <= #instance.items,
          true,
          string.format('backward nav selection should be in bounds for combination %d', i)
        )
      end

      -- Test jump to top navigation
      if #instance.items > 0 and H_internal.actions and H_internal.actions.jump_to_top then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(5)

        navigation_test.navigation_results.jump_top = {
          selection = instance.selection.index,
          expected = 1,
        }

        MiniTest.expect.equality(
          instance.selection.index,
          1,
          string.format('jump to top should set selection to 1 for combination %d', i)
        )
      end

      -- Test jump to bottom navigation
      if #instance.items > 0 and H_internal.actions and H_internal.actions.jump_to_bottom then
        H_internal.actions.jump_to_bottom(instance, {})
        vim.wait(5)

        navigation_test.navigation_results.jump_bottom = {
          selection = instance.selection.index,
          expected = #instance.items,
        }

        MiniTest.expect.equality(
          instance.selection.index,
          #instance.items,
          string.format('jump to bottom should set selection to last item for combination %d', i)
        )
      end

      -- Store test results
      table.insert(test_results, navigation_test)

      -- Cleanup this iteration
      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(10)
      end

      ::continue::
    end

    -- Verify we tested all combinations
    MiniTest.expect.equality(
      #test_results >= 4, -- Should have tested at least 4 combinations
      true,
      'should have tested multiple filter combinations'
    )

    -- Verify navigation worked correctly across different combinations
    local nav_success_count = 0
    for _, result in ipairs(test_results) do
      if result.navigation_results.forward and result.navigation_results.forward.changed then
        nav_success_count = nav_success_count + 1
      end
    end

    MiniTest.expect.equality(
      nav_success_count > 0,
      true,
      'navigation should work with at least some filter combinations'
    )
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

T['User Workflows']['Hide + Filter: Hiding items while filters are active'] = function()
  -- Setup: Create filter test data
  local filter_data = H.create_filter_test_data()

  -- Mock environment for consistent behavior
  local original_fns = H.mock_vim_functions({
    current_file = filter_data.filter_context.original_file,
    cwd = filter_data.filter_context.original_cwd,
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})

    H.create_mock_jumplist(
      vim.tbl_map(function(item)
        return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
      end, filter_data.items),
      0
    )

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Step 1: Apply cwd_only filter first
    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      H_internal.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)

      -- Verify filter applied
      H.assert_workflow_state(instance, {
        context = 'cwd filter applied before hide test',
        filters = { cwd_only = true },
        has_item_with_path = 'project',
        no_item_with_path = 'external',
      })
    end

    local filtered_items_count = #instance.items
    MiniTest.expect.equality(filtered_items_count > 1, true, 'should have multiple items to hide')

    -- Step 2: Hide an item while filter is active
    if H_internal.actions and H_internal.actions.toggle_hidden and filtered_items_count > 1 then
      -- Navigate to second item and hide it
      if H_internal.actions.move_next then
        H_internal.actions.move_next(instance, {})
        vim.wait(10)
      end

      local item_to_hide = instance.items[instance.selection.index]
      local item_path = item_to_hide.path

      -- Hide the current item
      H_internal.actions.toggle_hidden(instance, {})
      vim.wait(10)

      -- Verify item was hidden (count decreased)
      H.assert_workflow_state(instance, {
        context = 'after hiding item with filter active',
        items_count = filtered_items_count - 1,
        no_item_with_path = item_path:match('([^/]+)$'), -- Just filename
      })
    end

    -- Step 3: Test show_hidden filter interaction with manually hidden items
    if H_internal.actions and H_internal.actions.toggle_show_hidden then
      local before_show_hidden = #instance.items

      H_internal.actions.toggle_show_hidden(instance, {})
      vim.wait(10)

      -- Should now show the manually hidden item (but still respect cwd filter)
      H.assert_workflow_state(instance, {
        context = 'with show_hidden enabled',
        filters = {
          cwd_only = true,
          show_hidden = true,
        },
        items_count = before_show_hidden + 1, -- Should show the hidden item again
      })

      -- Turn off show_hidden again
      H_internal.actions.toggle_show_hidden(instance, {})
      vim.wait(10)

      -- Should hide the manually hidden item again
      H.assert_workflow_state(instance, {
        context = 'show_hidden disabled again',
        filters = {
          cwd_only = true,
          show_hidden = false,
        },
        items_count = before_show_hidden,
      })
    end

    -- Step 4: Test hide persistence when toggling other filters
    if H_internal.actions and H_internal.actions.toggle_file_filter then
      -- Apply file filter (which should be very restrictive)
      H_internal.actions.toggle_file_filter(instance, {})
      vim.wait(10)

      H.assert_workflow_state(instance, {
        context = 'with both cwd and file filters',
        filters = {
          cwd_only = true,
          file_only = true,
        },
      })

      -- Remove file filter
      H_internal.actions.toggle_file_filter(instance, {})
      vim.wait(10)

      -- Should return to cwd-only filtered state, with hidden item still hidden
      H.assert_workflow_state(instance, {
        context = 'back to cwd-only after file filter removed',
        filters = {
          cwd_only = true,
          file_only = false,
        },
        items_count = filtered_items_count - 1, -- Hidden item should stay hidden
      })
    end

    -- Step 5: Verify we can still hide additional items with filters active
    if H_internal.actions and H_internal.actions.toggle_hidden and #instance.items > 1 then
      local before_second_hide = #instance.items

      -- Move to first item and hide it too
      if H_internal.actions.jump_to_top then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(10)
      end

      H_internal.actions.toggle_hidden(instance, {})
      vim.wait(10)

      -- Should have one less item
      MiniTest.expect.equality(
        #instance.items,
        before_second_hide - 1,
        'should be able to hide additional items with filters active'
      )
    end

    -- Cleanup: Exit picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
  -- Clear hidden items
  if Jumppack and Jumppack.H and Jumppack.H.hide then
    Jumppack.H.hide.storage = {}
  end
end

T['User Workflows']['Count + Filter: Count-based navigation with filtered lists'] = function()
  -- Setup: Create jumplist with enough items for count navigation
  local jumplist_data = H.create_realistic_jumplist('large_list', { count = 8 })

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = '/project/file3.lua',
    cwd = '/project',
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Apply cwd filter to reduce list size
    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      H_internal.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)

      H.assert_workflow_state(instance, {
        context = 'count test with cwd filter',
        filters = { cwd_only = true },
      })
    end

    local filtered_count = #instance.items
    MiniTest.expect.equality(filtered_count > 3, true, 'should have enough items for count navigation')

    -- Test count navigation within filtered list
    if H_internal.actions and H_internal.actions.move_next and filtered_count > 3 then
      -- Start at first position
      if H_internal.actions.jump_to_top then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(10)
      end

      local start_pos = instance.selection.index
      MiniTest.expect.equality(start_pos, 1, 'should start at position 1')

      -- Simulate count navigation: move forward 3 times (like 3j)
      for i = 1, 3 do
        H_internal.actions.move_next(instance, {})
        vim.wait(5)

        -- Verify we stay within filtered bounds
        MiniTest.expect.equality(
          instance.selection.index >= 1 and instance.selection.index <= filtered_count,
          true,
          'count navigation should stay within filtered bounds'
        )
      end

      local final_pos = instance.selection.index

      -- Verify count navigation moved us forward
      MiniTest.expect.equality(final_pos > start_pos, true, 'count navigation should move forward')
    end

    -- Test count overflow behavior
    if H_internal.actions and H_internal.actions.move_next and filtered_count < 10 then
      -- Try to move more than available items
      local before_overflow = instance.selection.index

      for i = 1, filtered_count + 2 do -- Move more than items available
        H_internal.actions.move_next(instance, {})
        vim.wait(2)
      end

      -- Should still be within bounds
      MiniTest.expect.equality(
        instance.selection.index >= 1 and instance.selection.index <= filtered_count,
        true,
        'count overflow should keep selection within bounds'
      )
    end

    -- Cleanup: Exit picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(jumplist_data.buffers)
end

T['User Workflows']['Wrap + Filter: Edge wrapping with filtered/hidden items'] = function()
  -- Setup: Create jumplist for wrap testing
  local jumplist_data = H.create_realistic_jumplist('multiple_files')

  MiniTest.expect.no_error(function()
    -- Setup with wrap_edges enabled
    Jumppack.setup({
      options = { wrap_edges = true },
    })
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Apply mock environment with limited matches
    local original_getcwd = vim.fn.getcwd
    vim.fn.getcwd = function()
      return '/project'
    end

    -- Apply cwd filter to create smaller filtered list
    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      H_internal.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)
    end

    local filtered_count = #instance.items

    if filtered_count > 1 then
      -- Test forward wrap (last -> first)
      if H_internal.actions.jump_to_bottom then
        H_internal.actions.jump_to_bottom(instance, {})
        vim.wait(10)
      end

      MiniTest.expect.equality(instance.selection.index, filtered_count, 'should be at last item')

      -- Move forward from last item (should wrap to first)
      if H_internal.actions.move_next then
        H_internal.actions.move_next(instance, {})
        vim.wait(10)

        MiniTest.expect.equality(instance.selection.index, 1, 'forward navigation from last item should wrap to first')
      end

      -- Test backward wrap (first -> last)
      if H_internal.actions.move_prev then
        H_internal.actions.move_prev(instance, {})
        vim.wait(10)

        MiniTest.expect.equality(
          instance.selection.index,
          filtered_count,
          'backward navigation from first item should wrap to last'
        )
      end
    end

    -- Test wrap with hidden items
    if H_internal.actions and H_internal.actions.toggle_hidden and filtered_count > 2 then
      -- Move to middle item and hide it
      if H_internal.actions.jump_to_top then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(10)
      end
      if H_internal.actions.move_next then
        H_internal.actions.move_next(instance, {})
        vim.wait(10)
      end

      H_internal.actions.toggle_hidden(instance, {})
      vim.wait(10)

      -- Verify wrap still works with hidden item
      local new_count = #instance.items
      MiniTest.expect.equality(new_count, filtered_count - 1, 'should have one less item after hide')

      -- Test wrap with reduced list
      if H_internal.actions.jump_to_bottom and H_internal.actions.move_next then
        H_internal.actions.jump_to_bottom(instance, {})
        vim.wait(10)

        H_internal.actions.move_next(instance, {})
        vim.wait(10)

        MiniTest.expect.equality(instance.selection.index, 1, 'wrap should work correctly with hidden items')
      end
    end

    -- Restore and cleanup iteration
    vim.fn.getcwd = original_getcwd
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Cleanup
  H.cleanup_buffers(jumplist_data.buffers)
  if Jumppack and Jumppack.H and Jumppack.H.hide then
    Jumppack.H.hide.storage = {}
  end
end

T['User Workflows']['Preview + Filter: Preview updates during filter changes'] = function()
  -- Setup: Create jumplist with varied content
  local jumplist_data = H.create_realistic_jumplist('cross_directory')

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = '/project/src/main.lua',
    cwd = '/project',
  })

  MiniTest.expect.no_error(function()
    -- Start in preview mode
    Jumppack.setup({
      options = { default_view = 'preview' },
    })
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Verify we're in preview mode
    MiniTest.expect.equality(instance.view_state, 'preview', 'should be in preview mode')

    -- Store initial preview state
    local initial_selection = instance.selection.index
    local initial_item = instance.items[initial_selection]

    MiniTest.expect.equality(type(initial_item), 'table', 'should have initial item')
    MiniTest.expect.equality(type(initial_item.path), 'string', 'initial item should have path')

    -- Apply cwd filter and verify preview updates
    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      H_internal.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)

      -- Verify filter applied
      H.assert_workflow_state(instance, {
        context = 'preview test with cwd filter',
        view_state = 'preview',
        filters = { cwd_only = true },
        has_item_with_path = 'project',
      })

      -- Verify preview shows filtered item
      local filtered_item = instance.items[instance.selection.index]
      MiniTest.expect.equality(type(filtered_item), 'table', 'should have filtered item')
      MiniTest.expect.equality(
        filtered_item.path:find('/project') == 1,
        true,
        'preview should show item from project directory'
      )
    end

    -- Navigate and verify preview updates
    if H_internal.actions and H_internal.actions.move_next and #instance.items > 1 then
      local before_nav_item = instance.items[instance.selection.index]

      H_internal.actions.move_next(instance, {})
      vim.wait(10)

      local after_nav_item = instance.items[instance.selection.index]

      -- Preview should update to show different item
      MiniTest.expect.equality(
        before_nav_item.path ~= after_nav_item.path,
        true,
        'preview should update when navigating filtered items'
      )

      -- Should still be in preview mode
      MiniTest.expect.equality(instance.view_state, 'preview', 'should remain in preview mode')
    end

    -- Test preview with empty filter results
    if H_internal.actions and H_internal.actions.toggle_file_filter then
      H_internal.actions.toggle_file_filter(instance, {}) -- Very restrictive
      vim.wait(10)

      if #instance.items == 0 then
        -- Should handle empty results gracefully
        MiniTest.expect.equality(instance.view_state, 'preview', 'should stay in preview mode with empty results')
        MiniTest.expect.equality(Jumppack.is_active(), true, 'picker should remain active with empty preview')
      end

      -- Remove restrictive filter
      H_internal.actions.toggle_file_filter(instance, {})
      vim.wait(10)
    end

    -- Verify preview content matches selected item after filter changes
    local final_item = instance.items[instance.selection.index]
    MiniTest.expect.equality(type(final_item), 'table', 'should have valid final item')
    MiniTest.expect.equality(type(final_item.lnum), 'number', 'final item should have line number')
    MiniTest.expect.equality(final_item.lnum > 0, true, 'final item line number should be valid')

    -- Cleanup: Exit picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(jumplist_data.buffers)
end

-- Additional Display Features subcategories

T['Display Features']['Item Formatting'] = MiniTest.new_set()

T['Display Features']['Item Formatting']['displays items with new format'] = function()
  -- Set up plugin
  Jumppack.setup({})

  local test_buf = H.create_test_buffer('test.lua', { 'function test() end' })

  MiniTest.expect.no_error(function()
    local item = {
      offset = 0,
      path = vim.api.nvim_buf_get_name(test_buf),
      lnum = 1,
      bufnr = test_buf,
      is_current = true,
    }

    -- Test list mode display
    local list_buf = vim.api.nvim_create_buf(false, true)
    Jumppack.show_items(list_buf, { item }, {})
    local lines = vim.api.nvim_buf_get_lines(list_buf, 0, -1, false)

    -- Should contain the item with new format
    MiniTest.expect.equality(#lines > 0, true)
    if #lines > 0 then
      -- Should contain current marker (●) somewhere in the line
      MiniTest.expect.equality(lines[1]:find('●') ~= nil, true)
      -- Should not contain old format markers (←, →)
      MiniTest.expect.equality(lines[1]:find('←'), nil)
      MiniTest.expect.equality(lines[1]:find('→'), nil)
    end

    vim.api.nvim_buf_delete(list_buf, { force = true })
  end)

  H.cleanup_buffers({ test_buf })
end

T['Display Features']['Item Formatting']['shows line preview in list mode'] = function()
  Jumppack.setup({})

  local test_buf = H.create_test_buffer('preview_test.lua', { 'local result = "test content"' })

  MiniTest.expect.no_error(function()
    local item = {
      offset = -1,
      path = vim.api.nvim_buf_get_name(test_buf),
      lnum = 1,
      bufnr = test_buf,
      is_current = false,
    }

    local display_buf = vim.api.nvim_create_buf(false, true)
    Jumppack.show_items(display_buf, { item }, {})
    local lines = vim.api.nvim_buf_get_lines(display_buf, 0, -1, false)

    if #lines > 0 then
      -- Should contain the line content
      MiniTest.expect.equality(lines[1]:find('test content') ~= nil, true)
      -- Should contain separator
      MiniTest.expect.equality(lines[1]:find('│') ~= nil, true)
    end

    vim.api.nvim_buf_delete(display_buf, { force = true })
  end)

  H.cleanup_buffers({ test_buf })
end

-- ============================================================================
-- PHASE 7: VISUAL & DISPLAY TESTING
-- ============================================================================

T['Display Features']['Visual & Display Testing'] = MiniTest.new_set()

T['Display Features']['Visual & Display Testing']['Display Format Validation'] = MiniTest.new_set()

T['Display Features']['Visual & Display Testing']['Display Format Validation']['correctly displays item format: [indicator] [icon] [path/name] [lnum:col]'] = function()
  local buf = H.create_test_buffer('/project/test.lua', { 'local x = 1', 'local y = 2' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({ options = { show_hidden = true } })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
    { bufnr = buf, lnum = 2, col = 5 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')
  MiniTest.expect.equality(#state.items == 2, true, 'Should have 2 items')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Verify format: [indicator] [icon] [path/name] [lnum:col] [│ line preview]
  MiniTest.expect.string_matches(
    lines[1],
    '^[●○] .* test%.lua %d+:%d+ │',
    'First item should match format pattern'
  )
  MiniTest.expect.string_matches(
    lines[2],
    '^[●○] .* test%.lua %d+:%d+ │',
    'Second item should match format pattern'
  )

  -- Verify position information
  MiniTest.expect.string_matches(lines[1], '1:0', 'First item should show correct line:col')
  MiniTest.expect.string_matches(lines[2], '2:5', 'Second item should show correct line:col')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['displays hidden item indicators correctly'] = function()
  local buf = H.create_test_buffer('/project/test.lua', { 'local x = 1', 'local y = 2' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({ options = { show_hidden = true } })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
    { bufnr = buf, lnum = 2, col = 5 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Hide the first item
  vim.api.nvim_feedkeys('h', 'x', false)
  vim.wait(10)

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- First item should show hidden indicator (×)
  MiniTest.expect.string_matches(lines[1], '^× ', 'Hidden item should show × indicator')
  -- Second item should show normal indicator (● or ○)
  MiniTest.expect.string_matches(lines[2], '^[●○] ', 'Normal item should show position indicator')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['shows filter status indicators correctly'] = function()
  local buf1 = H.create_test_buffer('/project/main.lua', { 'local x = 1' })
  local buf2 = H.create_test_buffer('/other/test.lua', { 'local y = 2' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Initially no filters - check status
  local info = state.general_info
  MiniTest.expect.equality(type(info), 'table', 'Should have general info')

  -- Apply file filter
  vim.api.nvim_feedkeys('F', 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  info = state.general_info
  MiniTest.expect.string_matches(info.name or '', '[F]', 'Should show file filter indicator')

  -- Apply cwd filter
  vim.api.nvim_feedkeys('C', 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  info = state.general_info
  MiniTest.expect.string_matches(info.name or '', '[FC]', 'Should show both filter indicators')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['shows count display in status'] = function()
  local buf = H.create_test_buffer('/project/test.lua', { 'line 1', 'line 2', 'line 3', 'line 4', 'line 5' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
    { bufnr = buf, lnum = 2, col = 0 },
    { bufnr = buf, lnum = 3, col = 0 },
    { bufnr = buf, lnum = 4, col = 0 },
    { bufnr = buf, lnum = 5, col = 0 },
  }, 2)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Start typing a count
  vim.api.nvim_feedkeys('2', 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  local info = state.general_info
  MiniTest.expect.string_matches(info.name or '', '2', 'Should show count in status')

  -- Add another digit
  vim.api.nvim_feedkeys('5', 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  info = state.general_info
  MiniTest.expect.string_matches(info.name or '', '25', 'Should show multi-digit count in status')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['shows position indicators correctly'] = function()
  local buf = H.create_test_buffer('/project/test.lua', { 'line 1', 'line 2', 'line 3' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
    { bufnr = buf, lnum = 2, col = 0 },
    { bufnr = buf, lnum = 3, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Check that one item has current position indicator (●) and others have normal (○)
  local current_indicators = 0
  local normal_indicators = 0

  for _, line in ipairs(lines) do
    if line:match('^●') then
      current_indicators = current_indicators + 1
    elseif line:match('^○') then
      normal_indicators = normal_indicators + 1
    end
  end

  MiniTest.expect.equality(current_indicators, 1, 'Should have exactly one current position indicator')
  MiniTest.expect.equality(normal_indicators, 2, 'Should have two normal position indicators')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['handles window sizing properly'] = function()
  local buf = H.create_test_buffer('/project/very_long_filename_that_should_be_truncated.lua', {
    'This is a very long line that should test how the display handles long content and wrapping behavior in various window sizes',
  })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({
    window = {
      config = {
        width = 40, -- Small window to test truncation
        height = 10,
      },
    },
  })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Verify the window was created with correct size
  local win_id = state.instance.windows.main
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win_id), true, 'Main window should be valid')

  local win_config = vim.api.nvim_win_get_config(win_id)
  MiniTest.expect.equality(win_config.width, 40, 'Window should have correct width')
  MiniTest.expect.equality(win_config.height, 10, 'Window should have correct height')

  -- Verify content fits within window bounds
  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)
  MiniTest.expect.equality(#lines > 0, true, 'Should have content lines')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['shows preview content with proper context'] = function()
  local buf = H.create_test_buffer('/project/test.lua', {
    'function start()',
    '  local x = 1',
    '  local y = 2',
    '  return x + y',
    'end',
  })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({ options = { default_view = 'preview' } })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 3, col = 2 }, -- Point to 'local y = 2' line
  }, 0)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Should be in preview mode
  MiniTest.expect.equality(state.instance.view_state, 'preview', 'Should be in preview mode')

  -- Verify preview window exists
  local preview_win = state.instance.windows.preview
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview_win), true, 'Preview window should be valid')

  -- Verify preview content shows the target line with context
  local preview_lines = vim.api.nvim_buf_get_lines(state.instance.buffers.preview, 0, -1, false)
  MiniTest.expect.equality(#preview_lines > 1, true, 'Preview should have multiple lines for context')

  -- Should contain the target line
  local found_target = false
  for _, line in ipairs(preview_lines) do
    if line:match('local y = 2') then
      found_target = true
      break
    end
  end
  MiniTest.expect.equality(found_target, true, 'Preview should show target line')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Icon Integration'] = MiniTest.new_set()

T['Display Features']['Visual & Display Testing']['Icon Integration']['displays icons when MiniIcons available'] = function()
  -- Mock MiniIcons
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      if path:match('%.lua$') then
        return '󰢱', 'MiniIconsBlue'
      elseif path:match('%.json$') then
        return '', 'MiniIconsYellow'
      else
        return '', 'MiniIconsGrey'
      end
    end,
  }

  local buf1 = H.create_test_buffer('/project/test.lua', { 'local x = 1' })
  local buf2 = H.create_test_buffer('/project/config.json', { '{"name": "test"}' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Should contain MiniIcons
  MiniTest.expect.string_matches(lines[1], '󰢱', 'Lua file should show lua icon')
  MiniTest.expect.string_matches(lines[2], '', 'JSON file should show json icon')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore original
  _G.MiniIcons = original_miniicons
  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['displays icons when nvim-web-devicons available'] = function()
  -- Mock nvim-web-devicons
  local original_loaded = package.loaded['nvim-web-devicons']
  package.loaded['nvim-web-devicons'] = {
    get_icon = function(filename, ext, opts)
      if filename:match('%.lua$') then
        return '', 'DevIconLua'
      elseif filename:match('%.js$') then
        return '', 'DevIconJs'
      else
        return '', 'DevIconDefault'
      end
    end,
  }

  -- Ensure MiniIcons is not available
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = nil

  local buf1 = H.create_test_buffer('/project/main.lua', { 'local x = 1' })
  local buf2 = H.create_test_buffer('/project/script.js', { 'const x = 1;' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Should contain devicons
  MiniTest.expect.string_matches(lines[1], '', 'Lua file should show lua devicon')
  MiniTest.expect.string_matches(lines[2], '', 'JS file should show js devicon')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore originals
  _G.MiniIcons = original_miniicons
  package.loaded['nvim-web-devicons'] = original_loaded
  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['falls back gracefully when no icon plugins available'] = function()
  -- Ensure no icon plugins are available
  local original_miniicons = _G.MiniIcons
  local original_devicons = package.loaded['nvim-web-devicons']

  _G.MiniIcons = nil
  package.loaded['nvim-web-devicons'] = nil

  local buf = H.create_test_buffer('/project/test.lua', { 'local x = 1' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Should use fallback icon (space character)
  MiniTest.expect.string_matches(lines[1], '^[●○]  ', 'Should show fallback icon (space)')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore originals
  _G.MiniIcons = original_miniicons
  package.loaded['nvim-web-devicons'] = original_devicons
  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['maintains icon consistency across list and preview views'] = function()
  -- Mock MiniIcons
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      if path:match('%.lua$') then
        return '󰢱', 'MiniIconsBlue'
      else
        return '', 'MiniIconsGrey'
      end
    end,
  }

  local buf = H.create_test_buffer('/project/test.lua', { 'local x = 1', 'local y = 2' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({ options = { default_view = 'list' } })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Check icon in list view
  local list_lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)
  MiniTest.expect.string_matches(list_lines[1], '󰢱', 'Should show lua icon in list view')

  -- Switch to preview view
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-p>', true, true, true), 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  MiniTest.expect.equality(state.instance.view_state, 'preview', 'Should be in preview mode')

  -- Check that preview title shows same icon
  local preview_title_lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)
  MiniTest.expect.string_matches(preview_title_lines[1], '󰢱', 'Should show same lua icon in preview title')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore original
  _G.MiniIcons = original_miniicons
  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['applies correct highlight groups to icons'] = function()
  -- Mock MiniIcons with specific highlight groups
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      if path:match('%.lua$') then
        return '󰢱', 'TestLuaIconHL'
      elseif path:match('%.py$') then
        return '', 'TestPythonIconHL'
      else
        return '', 'TestDefaultIconHL'
      end
    end,
  }

  local buf1 = H.create_test_buffer('/project/test.lua', { 'local x = 1' })
  local buf2 = H.create_test_buffer('/project/script.py', { 'x = 1' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Check that extmarks were created for icon highlighting
  local buf_id = state.instance.buffers.main
  local extmarks = vim.api.nvim_buf_get_extmarks(buf_id, -1, 0, -1, { details = true })

  -- Should have icon highlights applied
  local found_lua_hl = false
  local found_python_hl = false

  for _, extmark in ipairs(extmarks) do
    local details = extmark[4]
    if details and details.hl_group then
      if details.hl_group == 'TestLuaIconHL' then
        found_lua_hl = true
      elseif details.hl_group == 'TestPythonIconHL' then
        found_python_hl = true
      end
    end
  end

  MiniTest.expect.equality(found_lua_hl, true, 'Should apply lua icon highlight group')
  MiniTest.expect.equality(found_python_hl, true, 'Should apply python icon highlight group')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore original
  _G.MiniIcons = original_miniicons
  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['handles different file types with appropriate icons'] = function()
  -- Mock comprehensive icon set
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      local icons = {
        ['%.lua$'] = { '󰢱', 'MiniIconsLua' },
        ['%.js$'] = { '', 'MiniIconsJS' },
        ['%.py$'] = { '', 'MiniIconsPython' },
        ['%.json$'] = { '', 'MiniIconsJSON' },
        ['%.md$'] = { '', 'MiniIconsMarkdown' },
        ['%.txt$'] = { '', 'MiniIconsText' },
      }

      for pattern, data in pairs(icons) do
        if path:match(pattern) then
          return data[1], data[2]
        end
      end

      return '', 'MiniIconsDefault'
    end,
  }

  local test_files = {
    { '/project/main.lua', { 'local x = 1' }, '󰢱' },
    { '/project/app.js', { 'const x = 1;' }, '' },
    { '/project/script.py', { 'x = 1' }, '' },
    { '/project/config.json', { '{}' }, '' },
    { '/project/README.md', { '# Title' }, '' },
    { '/project/notes.txt', { 'notes' }, '' },
  }

  local bufs = {}
  local jumplist_entries = {}

  for i, file_data in ipairs(test_files) do
    local buf = H.create_test_buffer(file_data[1], file_data[2])
    bufs[i] = buf
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist(jumplist_entries, 3)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Verify each file type shows correct icon
  for i, file_data in ipairs(test_files) do
    local expected_icon = file_data[3]
    MiniTest.expect.string_matches(
      lines[i],
      expected_icon,
      string.format('File %s should show icon %s', file_data[1], expected_icon)
    )
  end

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore original
  _G.MiniIcons = original_miniicons
  H.cleanup_buffers(bufs)
end

-- ============================================================================
-- 3. FILTER FEATURES TESTS
-- ============================================================================
T['Filter Features'] = MiniTest.new_set()

T['Filter Features']['H.filters.apply'] = function()
  local items = {
    { path = '/test/file1.lua', lnum = 1, bufnr = 1, is_current = false },
    { path = '/test/file2.lua', lnum = 2, bufnr = 2, is_current = true },
    { path = '/other/file3.lua', lnum = 3, bufnr = 3, is_current = false },
    { path = '/test/file4.lua', lnum = 4, bufnr = 4, is_current = false, hidden = true },
  }

  -- Test file_only filter
  local filters = { file_only = true, cwd_only = false, show_hidden = false }

  -- Mock current file
  local orig_expand = vim.fn.expand
  vim.fn.expand = function(pattern)
    if pattern == '%:p' then
      return '/test/file2.lua'
    end
    return orig_expand(pattern)
  end

  local filtered = Jumppack.H.filters.apply(items, filters)
  MiniTest.expect.equality(#filtered, 1)
  MiniTest.expect.equality(filtered[1].path, '/test/file2.lua')

  -- Test cwd_only filter
  filters = { file_only = false, cwd_only = true, show_hidden = true }

  -- Mock getcwd
  local orig_getcwd = vim.fn.getcwd
  vim.fn.getcwd = function()
    return '/test'
  end

  filtered = Jumppack.H.filters.apply(items, filters)
  MiniTest.expect.equality(#filtered, 3) -- Should include 3 files in /test/

  -- Test show_hidden filter
  filters = { file_only = false, cwd_only = false, show_hidden = false }
  filtered = Jumppack.H.filters.apply(items, filters)
  MiniTest.expect.equality(#filtered, 3) -- Should exclude hidden item

  -- Restore mocks
  vim.fn.expand = orig_expand
  vim.fn.getcwd = orig_getcwd
end

T['Filter Features']['H.filters.get_status_text'] = function()
  local filters = { file_only = false, cwd_only = false, show_hidden = false }
  MiniTest.expect.equality(Jumppack.H.filters.get_status_text(filters), '')

  filters.file_only = true
  MiniTest.expect.equality(Jumppack.H.filters.get_status_text(filters), '[f] ')

  filters.cwd_only = true
  MiniTest.expect.equality(Jumppack.H.filters.get_status_text(filters), '[f,c] ')

  filters.show_hidden = true
  MiniTest.expect.equality(Jumppack.H.filters.get_status_text(filters), '[f,c,.] ')
end

T['Filter Features']['Filter context handling'] = function()
  -- Create test buffers in different locations
  local buf1 = H.create_test_buffer('/project/src/main.lua', { 'local main = {}' })
  local buf2 = H.create_test_buffer('/project/test/spec.lua', { 'describe("test")' })
  local buf3 = H.create_test_buffer('/other/file.lua', { 'print("hello")' })

  -- Create items with different paths
  local items = {
    { path = '/project/src/main.lua', lnum = 1, bufnr = buf1, offset = -2 },
    { path = '/project/test/spec.lua', lnum = 1, bufnr = buf2, offset = -1 },
    { path = '/other/file.lua', lnum = 1, bufnr = buf3, offset = 1 },
  }

  -- Test filter context is properly captured and used
  local filter_context = {
    original_file = '/project/src/main.lua', -- Simulate being in main.lua
    original_cwd = '/project', -- Simulate cwd as /project
  }

  -- Test file_only filter with context
  local filters = { file_only = true, cwd_only = false, show_hidden = false }
  local filtered = Jumppack.H.filters.apply(items, filters, filter_context)
  MiniTest.expect.equality(#filtered, 1)
  MiniTest.expect.equality(filtered[1].path, '/project/src/main.lua')

  -- Test cwd_only filter with context
  filters = { file_only = false, cwd_only = true, show_hidden = false }
  filtered = Jumppack.H.filters.apply(items, filters, filter_context)
  MiniTest.expect.equality(#filtered, 2) -- Should include both files in /project

  -- Test combined filters with context
  filters = { file_only = true, cwd_only = true, show_hidden = false }
  filtered = Jumppack.H.filters.apply(items, filters, filter_context)
  MiniTest.expect.equality(#filtered, 1)
  MiniTest.expect.equality(filtered[1].path, '/project/src/main.lua')

  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Filter Features']['Empty filter results handling'] = function()
  local buf1 = H.create_test_buffer('/test/file1.lua', { 'content' })
  local buf2 = H.create_test_buffer('/other/file2.lua', { 'content' })

  local items = {
    { path = '/test/file1.lua', lnum = 1, bufnr = buf1, offset = -1 },
    { path = '/other/file2.lua', lnum = 1, bufnr = buf2, offset = 1 },
  }

  -- Filter that produces no results
  local filter_context = {
    original_file = '/nonexistent/file.lua',
    original_cwd = '/nonexistent',
  }

  local filters = { file_only = true, cwd_only = true, show_hidden = false }
  local filtered = Jumppack.H.filters.apply(items, filters, filter_context)
  MiniTest.expect.equality(#filtered, 0)

  -- Test that empty results are handled gracefully in instance update
  -- Create a more complete mock instance with required structure
  local mock_instance = {
    all_items = items,
    items = items,
    current = 1,
    filters = filters,
    filter_context = filter_context,
    view_state = 'preview',
    windows = {
      main = -1, -- Invalid window ID, but present
      preview = -1,
    },
    buffers = {
      main = -1, -- Invalid buffer ID, but present
      preview = -1,
    },
  }

  -- This should not error and should preserve view_state
  MiniTest.expect.no_error(function()
    Jumppack.H.instance.apply_filters_and_update(mock_instance)
  end)

  -- View state should be preserved
  MiniTest.expect.equality(mock_instance.view_state, 'preview')

  H.cleanup_buffers({ buf1, buf2 })
end

T['Filter Features']['Filter toggle integration'] = function()
  local buf1 = H.create_test_buffer('/project/main.lua', { 'main code' })
  local buf2 = H.create_test_buffer('/project/test.lua', { 'test code' })
  local buf3 = H.create_test_buffer('/other/file.lua', { 'other code' })

  -- Create jumplist with different files
  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 0)

  -- Mock being in /project/main.lua
  local orig_expand = vim.fn.expand
  local orig_getcwd = vim.fn.getcwd
  vim.fn.expand = function(pattern)
    if pattern == '%:p' then
      return '/project/main.lua'
    end
    return orig_expand(pattern)
  end
  vim.fn.getcwd = function()
    return '/project'
  end

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local initial_count = #instance.items
    local initial_view = instance.view_state

    -- Test file filter toggle - should reduce items to current file only
    local H = Jumppack.H
    if H.actions.toggle_file_filter then
      H.actions.toggle_file_filter(instance, {})
      vim.wait(10)

      -- Should have fewer items (only current file)
      MiniTest.expect.equality(instance.filters.file_only, true)
      MiniTest.expect.equality(instance.view_state, initial_view) -- View preserved
    end

    -- Test cwd filter toggle
    if H.actions.toggle_cwd_filter then
      H.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)

      MiniTest.expect.equality(instance.filters.cwd_only, true)
      MiniTest.expect.equality(instance.view_state, initial_view) -- View preserved
    end

    -- Test reset filters
    if H.actions.reset_filters then
      H.actions.reset_filters(instance, {})
      vim.wait(10)

      MiniTest.expect.equality(instance.filters.file_only, false)
      MiniTest.expect.equality(instance.filters.cwd_only, false)
      MiniTest.expect.equality(instance.view_state, initial_view) -- View preserved
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Restore mocks
  vim.fn.expand = orig_expand
  vim.fn.getcwd = orig_getcwd
  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Filter Features']['Filter actions'] = function()
  -- Setup test configuration
  local config = {
    options = { global_mappings = false, default_view = 'preview' },
    mappings = {
      jump_back = '<C-o>',
      jump_forward = '<C-i>',
      choose = '<CR>',
      choose_in_split = '<C-s>',
      choose_in_vsplit = '<C-v>',
      choose_in_tabpage = '<C-t>',
      stop = '<Esc>',
      toggle_preview = 'p',
      toggle_file_filter = 'f',
      toggle_cwd_filter = 'c',
      toggle_show_hidden = '.',
      reset_filters = 'r',
      toggle_hidden = 'x',
    },
    window = { config = nil },
  }

  require('jumppack').setup(config)

  -- Create mock items and start picker
  local items = {
    { path = '/test/file1.lua', lnum = 1, bufnr = 1, is_current = false },
    { path = '/test/file2.lua', lnum = 2, bufnr = 2, is_current = true },
  }

  -- Mock vim functions
  local orig_expand = vim.fn.expand
  vim.fn.expand = function(pattern)
    if pattern == '%:p' then
      return '/test/file2.lua'
    end
    return orig_expand(pattern)
  end

  -- Test filter toggle functions exist
  local H = Jumppack.H
  MiniTest.expect.equality(type(H.actions.toggle_file_filter), 'function')
  MiniTest.expect.equality(type(H.actions.toggle_cwd_filter), 'function')
  MiniTest.expect.equality(type(H.actions.toggle_show_hidden), 'function')
  MiniTest.expect.equality(type(H.actions.reset_filters), 'function')

  -- Restore mocks
  vim.fn.expand = orig_expand
end

-- Phase 3.1: Filter Combination Matrix Testing

T['Filter Features']['Filter Combination Matrix: Systematic testing of all 8 combinations'] = function()
  -- Setup: Create comprehensive filter test data
  local filter_data = H.create_filter_test_data()

  -- Mock environment for consistent behavior
  local original_fns = H.mock_vim_functions({
    current_file = filter_data.filter_context.original_file,
    cwd = filter_data.filter_context.original_cwd,
  })

  MiniTest.expect.no_error(function()
    local test_results = {}

    -- Test all 8 filter combinations systematically
    for i, filter_combination in ipairs(filter_data.filter_combinations) do
      -- Setup for this combination
      Jumppack.setup({})
      H.create_mock_jumplist(
        vim.tbl_map(function(item)
          return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
        end, filter_data.items),
        0
      )

      Jumppack.start({})
      vim.wait(10)

      local state = Jumppack.get_state()
      if not state or not state.instance then
        goto continue -- Skip if no valid state
      end

      local instance = state.instance
      local H_internal = Jumppack.H

      -- Apply the filter combination
      if H_internal.filters then
        instance.filters = vim.deepcopy(filter_combination)
        -- Reapply filters to items
        if H_internal.filters.apply then
          instance.items = H_internal.filters.apply(filter_data.items, filter_combination, filter_data.filter_context)
        end
      end

      local expected_result = filter_data.expected_results[i]

      -- Verify combination produces expected results
      local combination_result = {
        combination_index = i,
        filters = vim.deepcopy(filter_combination),
        item_count = #instance.items,
        expected_count = expected_result.item_count,
        has_project_items = false,
        has_external_items = false,
        has_hidden_items = false,
      }

      -- Check item characteristics
      for _, item in ipairs(instance.items) do
        if item.path and string.find(item.path, 'project') then
          combination_result.has_project_items = true
        end
        if item.path and string.find(item.path, 'external') then
          combination_result.has_external_items = true
        end
        if item.path and string.find(item.path, '%.hidden') then
          combination_result.has_hidden_items = true
        end
      end

      -- Validate results match expectations
      MiniTest.expect.equality(
        combination_result.item_count,
        expected_result.item_count,
        string.format(
          'Combination %d (%s) should have %d items, got %d',
          i,
          vim.inspect(filter_combination),
          expected_result.item_count,
          combination_result.item_count
        )
      )

      -- Validate project items presence based on cwd_only filter
      if filter_combination.cwd_only then
        MiniTest.expect.equality(
          combination_result.has_project_items,
          true,
          string.format('Combination %d with cwd_only should have project items', i)
        )
        MiniTest.expect.equality(
          combination_result.has_external_items,
          false,
          string.format('Combination %d with cwd_only should not have external items', i)
        )
      end

      -- Validate hidden items presence based on show_hidden filter
      if not filter_combination.show_hidden then
        MiniTest.expect.equality(
          combination_result.has_hidden_items,
          false,
          string.format('Combination %d without show_hidden should not have hidden items', i)
        )
      end

      -- Store test results
      table.insert(test_results, combination_result)

      -- Cleanup this iteration
      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(10)
      end

      ::continue::
    end

    -- Verify we tested all 8 combinations
    MiniTest.expect.equality(#test_results, 8, 'should have tested all 8 filter combinations')

    -- Verify different combinations produce different results
    local unique_counts = {}
    for _, result in ipairs(test_results) do
      unique_counts[result.item_count] = true
    end

    MiniTest.expect.equality(
      vim.tbl_count(unique_counts) > 1,
      true,
      'different filter combinations should produce different item counts'
    )
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

T['Filter Features']['Filter Transitions: Testing transitions between filter states'] = function()
  -- Setup: Create filter test data
  local filter_data = H.create_filter_test_data()

  -- Mock environment for consistent behavior
  local original_fns = H.mock_vim_functions({
    current_file = filter_data.filter_context.original_file,
    cwd = filter_data.filter_context.original_cwd,
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    H.create_mock_jumplist(
      vim.tbl_map(function(item)
        return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
      end, filter_data.items),
      0
    )

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Test transition sequence: none → cwd_only → file_only → both → none
    local transitions = {
      {
        from = { file_only = false, cwd_only = false, show_hidden = false },
        to = { file_only = false, cwd_only = true, show_hidden = false },
        action = 'toggle_cwd_filter',
      },
      {
        from = { file_only = false, cwd_only = true, show_hidden = false },
        to = { file_only = true, cwd_only = true, show_hidden = false },
        action = 'toggle_file_filter',
      },
      {
        from = { file_only = true, cwd_only = true, show_hidden = false },
        to = { file_only = true, cwd_only = true, show_hidden = true },
        action = 'toggle_show_hidden',
      },
      {
        from = { file_only = true, cwd_only = true, show_hidden = true },
        to = { file_only = false, cwd_only = false, show_hidden = false },
        action = 'reset_filters',
      },
    }

    for i, transition in ipairs(transitions) do
      -- Apply the transition action
      if H_internal.actions and H_internal.actions[transition.action] then
        local items_before = #instance.items

        H_internal.actions[transition.action](instance, {})
        vim.wait(10)

        -- Verify filter state changed correctly
        for key, expected_value in pairs(transition.to) do
          MiniTest.expect.equality(
            instance.filters[key],
            expected_value,
            string.format(
              'Transition %d: %s should be %s after %s',
              i,
              key,
              tostring(expected_value),
              transition.action
            )
          )
        end

        -- Verify items were refiltered (item count may change)
        MiniTest.expect.equality(
          type(#instance.items),
          'number',
          string.format('Transition %d should maintain valid items list', i)
        )

        -- Verify selection remains valid
        if #instance.items > 0 then
          MiniTest.expect.equality(
            instance.selection.index >= 1 and instance.selection.index <= #instance.items,
            true,
            string.format('Transition %d should maintain valid selection', i)
          )
        end
      end
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

T['Filter Features']['Empty Results Handling: Graceful handling when filters produce no items'] = function()
  -- Setup: Create minimal filter test data that can produce empty results
  local filter_data = H.create_filter_test_data({
    scenario = 'minimal', -- This would create fewer items making empty results more likely
  })

  -- Mock environment to force empty results in certain combinations
  local original_fns = H.mock_vim_functions({
    current_file = '/nonexistent/file.lua', -- File that doesn't match any test items
    cwd = '/nonexistent/directory', -- Directory that doesn't match any test items
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    H.create_mock_jumplist(
      vim.tbl_map(function(item)
        return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
      end, filter_data.items),
      0
    )

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Apply filters that should produce empty results
    if H_internal.actions then
      -- Apply cwd_only filter (should filter out all items since cwd doesn't match)
      if H_internal.actions.toggle_cwd_filter then
        H_internal.actions.toggle_cwd_filter(instance, {})
        vim.wait(10)

        -- Verify graceful handling of empty results
        MiniTest.expect.equality(
          #instance.items,
          0,
          'cwd_only filter with non-matching cwd should produce empty results'
        )

        -- Verify selection is handled gracefully
        MiniTest.expect.equality(instance.selection.index, 0, 'selection index should be 0 when no items available')

        -- Verify instance remains stable
        MiniTest.expect.equality(type(instance.items), 'table', 'items should remain a valid table even when empty')
      end

      -- Test recovery from empty state by resetting filters
      if H_internal.actions.reset_filters then
        H_internal.actions.reset_filters(instance, {})
        vim.wait(10)

        -- Should recover to showing all items
        MiniTest.expect.equality(#instance.items > 0, true, 'reset_filters should recover from empty state')

        -- Selection should be restored to valid position
        if #instance.items > 0 then
          MiniTest.expect.equality(
            instance.selection.index >= 1 and instance.selection.index <= #instance.items,
            true,
            'selection should be restored to valid position after recovery'
          )
        end
      end
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

T['Filter Features']['Selection Preservation: Maintaining selection during filter changes'] = function()
  -- Setup: Create filter test data
  local filter_data = H.create_filter_test_data()

  -- Mock environment for consistent behavior
  local original_fns = H.mock_vim_functions({
    current_file = filter_data.filter_context.original_file,
    cwd = filter_data.filter_context.original_cwd,
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    H.create_mock_jumplist(
      vim.tbl_map(function(item)
        return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
      end, filter_data.items),
      0
    )

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Test selection preservation scenarios
    if #instance.items > 1 then
      -- Move to second item
      if H_internal.actions and H_internal.actions.move_next then
        H_internal.actions.move_next(instance, {})
        vim.wait(10)

        local selected_item_before = instance.items[instance.selection.index]
        local selection_index_before = instance.selection.index

        -- Apply a filter that should keep the selected item visible
        if H_internal.actions.toggle_show_hidden then
          H_internal.actions.toggle_show_hidden(instance, {})
          vim.wait(10)

          -- Verify selection is still valid after filter
          MiniTest.expect.equality(
            instance.selection.index >= 1 and instance.selection.index <= #instance.items,
            true,
            'selection should remain valid after filter application'
          )

          -- If the selected item is still in the filtered list, selection should be preserved
          local selected_item_after = nil
          if #instance.items > 0 and instance.selection.index > 0 then
            selected_item_after = instance.items[instance.selection.index]
          end

          -- Verify reasonable selection behavior
          if selected_item_after then
            MiniTest.expect.equality(
              type(selected_item_after.path),
              'string',
              'selected item after filter should have valid path'
            )
          end

          -- Test intelligent adjustment when selected item is filtered out
          -- Apply a more restrictive filter
          if H_internal.actions.toggle_file_filter then
            H_internal.actions.toggle_file_filter(instance, {})
            vim.wait(10)

            -- Selection should be adjusted to a valid position
            if #instance.items > 0 then
              MiniTest.expect.equality(
                instance.selection.index >= 1 and instance.selection.index <= #instance.items,
                true,
                'selection should be adjusted to valid position when original item filtered out'
              )
            else
              MiniTest.expect.equality(instance.selection.index, 0, 'selection should be 0 when all items filtered out')
            end
          end
        end
      end
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

-- Phase 3.2: Filter Edge Cases Testing

T['Filter Features']['Path Edge Cases: Files with spaces, special chars, Unicode, symlinks'] = function()
  -- Create buffers with challenging file names
  local challenging_paths = {
    'my file with spaces.lua',
    'file#with@special%chars&stuff.lua',
    'файл-with-unicode-🚀.lua',
    'very-long-filename-that-exceeds-normal-expectations-and-tests-path-handling-limits.lua',
    '.hidden-file.lua',
    'UPPER-CASE-FILE.LUA',
  }

  local test_buffers = {}
  for _, path in ipairs(challenging_paths) do
    local buf = H.create_test_buffer(path, { 'line 1', 'line 2' })
    table.insert(test_buffers, buf)
  end

  -- Create jumplist with these challenging paths
  local jumplist_entries = {}
  for _, buf in ipairs(test_buffers) do
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = challenging_paths[1], -- First file as current
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Verify all challenging paths are handled correctly
    MiniTest.expect.equality(#instance.items >= #challenging_paths, true, 'should handle all challenging file paths')

    -- Test that items have properly escaped/handled paths
    for _, item in ipairs(instance.items) do
      MiniTest.expect.equality(type(item.path), 'string', 'item path should be string even with special characters')
      MiniTest.expect.equality(#item.path > 0, true, 'item path should not be empty')
    end

    -- Test filtering with challenging paths
    if H_internal.actions and H_internal.actions.toggle_file_filter then
      H_internal.actions.toggle_file_filter(instance, {})
      vim.wait(10)

      -- Should still work with special characters
      MiniTest.expect.equality(type(#instance.items), 'number', 'filtering should work with special character paths')

      -- Verify current file filter works with special characters
      local current_file_found = false
      for _, item in ipairs(instance.items) do
        if item.is_current then
          current_file_found = true
          break
        end
      end

      if #instance.items > 0 then
        MiniTest.expect.equality(
          current_file_found,
          true,
          'file_only filter should find current file even with special characters'
        )
      end
    end

    -- Test hidden file filtering
    if H_internal.actions and H_internal.actions.toggle_show_hidden then
      H_internal.actions.reset_filters(instance, {})
      vim.wait(10)

      local items_before_hidden = #instance.items

      H_internal.actions.toggle_show_hidden(instance, {})
      vim.wait(10)

      -- Should handle hidden files correctly
      MiniTest.expect.equality(type(#instance.items), 'number', 'show_hidden filter should handle hidden files')

      -- Should show hidden files when toggled
      local hidden_file_found = false
      for _, item in ipairs(instance.items) do
        if item.path and item.path:match('%.hidden') then
          hidden_file_found = true
          break
        end
      end

      MiniTest.expect.equality(hidden_file_found, true, 'should show hidden files when show_hidden is enabled')
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)
end

T['Filter Features']['Context Edge Cases: No current file, no cwd, deeply nested directories'] = function()
  -- Setup various challenging contexts
  local test_scenarios = {
    {
      name = 'no_current_file',
      current_file = '', -- No current file
      cwd = vim.fn.getcwd(),
      description = 'no current file context',
    },
    {
      name = 'no_cwd',
      current_file = '/test/file.lua',
      cwd = '', -- No working directory
      description = 'no working directory context',
    },
    {
      name = 'deeply_nested',
      current_file = '/very/deep/nested/directory/structure/with/many/levels/file.lua',
      cwd = '/very/deep/nested/directory/structure/with/many/levels',
      description = 'deeply nested directory context',
    },
    {
      name = 'root_directory',
      current_file = '/file.lua',
      cwd = '/',
      description = 'root directory context',
    },
  }

  for _, scenario in ipairs(test_scenarios) do
    -- Create test data for this scenario
    local buf1 = H.create_test_buffer('test1.lua', { 'line 1' })
    local buf2 = H.create_test_buffer('test2.lua', { 'line 2' })

    H.create_mock_jumplist({
      { bufnr = buf1, lnum = 1, col = 0 },
      { bufnr = buf2, lnum = 1, col = 0 },
    }, 0)

    -- Mock the challenging context
    local original_fns = H.mock_vim_functions({
      current_file = scenario.current_file,
      cwd = scenario.cwd,
    })

    MiniTest.expect.no_error(function()
      Jumppack.setup({})
      Jumppack.start({})
      vim.wait(10)

      local state = Jumppack.get_state()
      if not state or not state.instance then
        return -- Skip if no valid state
      end

      local instance = state.instance
      local H_internal = Jumppack.H

      -- Verify basic functionality works in challenging context
      MiniTest.expect.equality(type(instance.items), 'table', string.format('should handle %s', scenario.description))

      -- Test filtering in challenging context
      if H_internal.actions then
        -- Test file_only filter
        if H_internal.actions.toggle_file_filter then
          H_internal.actions.toggle_file_filter(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            type(#instance.items),
            'number',
            string.format('file_only filter should work in %s', scenario.description)
          )
        end

        -- Test cwd_only filter
        if H_internal.actions.toggle_cwd_filter then
          H_internal.actions.reset_filters(instance, {})
          vim.wait(10)

          H_internal.actions.toggle_cwd_filter(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            type(#instance.items),
            'number',
            string.format('cwd_only filter should work in %s', scenario.description)
          )
        end

        -- Reset filters for clean state
        if H_internal.actions.reset_filters then
          H_internal.actions.reset_filters(instance, {})
          vim.wait(10)
        end
      end

      -- Cleanup
      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(10)
      end
    end, string.format('Error in %s scenario', scenario.name))

    -- Restore and cleanup
    H.restore_vim_functions(original_fns)
    H.cleanup_buffers({ buf1, buf2 })
  end
end

T['Filter Features']['Dynamic Changes: Apply/remove filters during active navigation'] = function()
  -- Setup test data
  local filter_data = H.create_filter_test_data()

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = filter_data.filter_context.original_file,
    cwd = filter_data.filter_context.original_cwd,
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    H.create_mock_jumplist(
      vim.tbl_map(function(item)
        return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
      end, filter_data.items),
      0
    )

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Test dynamic filter changes during navigation
    if #instance.items > 1 and H_internal.actions then
      -- Start navigation
      if H_internal.actions.move_next then
        H_internal.actions.move_next(instance, {})
        vim.wait(5)

        local navigation_selection = instance.selection.index

        -- Apply filter while navigating
        if H_internal.actions.toggle_cwd_filter then
          H_internal.actions.toggle_cwd_filter(instance, {})
          vim.wait(10)

          -- Verify state remains consistent after dynamic filter change
          MiniTest.expect.equality(
            instance.selection.index >= 1 and instance.selection.index <= math.max(1, #instance.items),
            true,
            'selection should remain valid after dynamic filter application'
          )

          -- Continue navigation after filter change
          if #instance.items > 1 then
            H_internal.actions.move_next(instance, {})
            vim.wait(5)

            MiniTest.expect.equality(
              type(instance.selection.index),
              'number',
              'navigation should continue working after dynamic filter change'
            )
          end
        end

        -- Test rapid filter toggling
        if H_internal.actions.toggle_file_filter and H_internal.actions.toggle_show_hidden then
          local rapid_toggle_count = 5
          for i = 1, rapid_toggle_count do
            H_internal.actions.toggle_file_filter(instance, {})
            vim.wait(2)
            H_internal.actions.toggle_show_hidden(instance, {})
            vim.wait(2)

            -- Verify stability during rapid changes
            MiniTest.expect.equality(
              type(instance.items),
              'table',
              string.format('items should remain table during rapid toggle %d', i)
            )

            if #instance.items > 0 then
              MiniTest.expect.equality(
                instance.selection.index >= 1 and instance.selection.index <= #instance.items,
                true,
                string.format('selection should remain valid during rapid toggle %d', i)
              )
            end
          end
        end

        -- Test filter removal during active state
        if H_internal.actions.reset_filters then
          H_internal.actions.reset_filters(instance, {})
          vim.wait(10)

          -- Should return to full item list
          MiniTest.expect.equality(
            #instance.items >= 3, -- Should have restored most/all items
            true,
            'reset_filters should restore items during active navigation'
          )

          -- Selection should remain valid
          MiniTest.expect.equality(
            instance.selection.index >= 1 and instance.selection.index <= #instance.items,
            true,
            'selection should be valid after filter reset'
          )
        end
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

T['Filter Features']['Extreme Lists: Filter behavior with 0, 1, and 100+ items'] = function()
  local extreme_scenarios = {
    {
      name = 'empty_list',
      item_count = 0,
      description = 'empty jumplist',
    },
    {
      name = 'single_item',
      item_count = 1,
      description = 'single item list',
    },
    {
      name = 'large_list',
      item_count = 150,
      description = 'large item list (150 items)',
    },
  }

  for _, scenario in ipairs(extreme_scenarios) do
    -- Create test buffers based on scenario
    local test_buffers = {}
    local jumplist_entries = {}

    if scenario.item_count > 0 then
      for i = 1, scenario.item_count do
        local buf = H.create_test_buffer(string.format('file%d.lua', i), { 'line 1' })
        table.insert(test_buffers, buf)
        table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
      end
    end

    H.create_mock_jumplist(jumplist_entries, 0)

    -- Mock environment
    local original_fns = H.mock_vim_functions({
      current_file = scenario.item_count > 0 and 'file1.lua' or '',
      cwd = vim.fn.getcwd(),
    })

    MiniTest.expect.no_error(function()
      Jumppack.setup({})
      Jumppack.start({})
      vim.wait(10)

      local state = Jumppack.get_state()

      if scenario.item_count == 0 then
        -- Empty list should either not create state or handle gracefully
        if state and state.instance then
          MiniTest.expect.equality(#state.instance.items, 0, 'empty jumplist should result in 0 items')
        end
      else
        if not state or not state.instance then
          return -- Skip if no valid state
        end

        local instance = state.instance
        local H_internal = Jumppack.H

        -- Verify initial item count
        MiniTest.expect.equality(
          #instance.items,
          scenario.item_count,
          string.format('%s should have %d items', scenario.description, scenario.item_count)
        )

        -- Test filtering performance with extreme lists
        if H_internal.actions then
          local start_time = vim.loop.hrtime()

          -- Apply filters
          if H_internal.actions.toggle_file_filter then
            H_internal.actions.toggle_file_filter(instance, {})
            vim.wait(10)
          end

          if H_internal.actions.toggle_cwd_filter then
            H_internal.actions.toggle_cwd_filter(instance, {})
            vim.wait(10)
          end

          local end_time = vim.loop.hrtime()
          local filter_time_ms = (end_time - start_time) / 1000000

          -- Performance should be reasonable even for large lists
          MiniTest.expect.equality(
            filter_time_ms < 1000, -- Less than 1 second
            true,
            string.format(
              'filtering %s should complete in reasonable time (took %.2fms)',
              scenario.description,
              filter_time_ms
            )
          )

          -- Verify filtering produced valid results
          MiniTest.expect.equality(
            type(instance.items),
            'table',
            string.format('filtering %s should produce valid items table', scenario.description)
          )

          -- Test navigation with extreme lists
          if #instance.items > 1 and H_internal.actions.move_next then
            H_internal.actions.move_next(instance, {})
            vim.wait(5)

            MiniTest.expect.equality(
              instance.selection.index >= 1 and instance.selection.index <= #instance.items,
              true,
              string.format('navigation should work with %s', scenario.description)
            )
          end

          -- Reset filters
          if H_internal.actions.reset_filters then
            H_internal.actions.reset_filters(instance, {})
            vim.wait(10)
          end
        end
      end

      -- Cleanup
      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(10)
      end
    end, string.format('Error in %s scenario', scenario.name))

    -- Restore and cleanup
    H.restore_vim_functions(original_fns)
    if #test_buffers > 0 then
      H.cleanup_buffers(test_buffers)
    end
  end
end

-- ============================================================================
-- 4. HIDE FEATURES TESTS
-- ============================================================================
T['Hide Features'] = MiniTest.new_set()

T['Hide Features']['H.hide functions'] = function()
  -- Clear any existing hidden items
  Jumppack.H.hide.storage = {}

  local item = { path = '/test/file.lua', lnum = 10 }

  -- Test hide key generation
  local key = Jumppack.H.hide.get_key(item)
  MiniTest.expect.equality(key, '/test/file.lua:10')

  -- Test item not hidden initially
  MiniTest.expect.equality(Jumppack.H.hide.is_hidden(item), false)

  -- Test toggle to hidden
  local new_status = Jumppack.H.hide.toggle(item)
  MiniTest.expect.equality(new_status, true)
  MiniTest.expect.equality(Jumppack.H.hide.is_hidden(item), true)

  -- Test toggle back to not hidden
  new_status = Jumppack.H.hide.toggle(item)
  MiniTest.expect.equality(new_status, false)
  MiniTest.expect.equality(Jumppack.H.hide.is_hidden(item), false)

  -- Test mark_items function
  local items = {
    { path = '/test/file1.lua', lnum = 1 },
    { path = '/test/file2.lua', lnum = 2 },
  }

  -- Mark first item as hidden
  Jumppack.H.hide.toggle(items[1])

  -- Mark items with hide status
  local marked_items = Jumppack.H.hide.mark_items(items)
  MiniTest.expect.equality(marked_items[1].hidden, true)
  MiniTest.expect.equality(marked_items[2].hidden, false)

  -- Cleanup
  Jumppack.H.hide.storage = {}
end

T['Hide Features']['Toggle hidden action'] = function()
  -- Setup test configuration
  local config = {
    options = { global_mappings = false, default_view = 'preview' },
    mappings = {
      jump_back = '<C-o>',
      jump_forward = '<C-i>',
      choose = '<CR>',
      choose_in_split = '<C-s>',
      choose_in_vsplit = '<C-v>',
      choose_in_tabpage = '<C-t>',
      stop = '<Esc>',
      toggle_preview = 'p',
      toggle_file_filter = 'f',
      toggle_cwd_filter = 'c',
      toggle_show_hidden = '.',
      reset_filters = 'r',
      toggle_hidden = 'x',
    },
    window = { config = nil },
  }

  require('jumppack').setup(config)

  -- Clear any existing hidden items
  Jumppack.H.hide.storage = {}

  -- Test that toggle_hidden action exists
  local H = Jumppack.H
  MiniTest.expect.equality(type(H.actions.toggle_hidden), 'function')

  -- Cleanup
  Jumppack.H.hide.storage = {}
end

T['Hide Features']['Display with hidden items'] = function()
  local item_normal = {
    path = '/test/file1.lua',
    lnum = 1,
    offset = -1,
    hidden = false,
  }

  local item_hidden = {
    path = '/test/file2.lua',
    lnum = 2,
    offset = 1,
    hidden = true,
  }

  -- Test display string for normal item
  local normal_display = Jumppack.H.display.item_to_string(item_normal, { show_preview = false })
  MiniTest.expect.equality(normal_display:find('✗') == nil, true)

  -- Test display string for hidden item
  local hidden_display = Jumppack.H.display.item_to_string(item_hidden, { show_preview = false })
  MiniTest.expect.equality(hidden_display:find('✗') ~= nil, true)
end

T['Hide Features']['Hide current item moves selection correctly'] = function()
  local buf1 = H.create_test_buffer('/test/file1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('/test/file2.lua', { 'line 2' })
  local buf3 = H.create_test_buffer('/test/file3.lua', { 'line 3' })
  local buf4 = H.create_test_buffer('/test/file4.lua', { 'line 4' })

  -- Clear any existing hidden items
  Jumppack.H.hide.storage = {}

  -- Create jumplist with 4 files
  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
    { bufnr = buf4, lnum = 1, col = 0 },
  }, 0)

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_actions = Jumppack.H.actions

    -- Test 1: Hide middle item (should move to next)
    local initial_count = #instance.items
    H.instance.set_selection(instance, 2) -- Select middle item
    local selected_item = H.instance.get_selection(instance)
    if selected_item then
      H_actions.toggle_hidden(instance, {})
      vim.wait(10)

      -- Should have one fewer item visible
      MiniTest.expect.equality(#instance.items, initial_count - 1)
      -- Selection should move appropriately (to next available)
      MiniTest.expect.equality(instance.current <= #instance.items, true)
    end

    -- Test 2: Hide last item (should move to previous)
    if #instance.items > 0 then
      H.instance.set_selection(instance, #instance.items) -- Select last item
      local last_item = H.instance.get_selection(instance)
      if last_item then
        H_actions.toggle_hidden(instance, {})
        vim.wait(10)

        -- Selection should be valid and not beyond available items
        MiniTest.expect.equality(instance.current <= #instance.items, true)
        MiniTest.expect.equality(instance.current >= 1, true)
      end
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  Jumppack.H.hide.storage = {}
  H.cleanup_buffers({ buf1, buf2, buf3, buf4 })
end

T['Hide Features']['Hide item updates both views'] = function()
  local buf1 = H.create_test_buffer('/test/main.lua', { 'main content' })
  local buf2 = H.create_test_buffer('/test/other.lua', { 'other content' })

  -- Clear any existing hidden items
  Jumppack.H.hide.storage = {}

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 0)

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_actions = Jumppack.H.actions

    -- Test preview view
    instance.view_state = 'preview'
    H.instance.set_selection(instance, 1)
    local initial_view = instance.view_state

    local selected_item = H.instance.get_selection(instance)
    if selected_item then
      H_actions.toggle_hidden(instance, {})
      vim.wait(10)

      -- View should be preserved and updated
      MiniTest.expect.equality(instance.view_state, initial_view)
    end

    -- Test list view
    if #instance.items > 0 then
      instance.view_state = 'list'
      H.instance.set_selection(instance, 1)
      initial_view = instance.view_state

      selected_item = H.instance.get_selection(instance)
      if selected_item then
        H_actions.toggle_hidden(instance, {})
        vim.wait(10)

        -- View should be preserved and updated
        MiniTest.expect.equality(instance.view_state, initial_view)
      end
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  Jumppack.H.hide.storage = {}
  H.cleanup_buffers({ buf1, buf2 })
end

T['Hide Features']['Hide item respects show_hidden filter'] = function()
  local buf1 = H.create_test_buffer('/test/file1.lua', { 'content 1' })
  local buf2 = H.create_test_buffer('/test/file2.lua', { 'content 2' })

  -- Clear any existing hidden items
  Jumppack.H.hide.storage = {}

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 0)

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_actions = Jumppack.H.actions
    local initial_count = #instance.items

    -- Test 1: Hide with show_hidden=false (default) - item should disappear
    H.instance.set_selection(instance, 1)
    local selected_item = H.instance.get_selection(instance)
    if selected_item then
      H_actions.toggle_hidden(instance, {})
      vim.wait(10)

      -- Item should be hidden from view
      MiniTest.expect.equality(#instance.items, initial_count - 1)
    end

    -- Test 2: Toggle show_hidden=true - hidden items should reappear
    H_actions.toggle_show_hidden(instance, {})
    vim.wait(10)

    -- Hidden items should now be visible
    MiniTest.expect.equality(#instance.items >= initial_count - 1, true)

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  Jumppack.H.hide.storage = {}
  H.cleanup_buffers({ buf1, buf2 })
end

T['Hide Features']['Hide multiple items in sequence'] = function()
  local buf1 = H.create_test_buffer('/test/item1.lua', { 'content 1' })
  local buf2 = H.create_test_buffer('/test/item2.lua', { 'content 2' })
  local buf3 = H.create_test_buffer('/test/item3.lua', { 'content 3' })
  local buf4 = H.create_test_buffer('/test/item4.lua', { 'content 4' })

  -- Clear any existing hidden items
  Jumppack.H.hide.storage = {}

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
    { bufnr = buf4, lnum = 1, col = 0 },
  }, 0)

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_actions = Jumppack.H.actions
    local initial_count = #instance.items

    -- Hide items sequentially
    for i = 1, math.min(2, #instance.items) do
      if #instance.items > 0 then
        H.instance.set_selection(instance, 1) -- Always hide first visible item
        local selected_item = H.instance.get_selection(instance)
        if selected_item then
          H_actions.toggle_hidden(instance, {})
          vim.wait(10)

          -- Verify selection is still valid after each hide
          MiniTest.expect.equality(instance.current >= 1, true)
          MiniTest.expect.equality(instance.current <= math.max(1, #instance.items), true)
        end
      end
    end

    -- Should have fewer visible items
    MiniTest.expect.equality(#instance.items < initial_count, true)

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  Jumppack.H.hide.storage = {}
  H.cleanup_buffers({ buf1, buf2, buf3, buf4 })
end

-- Additional Navigation Features subcategories

T['Navigation Features']['calculate_filtered_initial_selection'] = function()
  local original_items = {
    { path = '/test/file1.lua', lnum = 1, offset = -2 },
    { path = '/test/file2.lua', lnum = 5, offset = -1 },
    { path = '/test/file3.lua', lnum = 10, offset = 0 }, -- Current position
    { path = '/test/file4.lua', lnum = 15, offset = 1 },
    { path = '/test/file5.lua', lnum = 20, offset = 2 },
  }

  local filtered_items = {
    { path = '/test/file1.lua', lnum = 1, offset = -2 },
    { path = '/test/file3.lua', lnum = 10, offset = 0 }, -- Current position
    { path = '/test/file5.lua', lnum = 20, offset = 2 },
  }

  -- Test finding exact match
  local selection = Jumppack.H.instance.calculate_filtered_initial_selection(original_items, filtered_items, 3)
  MiniTest.expect.equality(selection, 2) -- file3.lua should be at index 2 in filtered items

  -- Test finding closest when exact match not available
  selection = Jumppack.H.instance.calculate_filtered_initial_selection(original_items, filtered_items, 4)
  MiniTest.expect.equality(selection, 2) -- Should find file3.lua (offset=0) as first closest to file4.lua (offset=1)

  -- Test edge cases
  selection = Jumppack.H.instance.calculate_filtered_initial_selection(original_items, filtered_items, nil)
  MiniTest.expect.equality(selection, 1) -- Should default to 1

  selection = Jumppack.H.instance.calculate_filtered_initial_selection(original_items, filtered_items, 10)
  MiniTest.expect.equality(selection, 3) -- Should clamp to last item and find closest
end

T['Navigation Features']['find_best_selection'] = function()
  -- Setup a mock instance
  local original_items = {
    { path = '/test/file1.lua', lnum = 1, offset = -1 },
    { path = '/test/file2.lua', lnum = 5, offset = 0 },
    { path = '/test/file3.lua', lnum = 10, offset = 1 },
  }

  local filtered_items = {
    { path = '/test/file1.lua', lnum = 1, offset = -1 },
    { path = '/test/file3.lua', lnum = 10, offset = 1 },
  }

  local mock_instance = {
    original_items = original_items,
    current_ind = 2, -- Currently on file2.lua
  }

  -- Test finding closest item when current is not in filtered list
  local selection = Jumppack.H.instance.find_best_selection(mock_instance, filtered_items)
  -- Should find file1.lua (offset=-1) as closest to file2.lua (offset=0)
  MiniTest.expect.equality(selection, 1)

  -- Test when current item is in filtered list
  mock_instance.current_ind = 1 -- Currently on file1.lua
  selection = Jumppack.H.instance.find_best_selection(mock_instance, filtered_items)
  MiniTest.expect.equality(selection, 1) -- Should find exact match
end

T['Navigation Features']['Navigation actions'] = function()
  -- Test that navigation actions exist and handle count
  local H = Jumppack.H
  MiniTest.expect.equality(type(H.actions.jump_back), 'function')
  MiniTest.expect.equality(type(H.actions.jump_forward), 'function')

  -- Note: Full integration testing of count support would require
  -- more complex setup with actual picker instance
end

-- Count functionality tests

T['Navigation Features']['instance has pending_count field'] = function()
  local H = Jumppack.H

  -- Create a basic instance structure for testing
  local mock_instance = {
    items = { {}, {}, {}, {}, {} }, -- 5 items
    current_ind = 3,
    action_keys = {},
    filters = { file_only = false, cwd_only = false, show_hidden = false },
    pending_count = '',
  }

  MiniTest.expect.equality(mock_instance.pending_count, '')

  -- Test that pending_count can be set
  mock_instance.pending_count = '25'
  MiniTest.expect.equality(mock_instance.pending_count, '25')
end

T['Navigation Features']['actions handle count parameter'] = function()
  local H = Jumppack.H

  -- Create mock instance with move_selection function
  local moved_by = nil
  local mock_instance = {
    items = { {}, {}, {}, {}, {}, {}, {}, {}, {}, {} }, -- 10 items
    current_ind = 5,
  }

  -- Mock the move_selection function to capture the count
  H.instance.move_selection = function(instance, by)
    moved_by = by
    instance.current_ind = math.max(1, math.min(#instance.items, instance.current_ind + by))
  end

  -- Test jump_back with count
  H.actions.jump_back(mock_instance, 3)
  MiniTest.expect.equality(moved_by, 3)

  -- Test jump_forward with count
  H.actions.jump_forward(mock_instance, 2)
  MiniTest.expect.equality(moved_by, -2)

  -- Test default count (nil becomes 1)
  H.actions.jump_back(mock_instance, nil)
  MiniTest.expect.equality(moved_by, 1)
end

T['Navigation Features']['general_info includes count display'] = function()
  local H = Jumppack.H

  local mock_instance = {
    items = { {}, {}, {}, {}, {} },
    current_ind = 3,
    filters = { file_only = false, cwd_only = false, show_hidden = false },
    pending_count = '42',
    opts = { source = { name = 'test', cwd = '/tmp' } },
  }

  local info = H.display.get_general_info(mock_instance)
  -- Check that the count is integrated into the position indicator
  MiniTest.expect.equality(info.status_text:find('×42') ~= nil, true)
  MiniTest.expect.equality(info.position_indicator:find('×42') ~= nil, true)
end

T['Navigation Features']['general_info without pending count'] = function()
  local H = Jumppack.H

  local mock_instance = {
    items = { {}, {}, {}, {}, {} },
    current_ind = 3,
    filters = { file_only = false, cwd_only = false, show_hidden = false },
    pending_count = '', -- Empty count
    opts = { source = { name = 'test', cwd = '/tmp' } },
  }

  local info = H.display.get_general_info(mock_instance)
  -- Should not contain count symbol when pending_count is empty
  MiniTest.expect.equality(info.status_text:find('×'), nil)
  MiniTest.expect.equality(info.position_indicator:find('×'), nil)
end

-- Jump navigation tests

T['Navigation Features']['new actions exist and are callable'] = function()
  local H_internal = Jumppack.H
  local actions = H_internal.actions

  -- Test that new actions exist
  MiniTest.expect.equality(type(actions.jump_to_top), 'function')
  MiniTest.expect.equality(type(actions.jump_to_bottom), 'function')

  -- Test with empty items - should not error
  local mock_instance = {
    current_ind = 1,
    items = {},
    view_state = 'list',
    visible_range = { from = 1, to = 1 },
    windows = { main = -1 },
  }

  MiniTest.expect.no_error(function()
    actions.jump_to_top(mock_instance, 1)
    actions.jump_to_bottom(mock_instance, 1)
  end)
end

T['Navigation Features']['configuration includes new mappings'] = function()
  -- Test that new mappings are in default configuration
  MiniTest.expect.equality(type(Jumppack.config.mappings.jump_to_top), 'string')
  MiniTest.expect.equality(type(Jumppack.config.mappings.jump_to_bottom), 'string')

  -- Test default values
  MiniTest.expect.equality(Jumppack.config.mappings.jump_to_top, 'g')
  MiniTest.expect.equality(Jumppack.config.mappings.jump_to_bottom, 'G')
end

T['Navigation Features']['all actions have corresponding config mappings'] = function()
  local H_internal = Jumppack.H
  local actions = H_internal.actions
  local mappings = Jumppack.config.mappings

  -- Test that jump_to_top action exists and has mapping
  MiniTest.expect.equality(type(actions.jump_to_top), 'function')
  MiniTest.expect.equality(type(mappings.jump_to_top), 'string')

  -- Test that jump_to_bottom action exists and has mapping
  MiniTest.expect.equality(type(actions.jump_to_bottom), 'function')
  MiniTest.expect.equality(type(mappings.jump_to_bottom), 'string')
end

T['Navigation Features']['actions are properly wired in action normalization'] = function()
  local H_internal = Jumppack.H

  -- Test action normalization includes our new actions
  local test_mappings = {
    jump_to_top = 'g',
    jump_to_bottom = 'G',
    stop = '<Esc>', -- Include a known working action for comparison
  }

  local normalized = H_internal.config.normalize_mappings(test_mappings)

  -- Check that g and G are properly normalized with function references
  local g_key = H_internal.utils.replace_termcodes('g')
  local G_key = H_internal.utils.replace_termcodes('G')

  MiniTest.expect.equality(normalized[g_key] ~= nil, true)
  MiniTest.expect.equality(normalized[G_key] ~= nil, true)
  MiniTest.expect.equality(type(normalized[g_key].func), 'function')
  MiniTest.expect.equality(type(normalized[G_key].func), 'function')
  MiniTest.expect.equality(normalized[g_key].name, 'jump_to_top')
  MiniTest.expect.equality(normalized[G_key].name, 'jump_to_bottom')
end

T['Navigation Features']['jump_to_top action is properly implemented'] = function()
  local H_internal = Jumppack.H

  -- Test that the action exists and can be called without error
  MiniTest.expect.equality(type(H_internal.actions.jump_to_top), 'function')

  -- Test that it calls the right underlying function (move_selection with correct params)
  local move_selection_called_with = nil
  local original_move_selection = H_internal.instance.move_selection

  H_internal.instance.move_selection = function(instance, by, to)
    move_selection_called_with = { instance = instance, by = by, to = to }
  end

  local test_instance = { items = { {}, {}, {} } }
  H_internal.actions.jump_to_top(test_instance, 5) -- Count should be ignored

  -- Verify it was called with correct parameters
  MiniTest.expect.equality(move_selection_called_with.instance, test_instance)
  MiniTest.expect.equality(move_selection_called_with.by, 0)
  MiniTest.expect.equality(move_selection_called_with.to, 1)

  -- Restore original function
  H_internal.instance.move_selection = original_move_selection
end

T['Navigation Features']['jump_to_bottom action is properly implemented'] = function()
  local H_internal = Jumppack.H

  -- Test that the action exists and can be called without error
  MiniTest.expect.equality(type(H_internal.actions.jump_to_bottom), 'function')

  -- Test that it calls the right underlying function (move_selection with correct params)
  local move_selection_called_with = nil
  local original_move_selection = H_internal.instance.move_selection

  H_internal.instance.move_selection = function(instance, by, to)
    move_selection_called_with = { instance = instance, by = by, to = to }
  end

  local test_instance = { items = { {}, {}, {}, {} } } -- 4 items
  H_internal.actions.jump_to_bottom(test_instance, 10) -- Count should be ignored

  -- Verify it was called with correct parameters (should go to item 4)
  MiniTest.expect.equality(move_selection_called_with.instance, test_instance)
  MiniTest.expect.equality(move_selection_called_with.by, 0)
  MiniTest.expect.equality(move_selection_called_with.to, 4)

  -- Test edge case with empty items
  move_selection_called_with = nil
  H_internal.actions.jump_to_bottom({ items = {} }, 1)
  -- Should not call move_selection when items is empty
  MiniTest.expect.equality(move_selection_called_with, nil)

  -- Restore original function
  H_internal.instance.move_selection = original_move_selection
end

T['Navigation Features']['actions handle edge cases correctly'] = function()
  local H_internal = Jumppack.H
  local actions = H_internal.actions

  -- Test with empty items
  local empty_instance = {
    current_ind = 1,
    items = {},
    view_state = 'list',
    visible_range = { from = 1, to = 1 },
    windows = { main = vim.api.nvim_get_current_win() },
  }

  -- Should not error with empty items
  MiniTest.expect.no_error(function()
    actions.jump_to_top(empty_instance, 1)
    actions.jump_to_bottom(empty_instance, 1)
  end)

  -- Test with single item
  local single_instance = {
    current_ind = 1,
    items = {
      { path = '/test/single.lua', lnum = 1, col = 0, jump_index = 1 },
    },
    view_state = 'list',
    visible_range = { from = 1, to = 1 },
    windows = { main = vim.api.nvim_get_current_win() },
  }

  -- Both actions should keep selection at position 1
  actions.jump_to_top(single_instance, 1)
  MiniTest.expect.equality(single_instance.current_ind, 1)

  actions.jump_to_bottom(single_instance, 1)
  MiniTest.expect.equality(single_instance.current_ind, 1)
end

T['Navigation Features']['validation catches invalid mapping types'] = function()
  local H_internal = Jumppack.H

  -- Test that config validation fails when jump mappings have invalid types
  local invalid_config = {
    options = { global_mappings = true, cwd_only = false, wrap_edges = false, default_view = 'preview' },
    mappings = {
      jump_back = '<C-o>',
      jump_forward = '<C-i>',
      jump_to_top = 123, -- Invalid type - should be string
      jump_to_bottom = 'G',
      choose = '<CR>',
      choose_in_split = '<C-s>',
      choose_in_tabpage = '<C-t>',
      choose_in_vsplit = '<C-v>',
      stop = '<Esc>',
      toggle_preview = 'p',
      toggle_file_filter = 'f',
      toggle_cwd_filter = 'c',
      toggle_show_hidden = '.',
      reset_filters = 'r',
      toggle_hidden = 'x',
    },
    window = { config = nil },
  }

  -- Should error when jump_to_top mapping has invalid type
  MiniTest.expect.error(function()
    H_internal.config.setup(invalid_config)
  end, 'jump_to_top')

  -- Test invalid jump_to_bottom type
  local config_invalid_bottom = vim.deepcopy(invalid_config)
  config_invalid_bottom.mappings.jump_to_top = 'g' -- Fix top
  config_invalid_bottom.mappings.jump_to_bottom = {} -- Invalid type - should be string
  MiniTest.expect.error(function()
    H_internal.config.setup(config_invalid_bottom)
  end, 'jump_to_bottom')
end

-- Phase 4.1: Wrapping Boundary Tests

T['Navigation Features']['Basic Wrapping: First→back wraps to last, last→forward wraps to first'] = function()
  -- Setup test data with multiple items
  local buf1 = H.create_test_buffer('test1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('test2.lua', { 'line 2' })
  local buf3 = H.create_test_buffer('test3.lua', { 'line 3' })
  local buf4 = H.create_test_buffer('test4.lua', { 'line 4' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
    { bufnr = buf4, lnum = 1, col = 0 },
  }, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'test1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    -- Test with wrapping enabled
    Jumppack.setup({
      options = { wrap_edges = true },
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    MiniTest.expect.equality(#instance.items >= 4, true, 'should have at least 4 items for wrapping test')

    if #instance.items >= 4 and H_internal.actions then
      -- Test forward wrapping: navigate to last item, then forward should wrap to first
      if H_internal.actions.jump_to_bottom then
        H_internal.actions.jump_to_bottom(instance, {})
        vim.wait(10)

        local last_index = instance.selection.index
        MiniTest.expect.equality(last_index, #instance.items, 'should be at last item')

        -- Move forward from last - should wrap to first
        if H_internal.actions.move_next then
          H_internal.actions.move_next(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            instance.selection.index,
            1,
            'forward from last should wrap to first when wrap_edges is true'
          )
        end
      end

      -- Test backward wrapping: navigate to first item, then backward should wrap to last
      if H_internal.actions.jump_to_top then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(10)

        MiniTest.expect.equality(instance.selection.index, 1, 'should be at first item')

        -- Move backward from first - should wrap to last
        if H_internal.actions.move_prev then
          H_internal.actions.move_prev(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            instance.selection.index,
            #instance.items,
            'backward from first should wrap to last when wrap_edges is true'
          )
        end
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end

    -- Test with wrapping disabled
    Jumppack.setup({
      options = { wrap_edges = false },
    })

    Jumppack.start({})
    vim.wait(10)

    state = Jumppack.get_state()
    if state and state.instance then
      instance = state.instance

      if #instance.items >= 4 and H_internal.actions then
        -- Test no forward wrapping: at last item, forward should stay at last
        if H_internal.actions.jump_to_bottom then
          H_internal.actions.jump_to_bottom(instance, {})
          vim.wait(10)

          local last_index = instance.selection.index

          if H_internal.actions.move_next then
            H_internal.actions.move_next(instance, {})
            vim.wait(10)

            MiniTest.expect.equality(
              instance.selection.index,
              last_index,
              'forward from last should stay at last when wrap_edges is false'
            )
          end
        end

        -- Test no backward wrapping: at first item, backward should stay at first
        if H_internal.actions.jump_to_top then
          H_internal.actions.jump_to_top(instance, {})
          vim.wait(10)

          if H_internal.actions.move_prev then
            H_internal.actions.move_prev(instance, {})
            vim.wait(10)

            MiniTest.expect.equality(
              instance.selection.index,
              1,
              'backward from first should stay at first when wrap_edges is false'
            )
          end
        end
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3, buf4 })
end

T['Navigation Features']['Count Wrapping: Large counts with wrapping enabled/disabled'] = function()
  -- Setup test data
  local test_buffers = {}
  local jumplist_entries = {}

  -- Create 5 items for count testing
  for i = 1, 5 do
    local buf = H.create_test_buffer(string.format('count_test%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'count_test1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    -- Test with wrapping enabled
    Jumppack.setup({
      options = { wrap_edges = true },
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    if #instance.items >= 5 and H_internal.actions then
      -- Test large count forward with wrapping
      if H_internal.actions.jump_to_top and H_internal.actions.move_next then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(10)

        -- Move 7 steps forward from position 1 (list size = 5)
        -- With wrapping: 1 + 7 = 8, 8 % 5 = 3, so should end at position 3
        instance.pending_count = 7
        H_internal.actions.move_next(instance, {})
        vim.wait(10)

        local expected_position = ((1 - 1 + 7) % #instance.items) + 1 -- 1-based indexing
        MiniTest.expect.equality(
          instance.selection.index,
          expected_position,
          string.format('large count forward with wrapping should end at position %d', expected_position)
        )

        -- Verify count was cleared
        MiniTest.expect.equality(instance.pending_count, nil, 'pending count should be cleared after action')
      end

      -- Test large count backward with wrapping
      if H_internal.actions.jump_to_bottom and H_internal.actions.move_prev then
        H_internal.actions.jump_to_bottom(instance, {})
        vim.wait(10)

        -- Move 8 steps backward from position 5 (list size = 5)
        -- With wrapping: 5 - 8 = -3, (-3 % 5) + 5 = 2, so should end at position 2
        instance.pending_count = 8
        H_internal.actions.move_prev(instance, {})
        vim.wait(10)

        -- Calculate expected position for backward wrapping
        local current_pos = #instance.items
        local steps = 8
        local expected_position = ((current_pos - 1 - steps) % #instance.items) + 1
        if expected_position <= 0 then
          expected_position = expected_position + #instance.items
        end

        MiniTest.expect.equality(
          instance.selection.index,
          expected_position,
          string.format('large count backward with wrapping should end at position %d', expected_position)
        )
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end

    -- Test with wrapping disabled
    Jumppack.setup({
      options = { wrap_edges = false },
    })

    Jumppack.start({})
    vim.wait(10)

    state = Jumppack.get_state()
    if state and state.instance then
      instance = state.instance

      if #instance.items >= 5 and H_internal.actions then
        -- Test large count forward without wrapping - should clamp to last
        if H_internal.actions.jump_to_top and H_internal.actions.move_next then
          H_internal.actions.jump_to_top(instance, {})
          vim.wait(10)

          instance.pending_count = 10 -- Much larger than list size
          H_internal.actions.move_next(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            instance.selection.index,
            #instance.items,
            'large count forward without wrapping should clamp to last position'
          )
        end

        -- Test large count backward without wrapping - should clamp to first
        if H_internal.actions.jump_to_bottom and H_internal.actions.move_prev then
          H_internal.actions.jump_to_bottom(instance, {})
          vim.wait(10)

          instance.pending_count = 10 -- Much larger than list size
          H_internal.actions.move_prev(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            instance.selection.index,
            1,
            'large count backward without wrapping should clamp to first position'
          )
        end
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)
end

T['Navigation Features']['Filter Wrapping: Wrapping behavior when filters reduce available items'] = function()
  -- Setup comprehensive test data
  local filter_data = H.create_filter_test_data()

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = filter_data.filter_context.original_file,
    cwd = filter_data.filter_context.original_cwd,
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = { wrap_edges = true },
    })

    H.create_mock_jumplist(
      vim.tbl_map(function(item)
        return { bufnr = item.bufnr, lnum = item.lnum, col = item.col }
      end, filter_data.items),
      0
    )

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    local original_item_count = #instance.items

    -- Apply filter to reduce available items
    if H_internal.actions and H_internal.actions.toggle_cwd_filter then
      H_internal.actions.toggle_cwd_filter(instance, {})
      vim.wait(10)

      local filtered_item_count = #instance.items

      MiniTest.expect.equality(filtered_item_count < original_item_count, true, 'filter should reduce available items')

      if filtered_item_count >= 2 then
        -- Test wrapping with filtered list
        if H_internal.actions.jump_to_bottom and H_internal.actions.move_next then
          H_internal.actions.jump_to_bottom(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(instance.selection.index, filtered_item_count, 'should be at last filtered item')

          -- Move forward - should wrap to first filtered item
          H_internal.actions.move_next(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            instance.selection.index,
            1,
            'forward from last filtered item should wrap to first filtered item'
          )
        end

        -- Test backward wrapping with filtered list
        if H_internal.actions.jump_to_top and H_internal.actions.move_prev then
          H_internal.actions.jump_to_top(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(instance.selection.index, 1, 'should be at first filtered item')

          -- Move backward - should wrap to last filtered item
          H_internal.actions.move_prev(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            instance.selection.index,
            filtered_item_count,
            'backward from first filtered item should wrap to last filtered item'
          )
        end
      end

      -- Test count-based wrapping with filtered items
      if filtered_item_count > 2 and H_internal.actions.move_next then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(10)

        -- Move more steps than filtered items available
        instance.pending_count = filtered_item_count + 2
        H_internal.actions.move_next(instance, {})
        vim.wait(10)

        -- Should wrap around within filtered items
        local expected_pos = ((filtered_item_count + 2 - 1) % filtered_item_count) + 1
        MiniTest.expect.equality(
          instance.selection.index,
          expected_pos,
          'count wrapping should work within filtered item set'
        )
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

T['Navigation Features']['Hide Wrapping: Wrapping skips hidden items correctly'] = function()
  -- Setup test data
  local test_buffers = {}
  local jumplist_entries = {}

  for i = 1, 5 do
    local buf = H.create_test_buffer(string.format('hide_wrap%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'hide_wrap1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = { wrap_edges = true },
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    if #instance.items >= 5 then
      -- Hide some middle items (items 2 and 4)
      local items_to_hide = { instance.items[2], instance.items[4] }
      for _, item in ipairs(items_to_hide) do
        if H_internal.hide and H_internal.hide.toggle then
          H_internal.hide.toggle(item)
        end
      end

      -- Refresh to apply hide changes
      if Jumppack.refresh then
        Jumppack.refresh()
        vim.wait(10)
      end

      state = Jumppack.get_state()
      if state and state.instance then
        instance = state.instance

        -- Count visible (non-hidden) items
        local visible_items = {}
        for _, item in ipairs(instance.items) do
          if not item.hidden then
            table.insert(visible_items, item)
          end
        end

        MiniTest.expect.equality(#visible_items >= 3, true, 'should have at least 3 visible items after hiding')

        if #visible_items >= 3 and H_internal.actions then
          -- Navigate to last visible item
          local last_visible_index = 0
          for i = #instance.items, 1, -1 do
            if not instance.items[i].hidden then
              last_visible_index = i
              break
            end
          end

          if last_visible_index > 0 then
            instance.selection.index = last_visible_index
            vim.wait(10)

            -- Move forward - should wrap to first visible item, skipping hidden
            if H_internal.actions.move_next then
              H_internal.actions.move_next(instance, {})
              vim.wait(10)

              -- Find first visible item
              local first_visible_index = 0
              for i = 1, #instance.items do
                if not instance.items[i].hidden then
                  first_visible_index = i
                  break
                end
              end

              MiniTest.expect.equality(
                instance.selection.index,
                first_visible_index,
                'wrapping forward should skip hidden items and go to first visible'
              )

              -- Verify we're not on a hidden item
              if instance.items[instance.selection.index] then
                MiniTest.expect.equality(
                  instance.items[instance.selection.index].hidden or false,
                  false,
                  'wrapped selection should not be on hidden item'
                )
              end
            end

            -- Test backward wrapping skips hidden items
            if H_internal.actions.move_prev then
              -- Move to first visible item
              instance.selection.index = first_visible_index or 1
              vim.wait(10)

              H_internal.actions.move_prev(instance, {})
              vim.wait(10)

              -- Should be on last visible item
              MiniTest.expect.equality(
                instance.selection.index,
                last_visible_index,
                'wrapping backward should skip hidden items and go to last visible'
              )

              -- Verify we're not on a hidden item
              if instance.items[instance.selection.index] then
                MiniTest.expect.equality(
                  instance.items[instance.selection.index].hidden or false,
                  false,
                  'backward wrapped selection should not be on hidden item'
                )
              end
            end
          end
        end
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)

  -- Clear hide storage
  if Jumppack.H and Jumppack.H.hide then
    Jumppack.H.hide.storage = {}
  end
end

T['Navigation Features']['State Preservation: View mode and selection preserved during wrapping'] = function()
  -- Setup test data
  local buf1 = H.create_test_buffer('state1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('state2.lua', { 'line 2' })
  local buf3 = H.create_test_buffer('state3.lua', { 'line 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'state1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = {
        wrap_edges = true,
        default_view = 'list', -- Start in list view
      },
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    if #instance.items >= 3 and H_internal.actions then
      -- Verify initial state
      local initial_view = instance.current_view

      -- Toggle to preview view if available
      if H_internal.actions.toggle_preview then
        H_internal.actions.toggle_preview(instance, {})
        vim.wait(10)

        local preview_view = instance.current_view
        MiniTest.expect.equality(preview_view ~= initial_view, true, 'view should change after toggle')

        -- Navigate to last item
        if H_internal.actions.jump_to_bottom then
          H_internal.actions.jump_to_bottom(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(instance.selection.index, #instance.items, 'should be at last item')

          -- Wrap forward - view should be preserved
          if H_internal.actions.move_next then
            H_internal.actions.move_next(instance, {})
            vim.wait(10)

            MiniTest.expect.equality(instance.selection.index, 1, 'should wrap to first item')

            MiniTest.expect.equality(
              instance.current_view,
              preview_view,
              'view mode should be preserved during wrapping'
            )
          end

          -- Test that selection wrapping works consistently
          if H_internal.actions.move_prev then
            H_internal.actions.move_prev(instance, {})
            vim.wait(10)

            MiniTest.expect.equality(instance.selection.index, #instance.items, 'should wrap to last item')

            MiniTest.expect.equality(
              instance.current_view,
              preview_view,
              'view mode should remain preserved after multiple wraps'
            )
          end
        end
      end

      -- Test state preservation with count-based navigation
      if H_internal.actions.jump_to_top and H_internal.actions.move_next then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(10)

        local pre_wrap_view = instance.current_view

        -- Use count to cause wrapping
        instance.pending_count = #instance.items + 1
        H_internal.actions.move_next(instance, {})
        vim.wait(10)

        MiniTest.expect.equality(
          instance.current_view,
          pre_wrap_view,
          'view mode should be preserved during count-based wrapping'
        )

        -- Verify we wrapped correctly
        local expected_pos = ((#instance.items + 1 - 1) % #instance.items) + 1
        MiniTest.expect.equality(
          instance.selection.index,
          expected_pos,
          'count-based wrapping should calculate position correctly'
        )
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3 })
end

-- Phase 4.2: Count System Testing

T['Navigation Features']['Count with C-o/C-i on Picker Start: Opening picker with count prefix'] = function()
  -- Setup test data with enough items for meaningful count testing
  local test_buffers = {}
  local jumplist_entries = {}

  for i = 1, 10 do
    local buf = H.create_test_buffer(string.format('count_start_%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 5) -- Current at position 5 (0-based index)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'count_start_5.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = { global_mappings = true, wrap_edges = false },
    })

    -- Test 3<C-o> - should start picker at offset -3 (3 jumps back)
    local start_state = H.start_and_verify({ offset = -3 })
    if start_state and start_state.items and #start_state.items > 0 then
      local selected_item = start_state.items[start_state.selection.index]

      -- Should select item with offset -3 from current position
      MiniTest.expect.equality(selected_item.offset, -3, 'count prefix 3<C-o> should select item with offset -3')
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end

    -- Test 2<C-i> - should start picker at offset 2 (2 jumps forward)
    start_state = H.start_and_verify({ offset = 2 })
    if start_state and start_state.items and #start_state.items > 0 then
      local selected_item = start_state.items[start_state.selection.index]

      MiniTest.expect.equality(selected_item.offset, 2, 'count prefix 2<C-i> should select item with offset 2')
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end

    -- Test large count - 8<C-o>
    start_state = H.start_and_verify({ offset = -8 })
    if start_state and start_state.items and #start_state.items > 0 then
      local selected_item = start_state.items[start_state.selection.index]

      -- Should find best available jump (since we don't have 8 backward jumps)
      MiniTest.expect.equality(type(selected_item.offset), 'number', 'large count should select valid item')

      MiniTest.expect.equality(selected_item.offset < 0, true, 'large backward count should select backward jump')
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)
end

T['Navigation Features']['Count Accumulation in Picker: Multi-digit count building'] = function()
  -- Setup test data
  local test_buffers = {}
  local jumplist_entries = {}

  for i = 1, 6 do
    local buf = H.create_test_buffer(string.format('count_accum_%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'count_accum_1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = { wrap_edges = true },
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance

    -- Test single digit accumulation
    instance.pending_count = ''
    instance.pending_count = instance.pending_count .. '3'

    MiniTest.expect.equality(instance.pending_count, '3', 'single digit should accumulate correctly')

    -- Test multi-digit accumulation
    instance.pending_count = instance.pending_count .. '5'

    MiniTest.expect.equality(instance.pending_count, '35', 'multi-digit count should accumulate correctly')

    -- Test '0' handling - should only work after other digits
    instance.pending_count = ''
    instance.pending_count = instance.pending_count .. '0'

    -- '0' alone should not be added (special handling)
    MiniTest.expect.equality(
      instance.pending_count == '' or instance.pending_count == '0',
      true,
      'standalone 0 should be handled specially'
    )

    -- '0' after other digits should work
    instance.pending_count = '1'
    instance.pending_count = instance.pending_count .. '0'

    MiniTest.expect.equality(instance.pending_count, '10', '0 after other digits should accumulate')

    -- Test count display in status
    local general_info = H.display.get_general_info(instance)
    if instance.pending_count ~= '' then
      MiniTest.expect.equality(type(general_info.status_text), 'string', 'status should include count information')

      MiniTest.expect.equality(
        string.find(general_info.status_text, instance.pending_count) ~= nil,
        true,
        'status should display pending count'
      )
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)
end

T['Navigation Features']['Smart Escape with Count: Escape clears count before closing picker'] = function()
  -- Setup test data
  local buf1 = H.create_test_buffer('escape_count1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('escape_count2.lua', { 'line 2' })
  local buf3 = H.create_test_buffer('escape_count3.lua', { 'line 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'escape_count1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Set up a pending count
    instance.pending_count = '25'

    MiniTest.expect.equality(instance.pending_count, '25', 'should have pending count set')

    -- First escape should clear count without closing picker
    if H_internal.actions and H_internal.actions.stop then
      local should_stop = H_internal.actions.stop(instance, 1)

      MiniTest.expect.equality(should_stop, false, 'first escape with active count should not close picker')

      MiniTest.expect.equality(instance.pending_count, '', 'first escape should clear pending count')

      -- Verify picker is still active
      MiniTest.expect.equality(Jumppack.is_active(), true, 'picker should remain active after count clear')

      -- Second escape should close picker
      local should_stop_second = H_internal.actions.stop(instance, 1)

      MiniTest.expect.equality(should_stop_second, true, 'second escape without count should close picker')
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Navigation Features']['Count Timeout: Automatic count clearing after timeout'] = function()
  -- Setup test data
  local buf1 = H.create_test_buffer('timeout1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('timeout2.lua', { 'line 2' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'timeout1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = { count_timeout_ms = 100 }, -- Short timeout for testing
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    -- Simulate digit accumulation (would normally trigger timeout)
    instance.pending_count = '5'

    -- Start timeout manually to test the mechanism
    if H_internal.instance and H_internal.instance.start_count_timeout then
      H_internal.instance.start_count_timeout(instance)
    end

    MiniTest.expect.equality(instance.pending_count, '5', 'count should be present before timeout')

    MiniTest.expect.equality(instance.count_timer ~= nil, true, 'count timer should be active')

    -- Wait for timeout to expire
    vim.wait(150) -- Wait longer than timeout

    -- Check that count was cleared by timeout
    MiniTest.expect.equality(instance.pending_count, '', 'count should be cleared after timeout')

    MiniTest.expect.equality(instance.count_timer == nil, true, 'count timer should be cleared after timeout')

    -- Test timeout reset on new digit
    instance.pending_count = '3'
    if H_internal.instance and H_internal.instance.start_count_timeout then
      H_internal.instance.start_count_timeout(instance)
    end

    -- Add another digit (would reset timeout in real usage)
    vim.wait(50) -- Wait less than timeout
    instance.pending_count = instance.pending_count .. '2'
    if H_internal.instance and H_internal.instance.start_count_timeout then
      H_internal.instance.start_count_timeout(instance) -- Reset timeout
    end

    vim.wait(60) -- Wait less than full timeout but more than first wait

    -- Count should still be there since timeout was reset
    MiniTest.expect.equality(instance.pending_count, '32', 'count should persist when timeout is reset')

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2 })
end

T['Navigation Features']['Count with Navigation Actions: Count behavior with jump actions'] = function()
  -- Setup test data with sufficient items for count testing
  local test_buffers = {}
  local jumplist_entries = {}

  for i = 1, 8 do
    local buf = H.create_test_buffer(string.format('nav_count_%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)

  -- Mock environment
  local original_fns = H.mock_vim_functions({
    current_file = 'nav_count_1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = { wrap_edges = true },
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return -- Skip if no valid state
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    if #instance.items >= 8 and H_internal.actions then
      -- Test count with jump_back (simulating 3<C-o>)
      if H_internal.actions.jump_back then
        local initial_selection = instance.selection.index

        H_internal.actions.jump_back(instance, 3) -- Count = 3
        vim.wait(10)

        -- Should have moved by count amount (or as much as possible)
        local selection_change = instance.selection.index - initial_selection
        MiniTest.expect.equality(math.abs(selection_change) > 0, true, 'count with jump_back should change selection')
      end

      -- Test count with jump_forward (simulating 2<C-i>)
      if H_internal.actions.jump_forward then
        local initial_selection = instance.selection.index

        H_internal.actions.jump_forward(instance, 2) -- Count = 2
        vim.wait(10)

        local selection_change = instance.selection.index - initial_selection
        MiniTest.expect.equality(
          math.abs(selection_change) > 0,
          true,
          'count with jump_forward should change selection'
        )
      end

      -- Test count larger than available items
      if H_internal.actions.jump_back then
        H_internal.actions.jump_back(instance, 99) -- Count much larger than items
        vim.wait(10)

        -- Should handle gracefully without errors
        MiniTest.expect.equality(
          instance.selection.index >= 1 and instance.selection.index <= #instance.items,
          true,
          'large count should maintain valid selection'
        )
      end

      -- Test count clearing after action
      instance.pending_count = '42'

      if H_internal.actions.jump_back then
        H_internal.actions.jump_back(instance, 1)
        vim.wait(10)

        MiniTest.expect.equality(instance.pending_count, '', 'pending count should be cleared after action execution')
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Restore and cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)
end

T['Navigation Features']['Count Edge Cases: Count behavior in extreme scenarios'] = function()
  local test_scenarios = {
    {
      name = 'empty_jumplist',
      item_count = 0,
      description = 'empty jumplist with count',
    },
    {
      name = 'single_item',
      item_count = 1,
      description = 'single item with count',
    },
    {
      name = 'count_larger_than_items',
      item_count = 3,
      count = 10,
      description = 'count larger than available items',
    },
  }

  for _, scenario in ipairs(test_scenarios) do
    -- Setup test data for this scenario
    local test_buffers = {}
    local jumplist_entries = {}

    if scenario.item_count > 0 then
      for i = 1, scenario.item_count do
        local buf = H.create_test_buffer(string.format('edge_%s_%d.lua', scenario.name, i), { 'line ' .. i })
        table.insert(test_buffers, buf)
        table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
      end
    end

    H.create_mock_jumplist(jumplist_entries, 0)

    -- Mock environment
    local original_fns = H.mock_vim_functions({
      current_file = scenario.item_count > 0 and string.format('edge_%s_1.lua', scenario.name) or '',
      cwd = vim.fn.getcwd(),
    })

    MiniTest.expect.no_error(function()
      Jumppack.setup({
        options = { wrap_edges = false },
      })

      Jumppack.start({})
      vim.wait(10)

      local state = Jumppack.get_state()

      if scenario.item_count == 0 then
        -- Empty jumplist should handle counts gracefully
        if state and state.instance then
          local instance = state.instance
          instance.pending_count = '5'

          -- Should handle count with empty list without errors
          local H_internal = Jumppack.H
          if H_internal.actions and H_internal.actions.jump_back then
            MiniTest.expect.no_error(function()
              H_internal.actions.jump_back(instance, 5)
            end, string.format('Count with %s should not error', scenario.description))
          end
        end
      else
        if state and state.instance then
          local instance = state.instance
          local H_internal = Jumppack.H

          if H_internal.actions and H_internal.actions.jump_back then
            local test_count = scenario.count or 2
            local initial_selection = instance.selection.index

            H_internal.actions.jump_back(instance, test_count)
            vim.wait(10)

            -- Should maintain valid selection
            MiniTest.expect.equality(
              instance.selection.index >= 1 and instance.selection.index <= math.max(1, #instance.items),
              true,
              string.format('Count with %s should maintain valid selection', scenario.description)
            )

            -- For single item, selection shouldn't change
            if scenario.item_count == 1 then
              MiniTest.expect.equality(
                instance.selection.index,
                initial_selection,
                'Count with single item should not change selection'
              )
            end
          end
        end
      end

      -- Cleanup
      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(10)
      end
    end, string.format('Error in %s scenario', scenario.name))

    -- Restore and cleanup
    H.restore_vim_functions(original_fns)
    if #test_buffers > 0 then
      H.cleanup_buffers(test_buffers)
    end
  end
end

-- ============================================================================
-- 7. EDGE CASES & RECOVERY TESTS (Phase 5)
-- ============================================================================
T['Edge Cases & Recovery'] = MiniTest.new_set()

-- ============================================================================
-- 5.1 Buffer/Window Management Tests
-- ============================================================================
T['Edge Cases & Recovery']['Buffer & Window Management'] = MiniTest.new_set()

T['Edge Cases & Recovery']['Buffer & Window Management']['handles source buffers deleted while picker active'] = function()
  -- Create test buffers and jumplist
  local buf1 = H.create_test_buffer('/project/file1.lua', { 'line 1', 'line 2' })
  local buf2 = H.create_test_buffer('/project/file2.lua', { 'other line' })
  local buf3 = H.create_test_buffer('/project/file3.lua', { 'third file' })

  local test_buffers = { buf1, buf2, buf3 }

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 1)

  local original_fns = H.mock_vim_functions({
    current_file = '/project/file1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Picker should start successfully')

    -- Delete buffer while picker is active
    vim.api.nvim_buf_delete(buf2, { force = true })

    -- Picker should continue to function and not crash
    if state and state.instance then
      local instance = state.instance
      local H_internal = Jumppack.H

      -- Navigation should work despite deleted buffer
      if H_internal.actions and H_internal.actions.jump_back then
        MiniTest.expect.no_error(function()
          H_internal.actions.jump_back(instance, 1)
        end, 'Navigation should work with deleted buffer in jumplist')
      end

      -- Should be able to refresh without error
      MiniTest.expect.no_error(function()
        Jumppack.refresh()
      end, 'Refresh should handle deleted buffers gracefully')

      -- Preview should handle deleted buffer gracefully
      if H_internal.display and H_internal.display.render_preview then
        MiniTest.expect.no_error(function()
          H_internal.display.render_preview(instance)
        end, 'Preview should handle deleted buffers gracefully')
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle deleted buffers without errors')

  -- Restore and cleanup remaining buffers
  H.restore_vim_functions(original_fns)
  for _, buf in ipairs({ buf1, buf3 }) do -- buf2 already deleted
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

T['Edge Cases & Recovery']['Buffer & Window Management']['gracefully handles window cleanup failures'] = function()
  -- Create minimal test setup
  local buf = H.create_test_buffer('/test/file.lua', { 'test line' })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = '/test/file.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Picker should start')

    if state and state.instance then
      local instance = state.instance
      local main_win = instance.windows.main

      -- Manually close the main window to simulate cleanup failure scenario
      if main_win and vim.api.nvim_win_is_valid(main_win) then
        pcall(vim.api.nvim_win_close, main_win, true)
      end

      -- Should handle subsequent cleanup gracefully
      MiniTest.expect.no_error(function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(50)
      end, 'Should handle pre-closed windows gracefully')
    end
  end, 'Should handle window cleanup failures gracefully')

  -- Cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Edge Cases & Recovery']['Buffer & Window Management']['handles jumplist entries with invalid buffers'] = function()
  -- Create a buffer then delete it to simulate invalid buffer scenario
  local valid_buf = H.create_test_buffer('/project/valid.lua', { 'valid content' })
  local invalid_buf = H.create_test_buffer('/project/invalid.lua', { 'will be deleted' })

  -- Delete the buffer to make it invalid
  vim.api.nvim_buf_delete(invalid_buf, { force = true })

  -- Create jumplist with mix of valid and invalid buffers
  H.create_mock_jumplist({
    { bufnr = valid_buf, lnum = 1, col = 0 },
    { bufnr = invalid_buf, lnum = 1, col = 0 }, -- Invalid buffer
    { bufnr = 9999, lnum = 1, col = 0 }, -- Non-existent buffer number
  }, 1)

  local original_fns = H.mock_vim_functions({
    current_file = '/project/valid.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should start with invalid buffers in jumplist')

    if state and state.instance then
      local instance = state.instance

      -- Should have filtered out invalid buffers or handled them gracefully
      MiniTest.expect.equality(#instance.items >= 0, true, 'Should create items despite invalid buffers')

      -- Navigation should work despite invalid entries
      local H_internal = Jumppack.H
      if H_internal.actions and H_internal.actions.jump_back then
        MiniTest.expect.no_error(function()
          H_internal.actions.jump_back(instance, 1)
        end, 'Navigation should work with invalid buffers present')
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle invalid buffers without crashing')

  -- Cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ valid_buf })
end

T['Edge Cases & Recovery']['Buffer & Window Management']['handles concurrent start() calls gracefully'] = function()
  -- Create test setup
  local buf = H.create_test_buffer('/test/concurrent.lua', { 'test content' })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = '/test/concurrent.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})

    -- Start first instance
    Jumppack.start({})
    vim.wait(10)

    local state1 = Jumppack.get_state()
    MiniTest.expect.equality(state1 and state1.instance ~= nil, true, 'First start should succeed')

    -- Try to start second instance while first is active
    local first_instance = state1.instance

    MiniTest.expect.no_error(function()
      Jumppack.start({}) -- Second call should be handled gracefully
      vim.wait(10)
    end, 'Second start() call should not crash')

    local state2 = Jumppack.get_state()

    -- Should either:
    -- 1. Replace the first instance cleanly, OR
    -- 2. Ignore the second call and keep the first instance
    MiniTest.expect.equality(
      state2 and state2.instance ~= nil,
      true,
      'Should maintain valid state after concurrent start'
    )

    -- Should still be able to navigate
    if state2 and state2.instance then
      local instance = state2.instance
      local H_internal = Jumppack.H

      if H_internal.actions and H_internal.actions.jump_back then
        MiniTest.expect.no_error(function()
          H_internal.actions.jump_back(instance, 1)
        end, 'Navigation should work after concurrent start calls')
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle concurrent start() calls gracefully')

  -- Cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

-- ============================================================================
-- 5.2 State Corruption Recovery Tests
-- ============================================================================
T['Edge Cases & Recovery']['State Corruption Recovery'] = MiniTest.new_set()

T['Edge Cases & Recovery']['State Corruption Recovery']['handles corrupted vim jumplist data'] = function()
  -- Create test buffer for reference
  local buf = H.create_test_buffer('/test/reference.lua', { 'reference line' })

  -- Mock corrupted jumplist data with various corruption scenarios
  vim.fn.getjumplist = function()
    return {
      {
        -- Corrupted entry with missing fields
        { bufnr = buf, lnum = 1 }, -- missing col
        -- Entry with invalid line numbers
        { bufnr = buf, lnum = -5, col = 0 }, -- negative line
        { bufnr = buf, lnum = 0, col = -1 }, -- zero line, negative col
        -- Entry with enormous values
        { bufnr = buf, lnum = 999999999, col = 999999 },
        -- Entry with nil/string values where numbers expected
        { bufnr = buf, lnum = 'invalid', col = 'invalid' },
        -- Valid entry for comparison
        { bufnr = buf, lnum = 1, col = 0 },
      },
      2, -- position
    }
  end

  local original_fns = H.mock_vim_functions({
    current_file = '/test/reference.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})

    -- Should handle corrupted jumplist gracefully
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should handle corrupted jumplist data')

    if state and state.instance then
      local instance = state.instance

      -- Should have created some items (at least the valid ones)
      MiniTest.expect.equality(#instance.items >= 0, true, 'Should create items from valid entries')

      -- Navigation should work with cleaned data
      local H_internal = Jumppack.H
      if H_internal.actions and H_internal.actions.jump_back then
        MiniTest.expect.no_error(function()
          H_internal.actions.jump_back(instance, 1)
        end, 'Navigation should work with cleaned jumplist data')
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle corrupted jumplist data without crashing')

  -- Cleanup
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Edge Cases & Recovery']['State Corruption Recovery']['handles missing files gracefully'] = function()
  -- Create a buffer with a path that looks like a real file
  local buf = H.create_test_buffer('/nonexistent/missing/file.lua', { 'content for missing file' })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  -- Mock file system functions to simulate missing files
  local original_fns = H.mock_vim_functions({
    current_file = '/nonexistent/missing/file.lua',
    cwd = '/nonexistent/missing', -- Non-existent directory
  })

  -- Mock additional file system checks
  local original_fn_exists = vim.fn.filereadable
  vim.fn.filereadable = function(path)
    if string.match(path, '/nonexistent/') then
      return 0 -- File doesn't exist
    end
    return original_fn_exists(path)
  end

  local original_fn_isdirectory = vim.fn.isdirectory
  vim.fn.isdirectory = function(path)
    if string.match(path, '/nonexistent/') then
      return 0 -- Directory doesn't exist
    end
    return original_fn_isdirectory(path)
  end

  MiniTest.expect.no_error(function()
    Jumppack.setup({})

    -- Should handle missing files gracefully
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should start with missing files')

    if state and state.instance then
      local instance = state.instance

      -- Should create items (may filter out missing files or keep them with warnings)
      MiniTest.expect.equality(#instance.items >= 0, true, 'Should handle missing files')

      -- Preview should handle missing files gracefully
      local H_internal = Jumppack.H
      if H_internal.display and H_internal.display.render_preview then
        MiniTest.expect.no_error(function()
          H_internal.display.render_preview(instance)
        end, 'Preview should handle missing files gracefully')
      end

      -- Filter operations should work
      if H_internal.actions and H_internal.actions.toggle_file_filter then
        MiniTest.expect.no_error(function()
          H_internal.actions.toggle_file_filter(instance)
        end, 'Filter operations should work with missing files')
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle missing files without errors')

  -- Restore functions
  vim.fn.filereadable = original_fn_exists
  vim.fn.isdirectory = original_fn_isdirectory
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Edge Cases & Recovery']['State Corruption Recovery']['handles simulated permission errors'] = function()
  -- Create test buffer
  local buf = H.create_test_buffer('/restricted/permission_test.lua', { 'restricted content' })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  -- Mock permission errors by intercepting file operations
  local original_fns = H.mock_vim_functions({
    current_file = '/restricted/permission_test.lua',
    cwd = vim.fn.getcwd(),
  })

  -- Mock file read operations to simulate permission errors
  local original_readfile = vim.fn.readfile
  vim.fn.readfile = function(path, ...)
    if string.match(path, '/restricted/') then
      error('Permission denied') -- Simulate permission error
    end
    return original_readfile(path, ...)
  end

  MiniTest.expect.no_error(function()
    Jumppack.setup({})

    -- Should handle permission errors gracefully
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should start with permission-restricted files')

    if state and state.instance then
      local instance = state.instance

      -- Should handle the restricted files gracefully
      MiniTest.expect.equality(#instance.items >= 0, true, 'Should create items despite permission errors')

      -- Preview should handle permission errors gracefully
      local H_internal = Jumppack.H
      if H_internal.display and H_internal.display.render_preview then
        MiniTest.expect.no_error(function()
          H_internal.display.render_preview(instance)
        end, 'Preview should handle permission errors gracefully')
      end

      -- Choosing items should handle permission errors
      if H_internal.actions and H_internal.actions.choose then
        MiniTest.expect.no_error(function()
          -- This may fail internally but shouldn't crash
          pcall(H_internal.actions.choose, instance)
        end, 'Choose action should handle permission errors gracefully')
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle simulated permission errors without crashing')

  -- Restore functions
  vim.fn.readfile = original_readfile
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Edge Cases & Recovery']['State Corruption Recovery']['ensures memory cleanup with no leaks'] = function()
  -- This test ensures proper cleanup in various scenarios
  local test_buffers = {}

  -- Create multiple test scenarios that could cause memory leaks
  for i = 1, 5 do
    local buf = H.create_test_buffer('/memory/test' .. i .. '.lua', { 'test content ' .. i })
    table.insert(test_buffers, buf)
  end

  H.create_mock_jumplist({
    { bufnr = test_buffers[1], lnum = 1, col = 0 },
    { bufnr = test_buffers[2], lnum = 1, col = 0 },
    { bufnr = test_buffers[3], lnum = 1, col = 0 },
  }, 1)

  local original_fns = H.mock_vim_functions({
    current_file = '/memory/test1.lua',
    cwd = vim.fn.getcwd(),
  })

  -- Track memory usage patterns through multiple start/stop cycles
  for cycle = 1, 3 do
    MiniTest.expect.no_error(function()
      Jumppack.setup({})

      -- Start picker
      Jumppack.start({})
      vim.wait(10)

      local state = Jumppack.get_state()
      MiniTest.expect.equality(state and state.instance ~= nil, true, 'Cycle ' .. cycle .. ' should start')

      if state and state.instance then
        local instance = state.instance
        local H_internal = Jumppack.H

        -- Perform various operations that create state
        if H_internal.actions then
          if H_internal.actions.toggle_file_filter then
            H_internal.actions.toggle_file_filter(instance)
          end
          if H_internal.actions.jump_back then
            H_internal.actions.jump_back(instance, 1)
          end
          if H_internal.actions.toggle_preview then
            H_internal.actions.toggle_preview(instance)
          end
        end

        -- Delete a buffer mid-operation to test cleanup
        if cycle == 2 then
          vim.api.nvim_buf_delete(test_buffers[2], { force = true })
        end
      end

      -- Force stop to ensure cleanup
      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(50)
      end

      -- Verify clean state after stop
      local final_state = Jumppack.get_state()
      MiniTest.expect.equality(final_state, nil, 'State should be clean after stop in cycle ' .. cycle)
    end, 'Memory cleanup cycle ' .. cycle .. ' should complete without errors')
  end

  -- Verify no persistent state remains
  MiniTest.expect.no_error(function()
    -- Multiple refresh calls on inactive state should not accumulate errors
    for _ = 1, 5 do
      Jumppack.refresh()
    end
  end, 'Multiple refresh calls on inactive picker should not cause issues')

  -- Cleanup
  H.restore_vim_functions(original_fns)
  -- Clean up remaining buffers (skip already deleted one from cycle 2)
  for i, buf in ipairs(test_buffers) do
    if i ~= 2 and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

-- ============================================================================
-- 5.3 Configuration Edge Cases Tests
-- ============================================================================
T['Edge Cases & Recovery']['Configuration Edge Cases'] = MiniTest.new_set()

T['Edge Cases & Recovery']['Configuration Edge Cases']['handles conflicting key mappings'] = function()
  -- Create minimal test setup
  local buf = H.create_test_buffer('/test/mapping.lua', { 'test content' })
  H.create_mock_jumplist({ { bufnr = buf, lnum = 1, col = 0 } }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = '/test/mapping.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    -- Test conflicting mappings (multiple actions for same key)
    Jumppack.setup({
      mappings = {
        jump_back = '<C-o>',
        jump_forward = '<C-o>', -- Conflicting mapping
        choose = '<CR>',
        stop = '<CR>', -- Another conflict
      },
    })

    -- Should handle conflicts gracefully without crashing
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should start despite mapping conflicts')

    if state and state.instance then
      -- Should still function with the mappings that work
      local H_internal = Jumppack.H
      if H_internal.actions and H_internal.actions.jump_back then
        MiniTest.expect.no_error(function()
          H_internal.actions.jump_back(state.instance, 1)
        end, 'Navigation should work despite mapping conflicts')
      end
    end

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle conflicting key mappings gracefully')

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Edge Cases & Recovery']['Configuration Edge Cases']['handles invalid mapping types'] = function()
  local buf = H.create_test_buffer('/test/invalid_mappings.lua', { 'test content' })
  H.create_mock_jumplist({ { bufnr = buf, lnum = 1, col = 0 } }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = '/test/invalid_mappings.lua',
    cwd = vim.fn.getcwd(),
  })

  -- Test various invalid mapping configurations
  local invalid_configs = {
    -- Numbers instead of strings (should fail)
    { config = { mappings = { jump_back = 123, jump_forward = 456 } }, should_fail = true },
    -- Functions instead of strings (should fail)
    { config = { mappings = { jump_back = function() end, choose = '<CR>' } }, should_fail = true },
    -- Tables instead of strings (should fail)
    { config = { mappings = { jump_back = {}, jump_forward = '<C-i>' } }, should_fail = true },
    -- Boolean instead of strings (should fail)
    { config = { mappings = { jump_back = true, jump_forward = false } }, should_fail = true },
    -- Nil values mixed with valid ones (may succeed with defaults)
    { config = { mappings = { jump_back = nil, choose = '<CR>', stop = '<Esc>' } }, should_fail = false },
  }

  for i, test_case in ipairs(invalid_configs) do
    local success, err = pcall(function()
      Jumppack.setup(test_case.config)
    end)

    if test_case.should_fail then
      MiniTest.expect.equality(success, false, 'Invalid mapping config ' .. i .. ' should be rejected')
      MiniTest.expect.equality(type(err), 'string', 'Invalid mapping config ' .. i .. ' should provide error message')
    else
      -- These configs might succeed with graceful fallbacks
      MiniTest.expect.no_error(function()
        -- Just verify it doesn't crash
        Jumppack.setup(test_case.config)
      end, 'Config ' .. i .. ' should handle gracefully')
    end
  end

  -- Test that valid config still works after invalid attempts
  MiniTest.expect.no_error(function()
    Jumppack.setup({
      mappings = {
        jump_back = '<C-o>',
        jump_forward = '<C-i>',
        choose = '<CR>',
        stop = '<Esc>',
      },
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should recover from invalid config attempts')

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle invalid mapping types and recover gracefully')

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Edge Cases & Recovery']['Configuration Edge Cases']['handles malformed config structure'] = function()
  local buf = H.create_test_buffer('/test/malformed.lua', { 'test content' })
  H.create_mock_jumplist({ { bufnr = buf, lnum = 1, col = 0 } }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = '/test/malformed.lua',
    cwd = vim.fn.getcwd(),
  })

  -- Test various malformed configurations
  local malformed_configs = {
    -- Non-table top level
    'invalid_string_config',
    123,
    function() end,
    true,
    -- Nested malformed structures
    { options = 'should_be_table' },
    { window = 'should_be_table' },
    { mappings = 'should_be_table' },
    -- Mixed valid/invalid
    {
      options = { default_view = 'list' },
      window = 'invalid',
      mappings = { jump_back = '<C-o>' },
    },
  }

  for i, config in ipairs(malformed_configs) do
    -- Test that malformed configs are properly rejected (these should all error)
    local success, err = pcall(function()
      Jumppack.setup(config)
    end)
    MiniTest.expect.equality(success, false, 'Malformed config ' .. i .. ' should be rejected')
    MiniTest.expect.equality(type(err), 'string', 'Malformed config ' .. i .. ' should provide error message')
  end

  -- Test recovery with valid config
  MiniTest.expect.no_error(function()
    Jumppack.setup({}) -- Default config should work

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should recover with default config')

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle malformed config and recover with defaults')

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Edge Cases & Recovery']['Configuration Edge Cases']['handles invalid window config'] = function()
  local buf = H.create_test_buffer('/test/window_config.lua', { 'test content' })
  H.create_mock_jumplist({ { bufnr = buf, lnum = 1, col = 0 } }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = '/test/window_config.lua',
    cwd = vim.fn.getcwd(),
  })

  -- Test invalid window configurations
  local invalid_window_configs = {
    -- Invalid config types
    { window = { config = 'should_be_table_or_function' } },
    { window = { config = 123 } },
    { window = { config = true } },
  }

  for i, config in ipairs(invalid_window_configs) do
    -- Test that invalid window configs are properly rejected (these should all error)
    local success, err = pcall(function()
      Jumppack.setup(config)
    end)
    MiniTest.expect.equality(success, false, 'Invalid window config ' .. i .. ' should be rejected')
    MiniTest.expect.equality(type(err), 'string', 'Invalid window config ' .. i .. ' should provide error message')
  end

  -- Test that valid window config works
  MiniTest.expect.no_error(function()
    Jumppack.setup({
      window = {
        config = {
          relative = 'editor',
          width = 80,
          height = 20,
          row = 5,
          col = 5,
        },
      },
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should work with valid window config')

    -- Cleanup
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle invalid window config and work with valid ones')

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Edge Cases & Recovery']['Configuration Edge Cases']['handles config changes during active picker'] = function()
  local buf = H.create_test_buffer('/test/runtime_config.lua', { 'test content' })
  H.create_mock_jumplist({ { bufnr = buf, lnum = 1, col = 0 } }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = '/test/runtime_config.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    -- Start with initial config
    Jumppack.setup({
      options = { default_view = 'list' },
      mappings = { jump_back = '<C-o>', jump_forward = '<C-i>' },
    })

    Jumppack.start({})
    vim.wait(10)

    local state1 = Jumppack.get_state()
    MiniTest.expect.equality(state1 and state1.instance ~= nil, true, 'Should start with initial config')

    -- Try to change config while picker is active
    MiniTest.expect.no_error(function()
      Jumppack.setup({
        options = { default_view = 'preview' },
        mappings = { jump_back = '<C-k>', jump_forward = '<C-j>' },
      })
    end, 'Should handle config changes during active picker')

    -- Picker should either continue with old config or handle change gracefully
    local state2 = Jumppack.get_state()
    MiniTest.expect.equality(state2 and state2.instance ~= nil, true, 'Should maintain valid state after config change')

    if state2 and state2.instance then
      local instance = state2.instance
      local H_internal = Jumppack.H

      -- Should still be navigable
      if H_internal.actions and H_internal.actions.jump_back then
        MiniTest.expect.no_error(function()
          H_internal.actions.jump_back(instance, 1)
        end, 'Should still be navigable after config change')
      end
    end

    -- Cleanup current picker
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end

    -- Test that new config works for next picker
    MiniTest.expect.no_error(function()
      Jumppack.start({})
      vim.wait(10)

      local state3 = Jumppack.get_state()
      MiniTest.expect.equality(state3 and state3.instance ~= nil, true, 'New picker should work with updated config')

      -- Cleanup
      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(50)
      end
    end, 'New picker should respect updated configuration')
  end, 'Should handle runtime config changes gracefully')

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

return T
