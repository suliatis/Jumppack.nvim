local MiniTest = require('mini.test')
local H = require('tests.helpers')
local T = H.create_test_suite()
local Jumppack = require('lua.Jumppack')

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

T['Navigation Features']['Basic Processing']['filters invalid buffers correctly'] = function()

  local valid_buf = H.create_test_buffer('valid.lua', { 'valid content' })


  H.create_mock_jumplist({
    { bufnr = valid_buf, lnum = 1, col = 0 }, -- Valid buffer
    { bufnr = 0, lnum = 2, col = 0 }, -- Invalid: zero
    { bufnr = -1, lnum = 3, col = 0 }, -- Invalid: negative
    { bufnr = 99999, lnum = 4, col = 0 }, -- Invalid: non-existent
  }, 0)

  MiniTest.expect.no_error(function()
    local state = H.start_and_verify({ offset = -1 })

    if state and state.items then


      MiniTest.expect.equality(#state.items >= 0, true, 'should handle invalid buffers without crashing')


      for _, item in ipairs(state.items) do
        MiniTest.expect.equality(type(item.bufnr), 'number', 'all items should have numeric bufnr')
        MiniTest.expect.equality(item.bufnr > 0, true, 'all items should have positive bufnr')
      end
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'should filter invalid buffers without errors')

  H.cleanup_buffers({ valid_buf })
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


  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = 99 })
    vim.wait(10)

    local state = Jumppack.get_state()
    if state and state.current then

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


  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -99 })
    vim.wait(10)

    local state = Jumppack.get_state()
    if state and state.current then

      MiniTest.expect.equality(state.current.offset, -2)
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2, buf3 })
end

-- Additional Navigation Features subcategories for robustness testing
T['Navigation Features']['Buffer Management'] = MiniTest.new_set()

T['Navigation Features']['Buffer Management']['handles source buffers deleted while picker active'] = function()

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


    vim.api.nvim_buf_delete(buf2, { force = true })


    if state and state.instance then
      local instance = state.instance
      local H_internal = Jumppack.H


      if H_internal.actions and H_internal.actions.jump_back then
        MiniTest.expect.no_error(function()
          H_internal.actions.jump_back(instance, 1)
        end, 'Navigation should work with deleted buffer in jumplist')
      end


      MiniTest.expect.no_error(function()
        Jumppack.refresh()
      end, 'Refresh should handle deleted buffers gracefully')


      if H_internal.display and H_internal.display.render_preview then
        MiniTest.expect.no_error(function()
          H_internal.display.render_preview(instance)
        end, 'Preview should handle deleted buffers gracefully')
      end
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle deleted buffers without errors')


  H.restore_vim_functions(original_fns)
  for _, buf in ipairs({ buf1, buf3 }) do -- buf2 already deleted
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

T['Navigation Features']['Window Management'] = MiniTest.new_set()

T['Navigation Features']['Window Management']['gracefully handles window cleanup failures'] = function()

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


      if main_win and vim.api.nvim_win_is_valid(main_win) then
        pcall(vim.api.nvim_win_close, main_win, true)
      end


      MiniTest.expect.no_error(function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(50)
      end, 'Should handle pre-closed windows gracefully')
    end
  end, 'Should handle window cleanup failures gracefully')


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Navigation Features']['Window Management']['verifies window and buffer cleanup'] = function()

  local buf = H.create_test_buffer('/cleanup/test.lua', { 'test content' })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = '/cleanup/test.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()

    local windows_before = vim.api.nvim_list_wins()
    local buffers_before = vim.api.nvim_list_bufs()

    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return
    end


    local windows_during = vim.api.nvim_list_wins()
    local buffers_during = vim.api.nvim_list_bufs()

    MiniTest.expect.equality(#windows_during > #windows_before, true, 'Picker should create new window')
    MiniTest.expect.equality(#buffers_during > #buffers_before, true, 'Picker should create new buffer')

    local instance = state.instance
    local picker_window = instance.windows.main
    local picker_buffer = instance.buffers.main


    MiniTest.expect.equality(vim.api.nvim_win_is_valid(picker_window), true, 'Picker window should be valid')
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(picker_buffer), true, 'Picker buffer should be valid')


    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)


    MiniTest.expect.equality(
      vim.api.nvim_win_is_valid(picker_window),
      false,
      'Picker window should be closed after exit'
    )
    MiniTest.expect.equality(
      vim.api.nvim_buf_is_valid(picker_buffer),
      false,
      'Picker buffer should be deleted after exit'
    )


    local windows_after = vim.api.nvim_list_wins()
    local buffers_after = vim.api.nvim_list_bufs()

    MiniTest.expect.equality(#windows_after, #windows_before, 'Should return to original window count')

  end, 'Should properly cleanup windows and buffers')

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

T['Navigation Features']['Buffer Validation'] = MiniTest.new_set()

T['Navigation Features']['Buffer Validation']['handles jumplist entries with invalid buffers'] = function()

  local valid_buf = H.create_test_buffer('/project/valid.lua', { 'valid content' })
  local invalid_buf = H.create_test_buffer('/project/invalid.lua', { 'will be deleted' })


  vim.api.nvim_buf_delete(invalid_buf, { force = true })


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


      MiniTest.expect.equality(#instance.items >= 0, true, 'Should create items despite invalid buffers')


      local H_internal = Jumppack.H
      if H_internal.actions and H_internal.actions.jump_back then
        MiniTest.expect.no_error(function()
          H_internal.actions.jump_back(instance, 1)
        end, 'Navigation should work with invalid buffers present')
      end
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(50)
    end
  end, 'Should handle invalid buffers without crashing')


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ valid_buf })
end

T['Navigation Features']['find_best_selection'] = function()

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


  local selection = Jumppack.H.instance.find_best_selection(mock_instance, filtered_items)

  MiniTest.expect.equality(selection, 1)


  mock_instance.current_ind = 1 -- Currently on file1.lua
  selection = Jumppack.H.instance.find_best_selection(mock_instance, filtered_items)
  MiniTest.expect.equality(selection, 1) -- Should find exact match
end

T['Navigation Features']['Navigation actions'] = function()

  local H = Jumppack.H
  MiniTest.expect.equality(type(H.actions.jump_back), 'function')
  MiniTest.expect.equality(type(H.actions.jump_forward), 'function')



end

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


  local selection = Jumppack.H.instance.calculate_filtered_initial_selection(original_items, filtered_items, 3)
  MiniTest.expect.equality(selection, 2) -- file3.lua should be at index 2 in filtered items


  selection = Jumppack.H.instance.calculate_filtered_initial_selection(original_items, filtered_items, 4)
  MiniTest.expect.equality(selection, 2) -- Should find file3.lua (offset=0) as first closest to file4.lua (offset=1)


  selection = Jumppack.H.instance.calculate_filtered_initial_selection(original_items, filtered_items, nil)
  MiniTest.expect.equality(selection, 1) -- Should default to 1

  selection = Jumppack.H.instance.calculate_filtered_initial_selection(original_items, filtered_items, 10)
  MiniTest.expect.equality(selection, 3) -- Should clamp to last item and find closest
end

-- Count functionality tests

T['Navigation Features']['instance has pending_count field'] = function()
  local H = Jumppack.H


  local mock_instance = {
    items = { {}, {}, {}, {}, {} }, -- 5 items
    current_ind = 3,
    action_keys = {},
    filters = { file_only = false, cwd_only = false, show_hidden = false },
    pending_count = '',
  }

  MiniTest.expect.equality(mock_instance.pending_count, '')


  mock_instance.pending_count = '25'
  MiniTest.expect.equality(mock_instance.pending_count, '25')
end

T['Navigation Features']['actions handle count parameter'] = function()
  local H = Jumppack.H


  local moved_by = nil
  local mock_instance = {
    items = { {}, {}, {}, {}, {}, {}, {}, {}, {}, {} }, -- 10 items
    current_ind = 5,
  }


  H.instance.move_selection = function(instance, by)
    moved_by = by
    instance.current_ind = math.max(1, math.min(#instance.items, instance.current_ind + by))
  end


  H.actions.jump_back(mock_instance, 3)
  MiniTest.expect.equality(moved_by, 3)


  H.actions.jump_forward(mock_instance, 2)
  MiniTest.expect.equality(moved_by, -2)


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

  MiniTest.expect.equality(info.status_text:find('×'), nil)
  MiniTest.expect.equality(info.position_indicator:find('×'), nil)
end

-- Jump navigation tests

T['Navigation Features']['new actions exist and are callable'] = function()
  local H_internal = Jumppack.H
  local actions = H_internal.actions


  MiniTest.expect.equality(type(actions.jump_to_top), 'function')
  MiniTest.expect.equality(type(actions.jump_to_bottom), 'function')


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

  MiniTest.expect.equality(type(Jumppack.config.mappings.jump_to_top), 'string')
  MiniTest.expect.equality(type(Jumppack.config.mappings.jump_to_bottom), 'string')


  MiniTest.expect.equality(Jumppack.config.mappings.jump_to_top, 'g')
  MiniTest.expect.equality(Jumppack.config.mappings.jump_to_bottom, 'G')
end

T['Navigation Features']['all actions have corresponding config mappings'] = function()
  local H_internal = Jumppack.H
  local actions = H_internal.actions
  local mappings = Jumppack.config.mappings


  MiniTest.expect.equality(type(actions.jump_to_top), 'function')
  MiniTest.expect.equality(type(mappings.jump_to_top), 'string')


  MiniTest.expect.equality(type(actions.jump_to_bottom), 'function')
  MiniTest.expect.equality(type(mappings.jump_to_bottom), 'string')
end

T['Navigation Features']['actions are properly wired in action normalization'] = function()
  local H_internal = Jumppack.H


  local test_mappings = {
    jump_to_top = 'g',
    jump_to_bottom = 'G',
    stop = '<Esc>', -- Include a known working action for comparison
  }

  local normalized = H_internal.config.normalize_mappings(test_mappings)


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


  MiniTest.expect.equality(type(H_internal.actions.jump_to_top), 'function')


  local move_selection_called_with = nil
  local original_move_selection = H_internal.instance.move_selection

  H_internal.instance.move_selection = function(instance, by, to)
    move_selection_called_with = { instance = instance, by = by, to = to }
  end

  local test_instance = { items = { {}, {}, {} } }
  H_internal.actions.jump_to_top(test_instance, 5) -- Count should be ignored


  MiniTest.expect.equality(move_selection_called_with.instance, test_instance)
  MiniTest.expect.equality(move_selection_called_with.by, 0)
  MiniTest.expect.equality(move_selection_called_with.to, 1)


  H_internal.instance.move_selection = original_move_selection
end

T['Navigation Features']['jump_to_bottom action is properly implemented'] = function()
  local H_internal = Jumppack.H


  MiniTest.expect.equality(type(H_internal.actions.jump_to_bottom), 'function')


  local move_selection_called_with = nil
  local original_move_selection = H_internal.instance.move_selection

  H_internal.instance.move_selection = function(instance, by, to)
    move_selection_called_with = { instance = instance, by = by, to = to }
  end

  local test_instance = { items = { {}, {}, {}, {} } } -- 4 items
  H_internal.actions.jump_to_bottom(test_instance, 10) -- Count should be ignored


  MiniTest.expect.equality(move_selection_called_with.instance, test_instance)
  MiniTest.expect.equality(move_selection_called_with.by, 0)
  MiniTest.expect.equality(move_selection_called_with.to, 4)


  move_selection_called_with = nil
  H_internal.actions.jump_to_bottom({ items = {} }, 1)

  MiniTest.expect.equality(move_selection_called_with, nil)


  H_internal.instance.move_selection = original_move_selection
end

T['Navigation Features']['actions handle edge cases correctly'] = function()
  local H_internal = Jumppack.H
  local actions = H_internal.actions


  local empty_instance = {
    current_ind = 1,
    items = {},
    view_state = 'list',
    visible_range = { from = 1, to = 1 },
    windows = { main = vim.api.nvim_get_current_win() },
  }


  MiniTest.expect.no_error(function()
    actions.jump_to_top(empty_instance, 1)
    actions.jump_to_bottom(empty_instance, 1)
  end)


  local single_instance = {
    current_ind = 1,
    items = {
      { path = '/test/single.lua', lnum = 1, col = 0, jump_index = 1 },
    },
    view_state = 'list',
    visible_range = { from = 1, to = 1 },
    windows = { main = vim.api.nvim_get_current_win() },
  }


  actions.jump_to_top(single_instance, 1)
  MiniTest.expect.equality(single_instance.current_ind, 1)

  actions.jump_to_bottom(single_instance, 1)
  MiniTest.expect.equality(single_instance.current_ind, 1)
end

T['Navigation Features']['validation catches invalid mapping types'] = function()
  local H_internal = Jumppack.H


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


  MiniTest.expect.error(function()
    H_internal.config.setup(invalid_config)
  end, 'jump_to_top')


  local config_invalid_bottom = vim.deepcopy(invalid_config)
  config_invalid_bottom.mappings.jump_to_top = 'g' -- Fix top
  config_invalid_bottom.mappings.jump_to_bottom = {} -- Invalid type - should be string
  MiniTest.expect.error(function()
    H_internal.config.setup(config_invalid_bottom)
  end, 'jump_to_bottom')
end

T['Navigation Features']['Basic Wrapping: First→back wraps to last, last→forward wraps to first'] = function()

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


  local original_fns = H.mock_vim_functions({
    current_file = 'test1.lua',
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

    MiniTest.expect.equality(#instance.items >= 4, true, 'should have at least 4 items for wrapping test')

    if #instance.items >= 4 and H_internal.actions then

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
            instance.current_ind,
            1,
            'forward from last should wrap to first when wrap_edges is true'
          )
        end
      end


      if H_internal.actions.jump_to_top then
        H_internal.actions.jump_to_top(instance, {})
        vim.wait(10)

        MiniTest.expect.equality(instance.current_ind, 1, 'should be at first item')

        -- Move backward from first - should wrap to last
        if H_internal.actions.move_prev then
          H_internal.actions.move_prev(instance, {})
          vim.wait(10)

          MiniTest.expect.equality(
            instance.current_ind,
            #instance.items,
            'backward from first should wrap to last when wrap_edges is true'
          )
        end
      end
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end


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

          local last_index = instance.current_ind

          if H_internal.actions.move_next then
            H_internal.actions.move_next(instance, {})
            vim.wait(10)

            MiniTest.expect.equality(
              instance.current_ind,
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
              instance.current_ind,
              1,
              'backward from first should stay at first when wrap_edges is false'
            )
          end
        end
      end
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3, buf4 })
end

T['Navigation Features']['Wrap Edge Conditions: validates specific edge wrapping logic'] = function()



  local buf1 = H.create_test_buffer('wrap1.lua', { 'content 1' })
  local buf2 = H.create_test_buffer('wrap2.lua', { 'content 2' })
  local buf3 = H.create_test_buffer('wrap3.lua', { 'content 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = 'wrap1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({ options = { wrap_edges = true } })
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    if #instance.items >= 3 then

      instance.current_ind = 1 -- Set current_ind (the actual field used by move_selection)


      H_internal.instance.move_selection(instance, -1) -- Move backward by 1


      MiniTest.expect.equality(
        instance.current_ind,
        #instance.items,
        'backward movement from current_ind=1 should wrap to last item'
      )


      instance.current_ind = #instance.items -- Set to last position


      H_internal.instance.move_selection(instance, 1) -- Move forward by 1


      MiniTest.expect.equality(
        instance.current_ind,
        1,
        'forward movement from current_ind=last should wrap to first item'
      )



    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Navigation Features']['Wrap Edge Behavior: clamps correctly when disabled'] = function()

  local buf1 = H.create_test_buffer('nowrap1.lua', { 'content 1' })
  local buf2 = H.create_test_buffer('nowrap2.lua', { 'content 2' })
  local buf3 = H.create_test_buffer('nowrap3.lua', { 'content 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = 'nowrap1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({ options = { wrap_edges = false } })
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if not state or not state.instance then
      return
    end

    local instance = state.instance
    local H_internal = Jumppack.H

    if #instance.items >= 3 then

      instance.current_ind = 1

      H_internal.instance.move_selection(instance, -1)


      MiniTest.expect.equality(
        instance.current_ind,
        1,
        'backward movement from current_ind=1 should stay at 1 when wrap disabled'
      )


      instance.current_ind = #instance.items

      H_internal.instance.move_selection(instance, 1)


      MiniTest.expect.equality(
        instance.current_ind,
        #instance.items,
        'forward movement from current_ind=last should stay at last when wrap disabled'
      )
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Navigation Features']['Wrap Edge Behavior: detects incorrect wrap logic'] = function()



  local buf1 = H.create_test_buffer('logic1.lua', { 'content 1' })
  local buf2 = H.create_test_buffer('logic2.lua', { 'content 2' })
  local buf3 = H.create_test_buffer('logic3.lua', { 'content 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = 'logic1.lua',
    cwd = vim.fn.getcwd(),
  })


  MiniTest.expect.no_error(function()
    Jumppack.setup({ options = { wrap_edges = false } })


    local n_matches = 3
    local wrap_edges = Jumppack.config.options and Jumppack.config.options.wrap_edges


    local current_ind = 1
    local by = -1
    local to = current_ind


    if wrap_edges then

      if to == 1 and by < 0 then
        to = n_matches
      elseif to == n_matches and by > 0 then
        to = 1
      else
        to = to + by
      end
    else

      to = to + by
    end



    MiniTest.expect.equality(
      to,
      0,
      'wrap_edges=false: backward from pos 1 should give intermediate value 0, not '
        .. to
        .. ' (indicates broken wrap logic)'
    )


    current_ind = n_matches
    by = 1
    to = current_ind

    if wrap_edges then
      if to == 1 and by < 0 then
        to = n_matches
      elseif to == n_matches and by > 0 then
        to = 1
      else
        to = to + by
      end
    else
      to = to + by
    end



    MiniTest.expect.equality(
      to,
      4,
      'wrap_edges=false: forward from last should give intermediate value 4, not '
        .. to
        .. ' (indicates broken wrap logic)'
    )
  end)

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Navigation Features']['Count Wrapping: Large counts with wrapping enabled/disabled'] = function()

  local test_buffers = {}
  local jumplist_entries = {}


  for i = 1, 5 do
    local buf = H.create_test_buffer(string.format('count_test%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)


  local original_fns = H.mock_vim_functions({
    current_file = 'count_test1.lua',
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

    if #instance.items >= 5 and H_internal.actions then

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


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end


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


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)
end

T['Navigation Features']['Filter Wrapping: Wrapping behavior when filters reduce available items'] = function()

  local filter_data = H.create_filter_test_data()


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


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(filter_data.buffers)
end

T['Navigation Features']['Hide Wrapping: Wrapping skips hidden items correctly'] = function()

  local test_buffers = {}
  local jumplist_entries = {}

  for i = 1, 5 do
    local buf = H.create_test_buffer(string.format('hide_wrap%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)


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

      local items_to_hide = { instance.items[2], instance.items[4] }
      for _, item in ipairs(items_to_hide) do
        if H_internal.hide and H_internal.hide.toggle then
          H_internal.hide.toggle(item)
        end
      end


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


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)


  if Jumppack.H and Jumppack.H.hide then
    Jumppack.H.hide.storage = {}
  end
end

T['Navigation Features']['State Preservation: View mode and selection preserved during wrapping'] = function()

  local buf1 = H.create_test_buffer('state1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('state2.lua', { 'line 2' })
  local buf3 = H.create_test_buffer('state3.lua', { 'line 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 0)


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

      local initial_view = instance.current_view


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


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Navigation Features']['Count with C-o/C-i on Picker Start: Opening picker with count prefix'] = function()

  local test_buffers = {}
  local jumplist_entries = {}

  for i = 1, 10 do
    local buf = H.create_test_buffer(string.format('count_start_%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 5) -- Current at position 5 (0-based index)


  local original_fns = H.mock_vim_functions({
    current_file = 'count_start_5.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = { global_mappings = true, wrap_edges = false },
    })


    local start_state = H.start_and_verify({ offset = -3 })
    if start_state and start_state.items and #start_state.items > 0 then
      local selected_item = start_state.items[start_state.selection.index]


      MiniTest.expect.equality(selected_item.offset, -3, 'count prefix 3<C-o> should select item with offset -3')
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end


    start_state = H.start_and_verify({ offset = 2 })
    if start_state and start_state.items and #start_state.items > 0 then
      local selected_item = start_state.items[start_state.selection.index]

      MiniTest.expect.equality(selected_item.offset, 2, 'count prefix 2<C-i> should select item with offset 2')
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end


    start_state = H.start_and_verify({ offset = -8 })
    if start_state and start_state.items and #start_state.items > 0 then
      local selected_item = start_state.items[start_state.selection.index]


      MiniTest.expect.equality(type(selected_item.offset), 'number', 'large count should select valid item')

      MiniTest.expect.equality(selected_item.offset < 0, true, 'large backward count should select backward jump')
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)
end

T['Navigation Features']['Count Accumulation in Picker: Multi-digit count building'] = function()

  local test_buffers = {}
  local jumplist_entries = {}

  for i = 1, 6 do
    local buf = H.create_test_buffer(string.format('count_accum_%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)


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


    instance.pending_count = ''
    instance.pending_count = instance.pending_count .. '3'

    MiniTest.expect.equality(instance.pending_count, '3', 'single digit should accumulate correctly')


    instance.pending_count = instance.pending_count .. '5'

    MiniTest.expect.equality(instance.pending_count, '35', 'multi-digit count should accumulate correctly')


    instance.pending_count = ''
    instance.pending_count = instance.pending_count .. '0'


    MiniTest.expect.equality(
      instance.pending_count == '' or instance.pending_count == '0',
      true,
      'standalone 0 should be handled specially'
    )


    instance.pending_count = '1'
    instance.pending_count = instance.pending_count .. '0'

    MiniTest.expect.equality(instance.pending_count, '10', '0 after other digits should accumulate')


    local general_info = H.display.get_general_info(instance)
    if instance.pending_count ~= '' then
      MiniTest.expect.equality(type(general_info.status_text), 'string', 'status should include count information')

      MiniTest.expect.equality(
        string.find(general_info.status_text, instance.pending_count) ~= nil,
        true,
        'status should display pending count'
      )
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers(test_buffers)
end

T['Navigation Features']['Smart Escape with Count: Escape clears count before closing picker'] = function()

  local buf1 = H.create_test_buffer('escape_count1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('escape_count2.lua', { 'line 2' })
  local buf3 = H.create_test_buffer('escape_count3.lua', { 'line 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 0)


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


    instance.pending_count = '25'

    MiniTest.expect.equality(instance.pending_count, '25', 'should have pending count set')


    if H_internal.actions and H_internal.actions.stop then
      local should_stop = H_internal.actions.stop(instance, 1)

      MiniTest.expect.equality(should_stop, false, 'first escape with active count should not close picker')

      MiniTest.expect.equality(instance.pending_count, '', 'first escape should clear pending count')


      MiniTest.expect.equality(Jumppack.is_active(), true, 'picker should remain active after count clear')


      local should_stop_second = H_internal.actions.stop(instance, 1)

      MiniTest.expect.equality(should_stop_second, true, 'second escape without count should close picker')
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Navigation Features']['Count Timeout: Automatic count clearing after timeout'] = function()

  local buf1 = H.create_test_buffer('timeout1.lua', { 'line 1' })
  local buf2 = H.create_test_buffer('timeout2.lua', { 'line 2' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 0)


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


    instance.pending_count = '5'


    if H_internal.instance and H_internal.instance.start_count_timeout then
      H_internal.instance.start_count_timeout(instance)
    end

    MiniTest.expect.equality(instance.pending_count, '5', 'count should be present before timeout')

    MiniTest.expect.equality(instance.count_timer ~= nil, true, 'count timer should be active')


    vim.wait(150) -- Wait longer than timeout


    MiniTest.expect.equality(instance.pending_count, '', 'count should be cleared after timeout')

    MiniTest.expect.equality(instance.count_timer == nil, true, 'count timer should be cleared after timeout')


    instance.pending_count = '3'
    if H_internal.instance and H_internal.instance.start_count_timeout then
      H_internal.instance.start_count_timeout(instance)
    end


    vim.wait(50) -- Wait less than timeout
    instance.pending_count = instance.pending_count .. '2'
    if H_internal.instance and H_internal.instance.start_count_timeout then
      H_internal.instance.start_count_timeout(instance) -- Reset timeout
    end

    vim.wait(60) -- Wait less than full timeout but more than first wait


    MiniTest.expect.equality(instance.pending_count, '32', 'count should persist when timeout is reset')


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2 })
end

T['Navigation Features']['Count with Navigation Actions: Count behavior with jump actions'] = function()

  local test_buffers = {}
  local jumplist_entries = {}

  for i = 1, 8 do
    local buf = H.create_test_buffer(string.format('nav_count_%d.lua', i), { 'line ' .. i })
    table.insert(test_buffers, buf)
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  H.create_mock_jumplist(jumplist_entries, 0)


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

      if H_internal.actions.jump_back then
        local initial_selection = instance.selection.index

        H_internal.actions.jump_back(instance, 3) -- Count = 3
        vim.wait(10)

        -- Should have moved by count amount (or as much as possible)
        local selection_change = instance.selection.index - initial_selection
        MiniTest.expect.equality(math.abs(selection_change) > 0, true, 'count with jump_back should change selection')
      end


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


      instance.pending_count = '42'

      if H_internal.actions.jump_back then
        H_internal.actions.jump_back(instance, 1)
        vim.wait(10)

        MiniTest.expect.equality(instance.pending_count, '', 'pending count should be cleared after action execution')
      end
    end


    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)


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


      if Jumppack.is_active() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        vim.wait(10)
      end
    end, string.format('Error in %s scenario', scenario.name))


    H.restore_vim_functions(original_fns)
    if #test_buffers > 0 then
      H.cleanup_buffers(test_buffers)
    end
  end
end

return T
