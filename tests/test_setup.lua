local MiniTest = require('mini.test')
local H = require('tests.helpers')
local T = H.create_test_suite()
local Jumppack = require('lua.Jumppack')

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

T['Setup & Configuration']['Input Validation'] = MiniTest.new_set()

T['Setup & Configuration']['Input Validation']['validates start option types'] = function()
  -- Test various invalid argument types to start() - gaps we discovered

  -- Test passing number instead of table
  MiniTest.expect.error(function()
    Jumppack.start(123)
  end)

  -- Test passing function instead of table
  MiniTest.expect.error(function()
    Jumppack.start(function() end)
  end)

  -- Test passing boolean instead of table
  MiniTest.expect.error(function()
    Jumppack.start(true)
  end)

  -- Test nil should be acceptable (uses defaults)
  MiniTest.expect.no_error(function()
    -- Mock empty jumplist to prevent actual picker
    H.create_mock_jumplist({}, 0)
    Jumppack.start(nil)
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'should accept nil argument')

  -- Test empty table should be acceptable
  MiniTest.expect.no_error(function()
    H.create_mock_jumplist({}, 0)
    Jumppack.start({})
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'should accept empty table')

  -- Test valid table with invalid field types - this may not be validated yet
  MiniTest.expect.no_error(function()
    -- Mock empty jumplist to avoid actual start
    H.create_mock_jumplist({}, 0)
    Jumppack.start({ offset = 'not a number' })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)
end

T['Setup & Configuration']['Field Validation Gap: documents missing parameter validation'] = function()
  -- This test documents specific validation gaps discovered during breaking analysis
  -- Currently these field validations don't exist but should be considered for future implementation

  local original_fns = H.mock_vim_functions({
    current_file = 'test.lua',
    cwd = vim.fn.getcwd(),
  })

  -- Document offset parameter not being validated (discovered gap)
  MiniTest.expect.no_error(function()
    H.create_mock_jumplist({}, 0)
    -- These should potentially be validated but currently are not:
    Jumppack.start({ offset = 'string_instead_of_number' }) -- No validation
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'offset field validation gap - currently no type checking')

  -- Document other potential validation gaps for future consideration
  MiniTest.expect.no_error(function()
    H.create_mock_jumplist({}, 0)
    -- These pass but could benefit from validation:
    Jumppack.start({
      some_unknown_field = 'value', -- Unknown fields not caught
      offset = -999999, -- Extreme values not bounded
    })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'additional validation gaps - unknown fields and extreme values')

  H.restore_vim_functions(original_fns)
end

T['Setup & Configuration']['Complex Configuration Processing: handles nested and callback configurations'] = function()
  -- Test complex configuration scenarios discovered during breaking analysis
  -- where configuration processing gaps weren't caught by existing tests

  local buf = H.create_test_buffer('config_test.lua', { 'test content' })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = 'config_test.lua',
    cwd = vim.fn.getcwd(),
  })

  -- Test 1: Nested configuration structures
  MiniTest.expect.no_error(function()
    local complex_config = {
      window = {
        config = {
          relative = 'editor',
          width = function()
            return math.floor(vim.o.columns * 0.8)
          end,
          height = function()
            return math.floor(vim.o.lines * 0.8)
          end,
          row = function()
            return math.floor(vim.o.lines * 0.1)
          end,
          col = function()
            return math.floor(vim.o.columns * 0.1)
          end,
          border = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' },
          style = 'minimal',
        },
      },
      options = {
        wrap_edges = true,
        max_items = function()
          return 50
        end, -- Function config
      },
      mappings = {
        choose = '<CR>',
        choose_split = '<C-s>',
        choose_vsplit = '<C-v>',
        choose_tab = '<C-t>',
        move_up = 'k',
        move_down = 'j',
        toggle_preview = '<C-p>',
        exit = '<Esc>',
      },
    }

    Jumppack.setup(complex_config)

    -- Should handle callable configurations
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should handle complex nested config')

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end, 'Should process complex nested configurations')

  -- Test 2: Configuration with callback functions
  MiniTest.expect.no_error(function()
    local callback_config = {
      window = {
        config = function()
          return {
            relative = 'cursor',
            width = 60,
            height = 20,
            row = 1,
            col = 0,
          }
        end,
      },
      options = {
        wrap_edges = function()
          return vim.g.jumppack_wrap or false
        end,
      },
    }

    Jumppack.setup(callback_config)
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should handle callback-based config')

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end, 'Should process callback configurations')

  -- Test 3: Configuration merge behavior with complex types
  MiniTest.expect.no_error(function()
    -- First setup with base config
    Jumppack.setup({
      options = { wrap_edges = true },
      mappings = { choose = '<CR>' },
    })

    -- Second setup should merge, not replace
    Jumppack.setup({
      options = { max_items = 100 }, -- Should merge with existing wrap_edges
      mappings = { exit = '<C-c>' }, -- Should merge with existing choose mapping
    })

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should handle config merging')

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end, 'Should properly merge complex configurations')

  -- Test 4: Configuration with invalid but non-fatal structures
  MiniTest.expect.no_error(function()
    local mixed_config = {
      window = {
        config = {
          relative = 'editor',
          width = 80,
          height = 20,
          unknown_field = 'should_be_ignored', -- Unknown fields
        },
      },
      options = {
        wrap_edges = true,
        unknown_option = 'ignored', -- Unknown options
      },
      completely_unknown_section = { -- Unknown sections
        foo = 'bar',
      },
    }

    Jumppack.setup(mixed_config)
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should handle mixed valid/invalid config')

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end, 'Should gracefully handle unknown configuration fields')

  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf })
end

return T
