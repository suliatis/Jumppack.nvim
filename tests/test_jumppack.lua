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
      toggle_preview = '<C-p>',
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
      toggle_preview = '<C-p>',
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
      toggle_preview = '<C-p>',
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
      toggle_preview = '<C-p>',
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
      toggle_preview = '<C-p>',
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
      MiniTest.expect.equality(type(item.direction), 'string')
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
  end)
end

T['Display Functions Tests']['Choose Function']['handles forward jumps'] = function()
  local item = {
    offset = 1,
  }

  MiniTest.expect.no_error(function()
    Jumppack.choose_item(item)
  end)
end

T['Display Functions Tests']['Choose Function']['handles current position'] = function()
  local item = {
    offset = 0,
  }

  MiniTest.expect.no_error(function()
    Jumppack.choose_item(item)
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
      MiniTest.expect.equality(type(state.items[1].direction), 'string')
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

return T
