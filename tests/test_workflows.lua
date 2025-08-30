local MiniTest = require('mini.test')
local H = require('tests.helpers')
local T = H.create_test_suite()
local Jumppack = require('lua.Jumppack')

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

return T
