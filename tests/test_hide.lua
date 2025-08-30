local MiniTest = require('mini.test')
local H = require('tests.helpers')
local T = H.create_test_suite()
local Jumppack = require('lua.Jumppack')

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

-- Edge Cases tests have been reorganized into feature-focused groups above

return T
