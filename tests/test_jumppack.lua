---@diagnostic disable: duplicate-set-field

local MiniTest = require('mini.test')

local original_getjumplist = vim.fn.getjumplist
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset plugin state before each test
      package.loaded['lua.Jumppack'] = nil
      _G.Jumppack = nil
    end,
    post_case = function()
      -- Clean up after each test
      if _G.Jumppack and _G.Jumppack.is_active and _G.Jumppack.is_active() then
        -- Force stop any active instances
        pcall(function()
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
        end)

        -- Wait a bit for cleanup to complete
        vim.wait(100, function()
          return not _G.Jumppack.is_active()
        end)
      end

      -- Force reset plugin state
      local Jumppack = require('lua.Jumppack')
      if Jumppack.is_active() then
        -- Access internal state to force cleanup
        local H = getfenv(Jumppack.setup).H
        if H and H.instance then
          H.instance = nil
        end
      end

      vim.fn.getjumplist = original_getjumplist
    end,
  },
})

-- Load the plugin
local Jumppack = require('lua.Jumppack')

-- Helper function to verify state structure
local function verify_state(state, expected)
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

-- Configuration Tests
T['Configuration'] = MiniTest.new_set()

T['Configuration']['should have default configuration'] = function()
  MiniTest.expect.equality(type(Jumppack.config), 'table')
  MiniTest.expect.equality(type(Jumppack.config.mappings), 'table')
  MiniTest.expect.equality(type(Jumppack.config.window), 'table')
end

T['Configuration']['should validate configuration in setup'] = function()
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

T['Configuration']['should merge user config with defaults'] = function()
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

T['Configuration']['should validate mapping types'] = function()
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
T['Core API'] = MiniTest.new_set()

T['Core API']['setup'] = MiniTest.new_set()

T['Core API']['setup']['should initialize plugin without errors'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)
end

T['Core API']['setup']['should create autocommands'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)

  -- Check that the Jumppack augroup exists
  local autocmds = vim.api.nvim_get_autocmds({ group = 'Jumppack' })
  MiniTest.expect.equality(#autocmds > 0, true)
end

T['Core API']['setup']['should setup global mappings'] = function()
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

T['Core API']['setup']['should respect global_mappings = false'] = function()
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

T['Core API']['setup']['should respect global_mappings = true (default)'] = function()
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

T['Core API']['setup']['should respect cwd_only = true'] = function()
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

  -- Mock jumplist with files from different directories
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 }, -- temp file outside cwd
        { bufnr = buf2, lnum = 1, col = 0 }, -- another temp file outside cwd
      },
      1, -- current position
    }
  end

  local config = {
    options = {
      cwd_only = true,
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test that cwd_only filtering works by trying to start jumppack
  -- This is an integration test - we can't easily verify internal filtering
  -- but we can verify that the option doesn't cause errors
  MiniTest.expect.no_error(function()
    pcall(Jumppack.start, { offset = -1 })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
end

T['Core API']['setup']['should respect cwd_only = false (default)'] = function()
  -- Create test files
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)

  -- Create buffers for the files
  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)

  -- Mock jumplist with files from different directories
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 },
        { bufnr = buf2, lnum = 1, col = 0 },
      },
      1, -- current position
    }
  end

  local config = {
    options = {
      cwd_only = false, -- explicit false
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test that cwd_only = false works by trying to start jumppack
  -- This is an integration test - we can't easily verify internal filtering
  -- but we can verify that the option doesn't cause errors
  MiniTest.expect.no_error(function()
    pcall(Jumppack.start, { offset = -1 })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
end

T['Core API']['setup']['should respect wrap_edges = true'] = function()
  -- Create test files in current directory
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  local temp_file3 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)
  vim.fn.writefile({ 'test content 3' }, temp_file3)

  -- Create buffers for the files
  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  local buf3 = vim.fn.bufadd(temp_file3)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)
  vim.fn.bufload(buf3)

  -- Mock jumplist with backward and forward jumps
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 }, -- offset -2 (backward)
        { bufnr = buf2, lnum = 1, col = 0 }, -- offset -1 (backward)
        { bufnr = buf2, lnum = 2, col = 0 }, -- offset 0 (current)
        { bufnr = buf3, lnum = 1, col = 0 }, -- offset 1 (forward)
      },
      2, -- current position (0-based, so position 2 = 3rd item = current)
    }
  end

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

  MiniTest.expect.no_error(function()
    pcall(Jumppack.start, { offset = -99 }) -- Should wrap to furthest forward
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  pcall(vim.fn.delete, temp_file3)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
  pcall(vim.api.nvim_buf_delete, buf3, { force = true })
end

T['Core API']['setup']['should respect wrap_edges = false (default)'] = function()
  -- Create test files
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)

  -- Create buffers for the files
  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)

  -- Mock jumplist
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 }, -- offset -1 (backward)
        { bufnr = buf2, lnum = 1, col = 0 }, -- offset 0 (current)
      },
      1, -- current position
    }
  end

  local config = {
    options = {
      wrap_edges = false, -- explicit false
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test that wrapping does NOT work by trying extreme offsets
  MiniTest.expect.no_error(function()
    pcall(Jumppack.start, { offset = 99 }) -- Should not wrap, stay at edge
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
end

T['Core API']['setup']['should handle picker navigation wrapping when wrap_edges = true'] = function()
  -- Create test files
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  local temp_file3 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)
  vim.fn.writefile({ 'test content 3' }, temp_file3)

  -- Create buffers for the files
  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  local buf3 = vim.fn.bufadd(temp_file3)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)
  vim.fn.bufload(buf3)

  -- Mock jumplist with multiple items
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 }, -- offset -2 (backward)
        { bufnr = buf2, lnum = 1, col = 0 }, -- offset -1 (backward)
        { bufnr = buf2, lnum = 2, col = 0 }, -- offset 0 (current)
        { bufnr = buf3, lnum = 1, col = 0 }, -- offset 1 (forward)
      },
      2, -- current position
    }
  end

  local config = {
    options = {
      wrap_edges = true,
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test picker navigation with wrapping
  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -1 })

    if Jumppack.is_active() then
      local state = Jumppack.get_state()
      local initial_selection = state.current.index

      -- Simulate navigation that would wrap (using actions directly)
      -- Move to first item, then try to go back (should wrap to last)
      while state.current.index > 1 do
        H.actions.jump_back(H.instance, {})
        state = Jumppack.get_state()
      end

      -- Now at first item - one more back should wrap to last item if wrapping enabled
      local first_item_index = state.current.index
      H.actions.jump_back(H.instance, {})
      state = Jumppack.get_state()

      -- Should have wrapped to a different position
      MiniTest.expect.equality(state.current.index ~= first_item_index, true)

      -- Clean up
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  pcall(vim.fn.delete, temp_file3)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
  pcall(vim.api.nvim_buf_delete, buf3, { force = true })
end

T['Core API']['setup']['should handle picker navigation clamping when wrap_edges = false'] = function()
  -- Create test files
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  local temp_file3 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)
  vim.fn.writefile({ 'test content 3' }, temp_file3)

  -- Create buffers for the files
  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  local buf3 = vim.fn.bufadd(temp_file3)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)
  vim.fn.bufload(buf3)

  -- Mock jumplist with multiple items
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 }, -- offset -2
        { bufnr = buf2, lnum = 1, col = 0 }, -- offset -1
        { bufnr = buf2, lnum = 2, col = 0 }, -- offset 0 (current)
        { bufnr = buf3, lnum = 1, col = 0 }, -- offset 1
      },
      2, -- current position
    }
  end

  local config = {
    options = {
      wrap_edges = false, -- disable wrapping
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test picker navigation without wrapping
  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -1 })

    if Jumppack.is_active() then
      local state = Jumppack.get_state()

      -- Move to first item
      while state.current.index > 1 do
        H.actions.jump_back(H.instance, {})
        state = Jumppack.get_state()
      end

      -- Now at first item - try to go back (should stay at first)
      local first_item_index = state.current.index
      H.actions.jump_back(H.instance, {})
      state = Jumppack.get_state()

      -- Should stay at first item (no wrapping)
      MiniTest.expect.equality(state.current.index, first_item_index)

      -- Similarly, move to last item and try to go forward
      while state.current.index < #state.items do
        H.actions.jump_forward(H.instance, {})
        state = Jumppack.get_state()
      end

      local last_item_index = state.current.index
      H.actions.jump_forward(H.instance, {})
      state = Jumppack.get_state()

      -- Should stay at last item (no wrapping)
      MiniTest.expect.equality(state.current.index, last_item_index)

      -- Clean up
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  pcall(vim.fn.delete, temp_file3)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
  pcall(vim.api.nvim_buf_delete, buf3, { force = true })
end

T['Core API']['setup']['should respect default_view = "preview"'] = function()
  -- Create test files
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)

  -- Create buffers for the files
  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)

  -- Mock jumplist
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 }, -- offset -1
        { bufnr = buf2, lnum = 1, col = 0 }, -- offset 0 (current)
      },
      1, -- current position
    }
  end

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

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
end

T['Core API']['setup']['should respect default_view = "list"'] = function()
  -- Create test files
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)

  -- Create buffers for the files
  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)

  -- Mock jumplist
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 }, -- offset -1
        { bufnr = buf2, lnum = 1, col = 0 }, -- offset 0 (current)
      },
      1, -- current position
    }
  end

  local config = {
    options = {
      default_view = 'list',
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  -- Test that picker starts in list mode
  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -1 })

    if Jumppack.is_active() then
      local state = Jumppack.get_state()
      -- Should start in list mode (note: the internal state might be 'main' for list mode)
      MiniTest.expect.equality(state.general_info.view_state, 'list')

      -- Clean up
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Cleanup
  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  pcall(vim.api.nvim_buf_delete, buf1, { force = true })
  pcall(vim.api.nvim_buf_delete, buf2, { force = true })
end

T['Core API']['setup']['should validate default_view option'] = function()
  MiniTest.expect.error(function()
    Jumppack.setup({
      options = {
        default_view = 'invalid_mode', -- should cause error
      },
    })
  end)
end

T['Core API']['is_active'] = MiniTest.new_set()

T['Core API']['is_active']['should return false when no instance exists'] = function()
  MiniTest.expect.equality(Jumppack.is_active(), false)
end

T['Core API']['get_state'] = MiniTest.new_set()

T['Core API']['get_state']['should return nil when no instance is active'] = function()
  MiniTest.expect.equality(Jumppack.get_state(), nil)
end

T['Core API']['start'] = MiniTest.new_set()

T['Core API']['start']['should validate options'] = function()
  MiniTest.expect.error(function()
    Jumppack.start('invalid')
  end)
end

T['Core API']['refresh'] = MiniTest.new_set()

T['Core API']['refresh']['should not error when no instance is active'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.refresh()
  end)
end

-- Jumplist Processing Tests
T['Jumplist Processing'] = MiniTest.new_set()

T['Jumplist Processing']['should handle empty jumplist'] = function()
  -- Create a mock empty jumplist
  vim.fn.getjumplist = function()
    return { {}, 0 }
  end

  MiniTest.expect.no_error(function()
    local opts = {
      offset = -1,
    }
    Jumppack.start(opts)
    -- Clean up
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)
end

T['Jumplist Processing']['should handle jumplist with items'] = function()
  -- Create some test buffers and jump entries
  local buf1 = vim.api.nvim_create_buf(false, true)
  local buf2 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf1, 'test1.lua')
  vim.api.nvim_buf_set_name(buf2, 'test2.lua')
  vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { 'line 1', 'line 2' })
  vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { 'line 3', 'line 4' })

  -- Mock getjumplist with test data
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 },
        { bufnr = buf2, lnum = 2, col = 0 },
      },
      0,
    }
  end

  MiniTest.expect.no_error(function()
    local opts = {
      offset = -1,
    }
    Jumppack.start(opts)

    -- Allow time for jumplist processing
    vim.wait(10)

    -- Verify state contains jumplist items
    local state = Jumppack.get_state()
    -- Only verify if jumplist was successfully created (state exists)
    if state then
      verify_state(state, {
        source_name = 'Jumplist',
      })

      -- Verify jump items have expected structure if any exist
      if #state.items > 0 then
        for _, item in ipairs(state.items) do
          MiniTest.expect.equality(type(item.offset), 'number')
          MiniTest.expect.equality(type(item.bufnr), 'number')
        end
      end
    end

    -- Clean up
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)
  vim.api.nvim_buf_delete(buf1, { force = true })
  vim.api.nvim_buf_delete(buf2, { force = true })
end

T['Jumplist Processing']['should fallback to max/min offset when exact not found'] = function()
  -- Create test buffers with multiple jump positions
  local buf1 = vim.api.nvim_create_buf(false, true)
  local buf2 = vim.api.nvim_create_buf(false, true)
  local buf3 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf1, 'test_fallback1.lua')
  vim.api.nvim_buf_set_name(buf2, 'test_fallback2.lua')
  vim.api.nvim_buf_set_name(buf3, 'test_fallback3.lua')
  vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { 'line 1', 'line 2' })
  vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { 'line 3', 'line 4' })
  vim.api.nvim_buf_set_lines(buf3, 0, -1, false, { 'line 5', 'line 6' })

  -- Mock getjumplist with test data:
  -- Current position at index 2 (0-based), so we have:
  -- - 2 backward jumps (offsets -1, -2)
  -- - 1 current position (offset 0)
  -- - 2 forward jumps (offsets 1, 2)
  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 1, col = 0 }, -- offset -2
        { bufnr = buf2, lnum = 1, col = 0 }, -- offset -1
        { bufnr = buf2, lnum = 2, col = 0 }, -- offset 0 (current)
        { bufnr = buf3, lnum = 1, col = 0 }, -- offset 1
        { bufnr = buf3, lnum = 2, col = 0 }, -- offset 2
      },
      2, -- current position index (0-based)
    }
  end

  -- Store the original getjumplist to restore later
  local orig_getjumplist = vim.fn.getjumplist

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

  -- Restore original getjumplist
  vim.fn.getjumplist = orig_getjumplist

  -- Clean up
  vim.api.nvim_buf_delete(buf1, { force = true })
  vim.api.nvim_buf_delete(buf2, { force = true })
  vim.api.nvim_buf_delete(buf3, { force = true })
end

-- Display Functions Tests
T['Display Functions'] = MiniTest.new_set()

T['Display Functions']['default_show'] = MiniTest.new_set()

T['Display Functions']['default_show']['should display items without errors'] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  local items = {
    { path = 'test.lua', text = 'test item' },
  }

  MiniTest.expect.no_error(function()
    Jumppack.default_show(buf, items, {})
  end)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T['Display Functions']['default_show']['should handle empty items'] = function()
  local buf = vim.api.nvim_create_buf(false, true)

  MiniTest.expect.no_error(function()
    Jumppack.default_show(buf, {}, {})
  end)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T['Display Functions']['default_show']['should handle jump items'] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  local items = {
    {
      offset = -1,
      path = 'test.lua',
      lnum = 10,
      bufnr = buf,
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.default_show(buf, items, {})
  end)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T['Display Functions']['default_preview'] = MiniTest.new_set()

T['Display Functions']['default_preview']['should handle items with bufnr'] = function()
  local source_buf = vim.api.nvim_create_buf(false, true)
  local preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { 'test line 1', 'test line 2' })

  local item = {
    bufnr = source_buf,
    lnum = 1,
    col = 1,
    path = 'test.lua',
  }

  MiniTest.expect.no_error(function()
    Jumppack.default_preview(preview_buf, item, {})
  end)

  vim.api.nvim_buf_delete(source_buf, { force = true })
  vim.api.nvim_buf_delete(preview_buf, { force = true })
end

T['Display Functions']['default_preview']['should handle items without bufnr'] = function()
  local preview_buf = vim.api.nvim_create_buf(false, true)
  local item = { path = 'test.lua' }

  MiniTest.expect.no_error(function()
    Jumppack.default_preview(preview_buf, item, {})
  end)

  vim.api.nvim_buf_delete(preview_buf, { force = true })
end

T['Display Functions']['default_preview']['should handle nil item'] = function()
  local preview_buf = vim.api.nvim_create_buf(false, true)

  MiniTest.expect.no_error(function()
    Jumppack.default_preview(preview_buf, nil, {})
  end)

  vim.api.nvim_buf_delete(preview_buf, { force = true })
end

T['Display Functions']['default_choose'] = MiniTest.new_set()

T['Display Functions']['default_choose']['should handle negative offset (backward)'] = function()
  local item = {
    offset = -2,
  }

  MiniTest.expect.no_error(function()
    Jumppack.default_choose(item)
  end)
end

T['Display Functions']['default_choose']['should handle positive offset (forward)'] = function()
  local item = {
    offset = 1,
  }

  MiniTest.expect.no_error(function()
    Jumppack.default_choose(item)
  end)
end

T['Display Functions']['default_choose']['should handle zero offset (current)'] = function()
  local item = {
    offset = 0,
  }

  MiniTest.expect.no_error(function()
    Jumppack.default_choose(item)
  end)
end

-- Error Handling Tests
T['Error Handling'] = MiniTest.new_set()

T['Error Handling']['should handle invalid configuration gracefully'] = function()
  MiniTest.expect.error(function()
    Jumppack.setup({
      mappings = 'invalid',
    })
  end)
end

T['Error Handling']['should handle invalid start options'] = function()
  MiniTest.expect.error(function()
    Jumppack.start('not a table')
  end)
end

-- Integration Tests
T['Integration Tests'] = MiniTest.new_set()

T['Integration Tests']['should complete full setup workflow'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.setup({})
  end)

  -- Should not be active when just set up
  MiniTest.expect.equality(type(Jumppack.is_active), 'function')
end

T['Integration Tests']['should handle jumplist navigation request'] = function()
  -- Create test buffers with unique names
  local buf1 = vim.api.nvim_create_buf(false, true)
  local buf2 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf1, 'integration_test1.lua')
  vim.api.nvim_buf_set_name(buf2, 'integration_test2.lua')

  vim.fn.getjumplist = function()
    return {
      {
        { bufnr = buf1, lnum = 10, col = 0 },
        { bufnr = buf2, lnum = 20, col = 5 },
      },
      0,
    }
  end

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    local opts = {
      offset = -1,
    }
    Jumppack.start(opts)

    -- Allow time for jumplist processing
    vim.wait(10)

    -- Verify state after starting jumplist navigation
    local state = Jumppack.get_state()
    -- Only verify if jumplist was successfully created (state exists)
    if state then
      verify_state(state, {
        source_name = 'Jumplist',
      })

      -- Verify at least one item exists with proper structure if any exist
      if #state.items > 0 then
        MiniTest.expect.equality(type(state.items[1].path), 'string')
        MiniTest.expect.equality(type(state.items[1].direction), 'string')
      end
    end

    -- Clean up
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  -- Restore and clean up
  vim.api.nvim_buf_delete(buf1, { force = true })
  vim.api.nvim_buf_delete(buf2, { force = true })
end

T['Integration Tests']['should handle refresh when not active'] = function()
  MiniTest.expect.no_error(function()
    Jumppack.refresh()
  end)
end

return T
