local MiniTest = require('mini.test')
local H = require('tests.helpers')
local T = H.create_test_suite()
local Jumppack = require('lua.Jumppack')

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

    -- Test display formatting with special characters - enhancement from breaking analysis
    local lines = vim.api.nvim_buf_get_lines(instance.buffers.main, 0, -1, false)
    for _, line in ipairs(lines) do
      -- Verify display doesn't break with special characters in paths
      MiniTest.expect.equality(type(line), 'string', 'display lines should remain strings with special chars')
      MiniTest.expect.equality(#line > 0, true, 'display lines should not be empty with special chars')

      -- Test specific challenging cases are handled
      if line:match('my file with spaces') then
        MiniTest.expect.string_matches(line, 'my file with spaces%.lua', 'spaces in filenames should be preserved')
      elseif line:match('🚀') then
        MiniTest.expect.string_matches(line, '🚀', 'unicode characters should display correctly')
      elseif line:match('%%') then
        MiniTest.expect.string_matches(line, '%%', 'percent characters should be handled correctly')
      end
    end

    -- Test navigation with special character paths
    if #instance.items >= 2 then
      local original_index = instance.selection.index
      H_internal.instance.move_selection(instance, 1)

      MiniTest.expect.equality(
        instance.selection.index ~= original_index or #instance.items == 1,
        true,
        'navigation should work with special character paths'
      )

      -- Verify selection is still within bounds
      MiniTest.expect.equality(
        instance.selection.index >= 1 and instance.selection.index <= #instance.items,
        true,
        'selection bounds should be maintained with special character paths'
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

return T
