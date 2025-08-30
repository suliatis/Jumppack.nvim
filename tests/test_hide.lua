local MiniTest = require('mini.test')
local H = require('tests.helpers')
local T = H.create_test_suite()
local Jumppack = require('lua.Jumppack')

T['Hide Features'] = MiniTest.new_set()

T['Hide Features']['H.hide functions'] = function()

  Jumppack.H.hide.storage = {}

  local item = { path = '/test/file.lua', lnum = 10 }


  local key = Jumppack.H.hide.get_key(item)
  MiniTest.expect.equality(key, '/test/file.lua:10')


  MiniTest.expect.equality(Jumppack.H.hide.is_hidden(item), false)


  local new_status = Jumppack.H.hide.toggle(item)
  MiniTest.expect.equality(new_status, true)
  MiniTest.expect.equality(Jumppack.H.hide.is_hidden(item), true)


  new_status = Jumppack.H.hide.toggle(item)
  MiniTest.expect.equality(new_status, false)
  MiniTest.expect.equality(Jumppack.H.hide.is_hidden(item), false)


  local items = {
    { path = '/test/file1.lua', lnum = 1 },
    { path = '/test/file2.lua', lnum = 2 },
  }


  Jumppack.H.hide.toggle(items[1])


  local marked_items = Jumppack.H.hide.mark_items(items)
  MiniTest.expect.equality(marked_items[1].hidden, true)
  MiniTest.expect.equality(marked_items[2].hidden, false)


  Jumppack.H.hide.storage = {}
end

T['Hide Features']['Toggle hidden action'] = function()

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


  Jumppack.H.hide.storage = {}


  local H = Jumppack.H
  MiniTest.expect.equality(type(H.actions.toggle_hidden), 'function')


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


  local normal_display = Jumppack.H.display.item_to_string(item_normal, { show_preview = false })
  MiniTest.expect.equality(normal_display:find('✗') == nil, true)


  local hidden_display = Jumppack.H.display.item_to_string(item_hidden, { show_preview = false })
  MiniTest.expect.equality(hidden_display:find('✗') ~= nil, true)
end

T['Hide Features']['Hide current item moves selection correctly'] = function()
  local buf1 = H.create_test_buffer('/test/file1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('/test/file2.lua', { 'line 2' })
  local buf3 = H.create_test_buffer('/test/file3.lua', { 'line 3' })
  local buf4 = H.create_test_buffer('/test/file4.lua', { 'line 4' })


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
    H.instance.set_selection(instance, 2) -- Select middle item
    local selected_item = H.instance.get_selection(instance)
    if selected_item then
      H_actions.toggle_hidden(instance, {})
      vim.wait(10)


      MiniTest.expect.equality(#instance.items, initial_count - 1)

      MiniTest.expect.equality(instance.current <= #instance.items, true)
    end


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


  Jumppack.H.hide.storage = {}
  H.cleanup_buffers({ buf1, buf2, buf3, buf4 })
end

T['Hide Features']['Hide item updates both views'] = function()
  local buf1 = H.create_test_buffer('/test/main.lua', { 'main content' })
  local buf2 = H.create_test_buffer('/test/other.lua', { 'other content' })


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


    instance.view_state = 'preview'
    H.instance.set_selection(instance, 1)
    local initial_view = instance.view_state

    local selected_item = H.instance.get_selection(instance)
    if selected_item then
      H_actions.toggle_hidden(instance, {})
      vim.wait(10)


      MiniTest.expect.equality(instance.view_state, initial_view)
    end


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


  Jumppack.H.hide.storage = {}
  H.cleanup_buffers({ buf1, buf2 })
end

T['Hide Features']['Hide item respects show_hidden filter'] = function()
  local buf1 = H.create_test_buffer('/test/file1.lua', { 'content 1' })
  local buf2 = H.create_test_buffer('/test/file2.lua', { 'content 2' })


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


    H.instance.set_selection(instance, 1)
    local selected_item = H.instance.get_selection(instance)
    if selected_item then
      H_actions.toggle_hidden(instance, {})
      vim.wait(10)


      MiniTest.expect.equality(#instance.items, initial_count - 1)
    end


    H_actions.toggle_show_hidden(instance, {})
    vim.wait(10)


    MiniTest.expect.equality(#instance.items >= initial_count - 1, true)

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)


  Jumppack.H.hide.storage = {}
  H.cleanup_buffers({ buf1, buf2 })
end

T['Hide Features']['Hide multiple items in sequence'] = function()
  local buf1 = H.create_test_buffer('/test/item1.lua', { 'content 1' })
  local buf2 = H.create_test_buffer('/test/item2.lua', { 'content 2' })
  local buf3 = H.create_test_buffer('/test/item3.lua', { 'content 3' })
  local buf4 = H.create_test_buffer('/test/item4.lua', { 'content 4' })


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


    MiniTest.expect.equality(#instance.items < initial_count, true)

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)


  Jumppack.H.hide.storage = {}
  H.cleanup_buffers({ buf1, buf2, buf3, buf4 })
end

-- Additional Navigation Features subcategories

-- Edge Cases tests have been reorganized into feature-focused groups above

return T
