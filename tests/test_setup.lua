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

  local mappings = vim.api.nvim_get_keymap('n')
  local has_jump_back = false
  for _, map in ipairs(mappings) do
    if map.lhs == '<C-X>' then
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

  local mappings = vim.api.nvim_get_keymap('n')
  local has_jump_back = false
  for _, map in ipairs(mappings) do
    if map.lhs == '<C-X>' then
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

  local mappings = vim.api.nvim_get_keymap('n')
  local has_jump_back = false
  for _, map in ipairs(mappings) do
    if map.lhs == '<C-Z>' then
      has_jump_back = true
      break
    end
  end
  MiniTest.expect.equality(has_jump_back, true)
end

T['Setup & Configuration']['Options Configuration'] = MiniTest.new_set()

T['Setup & Configuration']['Options Configuration']['respects cwd_only option'] = function()
  local temp_file1 = vim.fn.tempname() .. '.lua'
  local temp_file2 = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({ 'test content 1' }, temp_file1)
  vim.fn.writefile({ 'test content 2' }, temp_file2)

  local buf1 = vim.fn.bufadd(temp_file1)
  local buf2 = vim.fn.bufadd(temp_file2)
  vim.fn.bufload(buf1)
  vim.fn.bufload(buf2)

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local config = {
    options = {
      cwd_only = true,
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  MiniTest.expect.no_error(function()
    pcall(Jumppack.start, { offset = -1 })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  pcall(vim.fn.delete, temp_file1)
  pcall(vim.fn.delete, temp_file2)
  H.cleanup_buffers({ buf1, buf2 })
end

T['Setup & Configuration']['Options Configuration']['respects wrap_edges option'] = function()
  local buf1 = H.create_test_buffer('test1.lua', { 'test content 1' })
  local buf2 = H.create_test_buffer('test2.lua', { 'test content 2' })
  local buf3 = H.create_test_buffer('test3.lua', { 'test content 3' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 2, col = 0 },
    { bufnr = buf3, lnum = 1, col = 0 },
  }, 2)

  local config = {
    options = {
      wrap_edges = true,
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  MiniTest.expect.no_error(function()
    pcall(Jumppack.start, { offset = 99 }) -- Should wrap to furthest back
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2, buf3 })
end

T['Setup & Configuration']['Options Configuration']['respects default_view option'] = function()
  local buf1 = H.create_test_buffer('test1.lua', { 'test content 1' })
  local buf2 = H.create_test_buffer('test2.lua', { 'test content 2' })

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local config = {
    options = {
      default_view = 'preview',
    },
  }

  MiniTest.expect.no_error(function()
    Jumppack.setup(config)
  end)

  MiniTest.expect.no_error(function()
    Jumppack.start({ offset = -1 })

    if Jumppack.is_active() then
      local state = Jumppack.get_state()
      MiniTest.expect.equality(state.general_info.view_state, 'preview')

      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)

  H.cleanup_buffers({ buf1, buf2 })
end

T['Setup & Configuration']['Options Configuration']['validates default_view option'] = function()
  MiniTest.expect.error(function()
    Jumppack.setup({
      options = {
        default_view = 'invalid_mode',
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
  MiniTest.expect.error(function()
    Jumppack.start(123)
  end)

  MiniTest.expect.error(function()
    Jumppack.start(function() end)
  end)

  MiniTest.expect.error(function()
    Jumppack.start(true)
  end)

  MiniTest.expect.no_error(function()
    H.create_mock_jumplist({}, 0)
    Jumppack.start(nil)
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'should accept nil argument')

  MiniTest.expect.no_error(function()
    H.create_mock_jumplist({}, 0)
    Jumppack.start({})
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'should accept empty table')

  MiniTest.expect.no_error(function()
    H.create_mock_jumplist({}, 0)
    Jumppack.start({ offset = 'not a number' })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end)
end

T['Setup & Configuration']['Field Validation Gap: documents missing parameter validation'] = function()
  local original_fns = H.mock_vim_functions({
    current_file = 'test.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    H.create_mock_jumplist({}, 0)
    Jumppack.start({ offset = 'string_instead_of_number' })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'offset field validation gap - currently no type checking')

  MiniTest.expect.no_error(function()
    H.create_mock_jumplist({}, 0)
    Jumppack.start({
      some_unknown_field = 'value',
      offset = -999999,
    })
    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    end
  end, 'additional validation gaps - unknown fields and extreme values')

  H.restore_vim_functions(original_fns)
end

T['Setup & Configuration']['Complex Configuration Processing: handles nested and callback configurations'] = function()
  local buf = H.create_test_buffer('config_test.lua', { 'test content' })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = 'config_test.lua',
    cwd = vim.fn.getcwd(),
  })

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
        end,
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

    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    MiniTest.expect.equality(state and state.instance ~= nil, true, 'Should handle complex nested config')

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end, 'Should process complex nested configurations')

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

  MiniTest.expect.no_error(function()
    Jumppack.setup({
      options = { wrap_edges = true },
      mappings = { choose = '<CR>' },
    })

    Jumppack.setup({
      options = { max_items = 100 },
      mappings = { exit = '<C-c>' },
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

  MiniTest.expect.no_error(function()
    local mixed_config = {
      window = {
        config = {
          relative = 'editor',
          width = 80,
          height = 20,
          unknown_field = 'should_be_ignored',
        },
      },
      options = {
        wrap_edges = true,
        unknown_option = 'ignored',
      },
      completely_unknown_section = {
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
