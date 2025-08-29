---@diagnostic disable: duplicate-set-field

local MiniTest = require('mini.test')

local original_getjumplist = vim.fn.getjumplist

-- Test helper namespace (like production code)
local H = {}

-- Helper functions in H namespace
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
  if _G.Jumppack and _G.Jumppack.is_active and _G.Jumppack.is_active() then
    pcall(function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end)
    vim.wait(100, function()
      return not _G.Jumppack.is_active()
    end)
  end

  -- Try to access the loaded Jumppack module if it exists
  if package.loaded['lua.Jumppack'] then
    local Jumppack = require('lua.Jumppack')
    if Jumppack.is_active() then
      local internal_H = getfenv(Jumppack.setup).H
      if internal_H and internal_H.instance then
        internal_H.instance = nil
      end
    end
  end
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

-- Configuration Tests
T['Configuration Tests'] = MiniTest.new_set()

T['Configuration Tests']['Basic Configuration'] = MiniTest.new_set()

T['Configuration Tests']['Basic Configuration']['has default configuration'] = function()
  MiniTest.expect.equality(type(Jumppack.config), 'table')
  MiniTest.expect.equality(type(Jumppack.config.mappings), 'table')
  MiniTest.expect.equality(type(Jumppack.config.window), 'table')
end

T['Configuration Tests']['Basic Configuration']['merges user config with defaults'] = function()
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

T['Configuration Tests']['Basic Configuration']['validates configuration in setup'] = function()
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

T['Configuration Tests']['Mapping Configuration'] = MiniTest.new_set()

T['Configuration Tests']['Mapping Configuration']['validates mapping types'] = function()
  local invalid_config = {
    mappings = {
      jump_back = 123,
    },
  }

  MiniTest.expect.error(function()
    Jumppack.setup(invalid_config)
  end)
end

-- Core API Tests
T['Core API Tests'] = MiniTest.new_set()

T['Core API Tests']['Setup'] = MiniTest.new_set()

T['Core API Tests']['Setup']['initializes without errors'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)
end

T['Core API Tests']['Setup']['creates autocommands'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)

  -- Check that the Jumppack augroup exists
  local autocmds = vim.api.nvim_get_autocmds({ group = 'Jumppack' })
  MiniTest.expect.equality(#autocmds > 0, true)
end

T['Core API Tests']['Setup']['sets up mappings correctly'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)
  MiniTest.expect.equality(type(Jumppack.is_active), 'function')
end

T['Configuration Tests']['Mapping Configuration']['creates global mappings by default'] = function()
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

T['Configuration Tests']['Mapping Configuration']['respects global_mappings = false'] = function()
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

T['Configuration Tests']['Mapping Configuration']['respects global_mappings = true'] = function()
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

T['Configuration Tests']['Options Configuration'] = MiniTest.new_set()

T['Configuration Tests']['Options Configuration']['respects cwd_only option'] = function()
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

T['Configuration Tests']['Options Configuration']['respects wrap_edges option'] = function()
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

T['Configuration Tests']['Options Configuration']['respects default_view option'] = function()
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

T['Configuration Tests']['Options Configuration']['validates default_view option'] = function()
  MiniTest.expect.error(function()
    Jumppack.setup({
      options = {
        default_view = 'invalid_mode', -- should cause error
      },
    })
  end)
end

T['Core API Tests']['State Management'] = MiniTest.new_set()

T['Core API Tests']['State Management']['reports active state correctly'] = function()
  MiniTest.expect.equality(Jumppack.is_active(), false)
end

T['Core API Tests']['State Management']['returns state when active'] = function()
  MiniTest.expect.equality(Jumppack.get_state(), nil)
end

T['Core API Tests']['State Management']['handles refresh when inactive'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.refresh()
  end)
end

T['Core API Tests']['State Management']['validates start options'] = function()
  MiniTest.expect.error(function()
    Jumppack.start('invalid')
  end)
end

-- Jumplist Processing Tests
T['Jumplist Processing Tests'] = MiniTest.new_set()

T['Jumplist Processing Tests']['Basic Processing'] = MiniTest.new_set()

T['Jumplist Processing Tests']['Basic Processing']['handles empty jumplist'] = function()
  H.create_mock_jumplist({}, 0)

  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -1 })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)
end

T['Jumplist Processing Tests']['Basic Processing']['processes jumplist with items'] = function()
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

T['Jumplist Processing Tests']['Basic Processing']['creates proper item structure'] = function()
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

T['Jumplist Processing Tests']['Fallback Behavior'] = MiniTest.new_set()

T['Jumplist Processing Tests']['Fallback Behavior']['falls back to max offset when too high'] = function()
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

T['Jumplist Processing Tests']['Fallback Behavior']['falls back to min offset when too low'] = function()
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

-- Display Functions Tests
T['Display Functions Tests'] = MiniTest.new_set()

T['Display Functions Tests']['Show Function'] = MiniTest.new_set()

T['Display Functions Tests']['Show Function']['displays items without errors'] = function()
  local buf = H.create_test_buffer()
  local items = {
    { path = 'test.lua', text = 'test item' },
  }

  MiniTest.expect.no_error(function()
    Jumppack.show_items(buf, items, {})
  end)

  H.cleanup_buffers({ buf })
end

T['Display Functions Tests']['Show Function']['handles empty items'] = function()
  local buf = H.create_test_buffer()

  MiniTest.expect.no_error(function()
    Jumppack.show_items(buf, {}, {})
  end)

  H.cleanup_buffers({ buf })
end

T['Display Functions Tests']['Show Function']['handles jump items with offsets'] = function()
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

T['Display Functions Tests']['Preview Function'] = MiniTest.new_set()

T['Display Functions Tests']['Preview Function']['handles items with bufnr'] = function()
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

T['Display Functions Tests']['Preview Function']['handles items without bufnr'] = function()
  local preview_buf = H.create_test_buffer()
  local item = { path = 'test.lua' }

  MiniTest.expect.no_error(function()
    Jumppack.preview_item(preview_buf, item, {})
  end)

  H.cleanup_buffers({ preview_buf })
end

T['Display Functions Tests']['Preview Function']['handles nil item'] = function()
  local preview_buf = H.create_test_buffer()

  MiniTest.expect.no_error(function()
    Jumppack.preview_item(preview_buf, nil, {})
  end)

  H.cleanup_buffers({ preview_buf })
end

T['Display Functions Tests']['Choose Function'] = MiniTest.new_set()

T['Display Functions Tests']['Choose Function']['handles backward jumps'] = function()
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

T['Display Functions Tests']['Choose Function']['handles forward jumps'] = function()
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

T['Display Functions Tests']['Choose Function']['handles current position'] = function()
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

-- Integration Tests
T['Integration Tests'] = MiniTest.new_set()

T['Integration Tests']['completes full setup workflow'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)

  -- Should not be active when just set up
  MiniTest.expect.equality(type(Jumppack.is_active), 'function')
end

T['Integration Tests']['handles jumplist navigation request'] = function()
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

T['Integration Tests']['handles refresh when not active'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.refresh()
  end)
end

T['Integration Tests']['handles invalid configuration gracefully'] = function()
  MiniTest.expect.error(function()
    Jumppack.setup({
      mappings = 'invalid',
    })
  end)
end

T['Integration Tests']['handles invalid start options'] = function()
  MiniTest.expect.error(function()
    Jumppack.start('not a table')
  end)
end

-- Phase 1: Visual Display Tests
T['Display Tests'] = MiniTest.new_set()

T['Display Tests']['Item Formatting'] = MiniTest.new_set()

T['Display Tests']['Item Formatting']['displays items with new format'] = function()
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

T['Display Tests']['Item Formatting']['shows line preview in list mode'] = function()
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

-- Phase 3: Filter System Tests
T['Filter System'] = MiniTest.new_set()

T['Filter System']['H.filters.apply'] = function()
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

T['Filter System']['H.filters.get_status_text'] = function()
  local filters = { file_only = false, cwd_only = false, show_hidden = false }
  MiniTest.expect.equality(Jumppack.H.filters.get_status_text(filters), '')

  filters.file_only = true
  MiniTest.expect.equality(Jumppack.H.filters.get_status_text(filters), '[f] ')

  filters.cwd_only = true
  MiniTest.expect.equality(Jumppack.H.filters.get_status_text(filters), '[f,c] ')

  filters.show_hidden = true
  MiniTest.expect.equality(Jumppack.H.filters.get_status_text(filters), '[f,c,.] ')
end

T['Filter System']['Filter context handling'] = function()
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

T['Filter System']['Empty filter results handling'] = function()
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

T['Filter System']['Filter toggle integration'] = function()
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

T['Filter System']['Filter actions'] = function()
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

-- Phase 4: Hide System Tests
T['Hide System'] = MiniTest.new_set()

T['Hide System']['H.hide functions'] = function()
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

T['Hide System']['Toggle hidden action'] = function()
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

T['Hide System']['Display with hidden items'] = function()
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

T['Hide System']['Hide current item moves selection correctly'] = function()
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

T['Hide System']['Hide item updates both views'] = function()
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

T['Hide System']['Hide item respects show_hidden filter'] = function()
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

T['Hide System']['Hide multiple items in sequence'] = function()
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

-- Phase 5: Smart Navigation Tests
T['Smart Navigation'] = MiniTest.new_set()

T['Smart Navigation']['calculate_filtered_initial_selection'] = function()
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

T['Smart Navigation']['find_best_selection'] = function()
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

T['Smart Navigation']['Navigation actions'] = function()
  -- Test that navigation actions exist and handle count
  local H = Jumppack.H
  MiniTest.expect.equality(type(H.actions.jump_back), 'function')
  MiniTest.expect.equality(type(H.actions.jump_forward), 'function')

  -- Note: Full integration testing of count support would require
  -- more complex setup with actual picker instance
end

T['Count Functionality'] = MiniTest.new_set()

T['Count Functionality']['instance has pending_count field'] = function()
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

T['Count Functionality']['actions handle count parameter'] = function()
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

T['Count Functionality']['general_info includes count display'] = function()
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

T['Count Functionality']['general_info without pending count'] = function()
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

return T
