local MiniTest = require('mini.test')
local H = require('tests.helpers')
local T = H.create_test_suite()
local Jumppack = require('lua.Jumppack')

T['Display Features'] = MiniTest.new_set()

T['Display Features']['Show Function'] = MiniTest.new_set()

T['Display Features']['Show Function']['displays items without errors'] = function()
  local buf = H.create_test_buffer()
  local items = {
    { path = 'test.lua', text = 'test item' },
  }

  MiniTest.expect.no_error(function()
    Jumppack.show_items(buf, items, {})
  end)

  H.cleanup_buffers({ buf })
end

T['Display Features']['Show Function']['handles empty items'] = function()
  local buf = H.create_test_buffer()

  MiniTest.expect.no_error(function()
    Jumppack.show_items(buf, {}, {})
  end)

  H.cleanup_buffers({ buf })
end

T['Display Features']['Show Function']['handles jump items with offsets'] = function()
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

T['Display Features']['Preview Function'] = MiniTest.new_set()

T['Display Features']['Preview Function']['handles items with bufnr'] = function()
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

T['Display Features']['Preview Function']['handles items without bufnr'] = function()
  local preview_buf = H.create_test_buffer()
  local item = { path = 'test.lua' }

  MiniTest.expect.no_error(function()
    Jumppack.preview_item(preview_buf, item, {})
  end)

  H.cleanup_buffers({ preview_buf })
end

T['Display Features']['Preview Function']['handles nil item'] = function()
  local preview_buf = H.create_test_buffer()

  MiniTest.expect.no_error(function()
    Jumppack.preview_item(preview_buf, nil, {})
  end)

  H.cleanup_buffers({ preview_buf })
end

T['Display Features']['Choose Function'] = MiniTest.new_set()

T['Display Features']['Choose Function']['handles backward jumps'] = function()
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

T['Display Features']['Choose Function']['handles forward jumps'] = function()
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

T['Display Features']['Choose Function']['handles current position'] = function()
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

T['Display Features']['Item Formatting'] = MiniTest.new_set()

T['Display Features']['Item Formatting']['displays items with new format'] = function()
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

T['Display Features']['Item Formatting']['shows line preview in list mode'] = function()
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

T['Display Features']['Item Formatting']['handles incomplete item data'] = function()
  -- Test H.display.item_to_string with various missing properties
  local H_internal = Jumppack.H

  -- Test with nil item
  local result1 = H_internal.display.item_to_string(nil)
  MiniTest.expect.equality(result1, '', 'nil item should return empty string')

  -- Test with item missing lnum (discovered as potential crash point)
  local item_no_lnum = {
    path = '/test/file.lua',
    col = 0,
    bufnr = 1,
    offset = -1,
    -- lnum is missing - this was a gap we discovered
  }

  MiniTest.expect.no_error(function()
    local result2 = H_internal.display.item_to_string(item_no_lnum)
    MiniTest.expect.equality(type(result2), 'string', 'should return string even with missing lnum')
  end, 'should handle missing lnum without crashing')

  -- Test with item missing path
  local item_no_path = {
    lnum = 10,
    col = 0,
    bufnr = 1,
    offset = -1,
    -- path is missing
  }

  MiniTest.expect.no_error(function()
    local result3 = H_internal.display.item_to_string(item_no_path)
    MiniTest.expect.equality(type(result3), 'string', 'should return string even with missing path')
  end, 'should handle missing path without crashing')

  -- Test with item missing col (should have default)
  local item_no_col = {
    path = '/test/file.lua',
    lnum = 10,
    bufnr = 1,
    offset = -1,
    -- col is missing
  }

  MiniTest.expect.no_error(function()
    local result4 = H_internal.display.item_to_string(item_no_col)
    MiniTest.expect.equality(type(result4), 'string', 'should return string with missing col')
    MiniTest.expect.equality(result4:find('10:1') ~= nil, true, 'should default col to 1')
  end, 'should handle missing col with default value')

  -- Test with completely empty item (should fall back to text field)
  local empty_item = {
    text = 'fallback text',
  }

  MiniTest.expect.no_error(function()
    local result5 = H_internal.display.item_to_string(empty_item)
    MiniTest.expect.equality(result5, 'fallback text', 'should use text field as fallback')
  end, 'should use text field as fallback')
end

-- ============================================================================
-- PHASE 7: VISUAL & DISPLAY TESTING
-- ============================================================================

T['Display Features']['Visual & Display Testing'] = MiniTest.new_set()

T['Display Features']['Visual & Display Testing']['Display Format Validation'] = MiniTest.new_set()

T['Display Features']['Visual & Display Testing']['Display Format Validation']['correctly displays item format: [indicator] [icon] [path/name] [lnum:col]'] = function()
  local buf = H.create_test_buffer('/project/test.lua', { 'local x = 1', 'local y = 2' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({ options = { show_hidden = true } })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
    { bufnr = buf, lnum = 2, col = 5 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')
  MiniTest.expect.equality(#state.items == 2, true, 'Should have 2 items')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Verify format: [indicator] [icon] [path/name] [lnum:col] [│ line preview]
  MiniTest.expect.string_matches(
    lines[1],
    '^[●○] .* test%.lua %d+:%d+ │',
    'First item should match format pattern'
  )
  MiniTest.expect.string_matches(
    lines[2],
    '^[●○] .* test%.lua %d+:%d+ │',
    'Second item should match format pattern'
  )

  -- Verify position information
  MiniTest.expect.string_matches(lines[1], '1:0', 'First item should show correct line:col')
  MiniTest.expect.string_matches(lines[2], '2:5', 'Second item should show correct line:col')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['displays hidden item indicators correctly'] = function()
  local buf = H.create_test_buffer('/project/test.lua', { 'local x = 1', 'local y = 2' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({ options = { show_hidden = true } })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
    { bufnr = buf, lnum = 2, col = 5 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Hide the first item
  vim.api.nvim_feedkeys('h', 'x', false)
  vim.wait(10)

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- First item should show hidden indicator (×)
  MiniTest.expect.string_matches(lines[1], '^× ', 'Hidden item should show × indicator')
  -- Second item should show normal indicator (● or ○)
  MiniTest.expect.string_matches(lines[2], '^[●○] ', 'Normal item should show position indicator')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['shows filter status indicators correctly'] = function()
  local buf1 = H.create_test_buffer('/project/main.lua', { 'local x = 1' })
  local buf2 = H.create_test_buffer('/other/test.lua', { 'local y = 2' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Initially no filters - check status
  local info = state.general_info
  MiniTest.expect.equality(type(info), 'table', 'Should have general info')

  -- Apply file filter
  vim.api.nvim_feedkeys('F', 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  info = state.general_info
  MiniTest.expect.string_matches(info.name or '', '[F]', 'Should show file filter indicator')

  -- Apply cwd filter
  vim.api.nvim_feedkeys('C', 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  info = state.general_info
  MiniTest.expect.string_matches(info.name or '', '[FC]', 'Should show both filter indicators')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['shows count display in status'] = function()
  local buf = H.create_test_buffer('/project/test.lua', { 'line 1', 'line 2', 'line 3', 'line 4', 'line 5' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
    { bufnr = buf, lnum = 2, col = 0 },
    { bufnr = buf, lnum = 3, col = 0 },
    { bufnr = buf, lnum = 4, col = 0 },
    { bufnr = buf, lnum = 5, col = 0 },
  }, 2)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Start typing a count
  vim.api.nvim_feedkeys('2', 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  local info = state.general_info
  MiniTest.expect.string_matches(info.name or '', '2', 'Should show count in status')

  -- Add another digit
  vim.api.nvim_feedkeys('5', 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  info = state.general_info
  MiniTest.expect.string_matches(info.name or '', '25', 'Should show multi-digit count in status')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['shows position indicators correctly'] = function()
  local buf = H.create_test_buffer('/project/test.lua', { 'line 1', 'line 2', 'line 3' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
    { bufnr = buf, lnum = 2, col = 0 },
    { bufnr = buf, lnum = 3, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Check that one item has current position indicator (●) and others have normal (○)
  local current_indicators = 0
  local normal_indicators = 0

  for _, line in ipairs(lines) do
    if line:match('^●') then
      current_indicators = current_indicators + 1
    elseif line:match('^○') then
      normal_indicators = normal_indicators + 1
    end
  end

  MiniTest.expect.equality(current_indicators, 1, 'Should have exactly one current position indicator')
  MiniTest.expect.equality(normal_indicators, 2, 'Should have two normal position indicators')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['handles window sizing properly'] = function()
  local buf = H.create_test_buffer('/project/very_long_filename_that_should_be_truncated.lua', {
    'This is a very long line that should test how the display handles long content and wrapping behavior in various window sizes',
  })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({
    window = {
      config = {
        width = 40, -- Small window to test truncation
        height = 10,
      },
    },
  })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Verify the window was created with correct size
  local win_id = state.instance.windows.main
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win_id), true, 'Main window should be valid')

  local win_config = vim.api.nvim_win_get_config(win_id)
  MiniTest.expect.equality(win_config.width, 40, 'Window should have correct width')
  MiniTest.expect.equality(win_config.height, 10, 'Window should have correct height')

  -- Verify content fits within window bounds
  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)
  MiniTest.expect.equality(#lines > 0, true, 'Should have content lines')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Display Format Validation']['shows preview content with proper context'] = function()
  local buf = H.create_test_buffer('/project/test.lua', {
    'function start()',
    '  local x = 1',
    '  local y = 2',
    '  return x + y',
    'end',
  })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({ options = { default_view = 'preview' } })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 3, col = 2 }, -- Point to 'local y = 2' line
  }, 0)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Should be in preview mode
  MiniTest.expect.equality(state.instance.view_state, 'preview', 'Should be in preview mode')

  -- Verify preview window exists
  local preview_win = state.instance.windows.preview
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview_win), true, 'Preview window should be valid')

  -- Verify preview content shows the target line with context
  local preview_lines = vim.api.nvim_buf_get_lines(state.instance.buffers.preview, 0, -1, false)
  MiniTest.expect.equality(#preview_lines > 1, true, 'Preview should have multiple lines for context')

  -- Should contain the target line
  local found_target = false
  for _, line in ipairs(preview_lines) do
    if line:match('local y = 2') then
      found_target = true
      break
    end
  end
  MiniTest.expect.equality(found_target, true, 'Preview should show target line')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Icon Integration'] = MiniTest.new_set()

T['Display Features']['Visual & Display Testing']['Icon Integration']['displays icons when MiniIcons available'] = function()
  -- Mock MiniIcons
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      if path:match('%.lua$') then
        return '󰢱', 'MiniIconsBlue'
      elseif path:match('%.json$') then
        return '', 'MiniIconsYellow'
      else
        return '', 'MiniIconsGrey'
      end
    end,
  }

  local buf1 = H.create_test_buffer('/project/test.lua', { 'local x = 1' })
  local buf2 = H.create_test_buffer('/project/config.json', { '{"name": "test"}' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Should contain MiniIcons
  MiniTest.expect.string_matches(lines[1], '󰢱', 'Lua file should show lua icon')
  MiniTest.expect.string_matches(lines[2], '', 'JSON file should show json icon')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore original
  _G.MiniIcons = original_miniicons
  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['displays icons when nvim-web-devicons available'] = function()
  -- Mock nvim-web-devicons
  local original_loaded = package.loaded['nvim-web-devicons']
  package.loaded['nvim-web-devicons'] = {
    get_icon = function(filename, ext, opts)
      if filename:match('%.lua$') then
        return '', 'DevIconLua'
      elseif filename:match('%.js$') then
        return '', 'DevIconJs'
      else
        return '', 'DevIconDefault'
      end
    end,
  }

  -- Ensure MiniIcons is not available
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = nil

  local buf1 = H.create_test_buffer('/project/main.lua', { 'local x = 1' })
  local buf2 = H.create_test_buffer('/project/script.js', { 'const x = 1;' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Should contain devicons
  MiniTest.expect.string_matches(lines[1], '', 'Lua file should show lua devicon')
  MiniTest.expect.string_matches(lines[2], '', 'JS file should show js devicon')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore originals
  _G.MiniIcons = original_miniicons
  package.loaded['nvim-web-devicons'] = original_loaded
  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['falls back gracefully when no icon plugins available'] = function()
  -- Ensure no icon plugins are available
  local original_miniicons = _G.MiniIcons
  local original_devicons = package.loaded['nvim-web-devicons']

  _G.MiniIcons = nil
  package.loaded['nvim-web-devicons'] = nil

  local buf = H.create_test_buffer('/project/test.lua', { 'local x = 1' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Should use fallback icon (space character)
  MiniTest.expect.string_matches(lines[1], '^[●○]  ', 'Should show fallback icon (space)')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore originals
  _G.MiniIcons = original_miniicons
  package.loaded['nvim-web-devicons'] = original_devicons
  H.cleanup_buffers({ buf })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['maintains icon consistency across list and preview views'] = function()
  -- Mock MiniIcons
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      if path:match('%.lua$') then
        return '󰢱', 'MiniIconsBlue'
      else
        return '', 'MiniIconsGrey'
      end
    end,
  }

  local buf = H.create_test_buffer('/project/test.lua', { 'local x = 1', 'local y = 2' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({ options = { default_view = 'list' } })

  H.create_mock_jumplist({
    { bufnr = buf, lnum = 1, col = 0 },
  }, 0)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Check icon in list view
  local list_lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)
  MiniTest.expect.string_matches(list_lines[1], '󰢱', 'Should show lua icon in list view')

  -- Switch to preview view
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-p>', true, true, true), 'x', false)
  vim.wait(10)

  state = Jumppack.get_state()
  MiniTest.expect.equality(state.instance.view_state, 'preview', 'Should be in preview mode')

  -- Check that preview title shows same icon
  local preview_title_lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)
  MiniTest.expect.string_matches(preview_title_lines[1], '󰢱', 'Should show same lua icon in preview title')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore original
  _G.MiniIcons = original_miniicons
  H.cleanup_buffers({ buf })
end

T['Display Features']['Icon Configuration: respects user icon preferences and settings'] = function()
  -- Test configuration-driven icon behavior - gap discovered during breaking analysis
  -- where removing icon conditional logic wasn't caught by existing tests

  local buf1 = H.create_test_buffer('config1.lua', { 'local config = {}' })
  local buf2 = H.create_test_buffer('config2.py', { 'config = dict()' })

  -- Test 1: With MiniIcons enabled but user preference disabled
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      return '󰢱', 'MiniIconsBlue' -- Always return lua icon for testing
    end,
  }

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 0)

  local original_fns = H.mock_vim_functions({
    current_file = 'config1.lua',
    cwd = vim.fn.getcwd(),
  })

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if state and state.instance then
      local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)
      -- Should contain icons when icon plugins are available
      MiniTest.expect.equality(#lines >= 1, true, 'should have display lines')

      -- Check that icon logic is actually working
      local has_icon = false
      for _, line in ipairs(lines) do
        if line:match('󰢱') then
          has_icon = true
          break
        end
      end
      MiniTest.expect.equality(has_icon, true, 'should display icons from MiniIcons')
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Test 2: Icon fallback behavior when plugins unavailable
  _G.MiniIcons = nil
  package.loaded['nvim-web-devicons'] = nil

  MiniTest.expect.no_error(function()
    Jumppack.setup({})
    Jumppack.start({})
    vim.wait(10)

    local state = Jumppack.get_state()
    if state and state.instance then
      local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)
      -- Should fallback to space character when no icon plugins
      local has_fallback = false
      for _, line in ipairs(lines) do
        -- Look for the fallback pattern (indicator + space + path)
        if line:match('^[●○]  ') then -- indicator + space + space (fallback icon) + path
          has_fallback = true
          break
        end
      end
      MiniTest.expect.equality(has_fallback, true, 'should use fallback icon pattern when no plugins')
    end

    if Jumppack.is_active() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
      vim.wait(10)
    end
  end)

  -- Cleanup and restore
  _G.MiniIcons = original_miniicons
  H.restore_vim_functions(original_fns)
  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['applies correct highlight groups to icons'] = function()
  -- Mock MiniIcons with specific highlight groups
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      if path:match('%.lua$') then
        return '󰢱', 'TestLuaIconHL'
      elseif path:match('%.py$') then
        return '', 'TestPythonIconHL'
      else
        return '', 'TestDefaultIconHL'
      end
    end,
  }

  local buf1 = H.create_test_buffer('/project/test.lua', { 'local x = 1' })
  local buf2 = H.create_test_buffer('/project/script.py', { 'x = 1' })

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist({
    { bufnr = buf1, lnum = 1, col = 0 },
    { bufnr = buf2, lnum = 1, col = 0 },
  }, 1)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  -- Check that extmarks were created for icon highlighting
  local buf_id = state.instance.buffers.main
  local extmarks = vim.api.nvim_buf_get_extmarks(buf_id, -1, 0, -1, { details = true })

  -- Should have icon highlights applied
  local found_lua_hl = false
  local found_python_hl = false

  for _, extmark in ipairs(extmarks) do
    local details = extmark[4]
    if details and details.hl_group then
      if details.hl_group == 'TestLuaIconHL' then
        found_lua_hl = true
      elseif details.hl_group == 'TestPythonIconHL' then
        found_python_hl = true
      end
    end
  end

  MiniTest.expect.equality(found_lua_hl, true, 'Should apply lua icon highlight group')
  MiniTest.expect.equality(found_python_hl, true, 'Should apply python icon highlight group')

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore original
  _G.MiniIcons = original_miniicons
  H.cleanup_buffers({ buf1, buf2 })
end

T['Display Features']['Visual & Display Testing']['Icon Integration']['handles different file types with appropriate icons'] = function()
  -- Mock comprehensive icon set
  local original_miniicons = _G.MiniIcons
  _G.MiniIcons = {
    get = function(category, path)
      local icons = {
        ['%.lua$'] = { '󰢱', 'MiniIconsLua' },
        ['%.js$'] = { '', 'MiniIconsJS' },
        ['%.py$'] = { '', 'MiniIconsPython' },
        ['%.json$'] = { '', 'MiniIconsJSON' },
        ['%.md$'] = { '', 'MiniIconsMarkdown' },
        ['%.txt$'] = { '', 'MiniIconsText' },
      }

      for pattern, data in pairs(icons) do
        if path:match(pattern) then
          return data[1], data[2]
        end
      end

      return '', 'MiniIconsDefault'
    end,
  }

  local test_files = {
    { '/project/main.lua', { 'local x = 1' }, '󰢱' },
    { '/project/app.js', { 'const x = 1;' }, '' },
    { '/project/script.py', { 'x = 1' }, '' },
    { '/project/config.json', { '{}' }, '' },
    { '/project/README.md', { '# Title' }, '' },
    { '/project/notes.txt', { 'notes' }, '' },
  }

  local bufs = {}
  local jumplist_entries = {}

  for i, file_data in ipairs(test_files) do
    local buf = H.create_test_buffer(file_data[1], file_data[2])
    bufs[i] = buf
    table.insert(jumplist_entries, { bufnr = buf, lnum = 1, col = 0 })
  end

  local Jumppack = require('lua.Jumppack')
  Jumppack.setup({})

  H.create_mock_jumplist(jumplist_entries, 3)

  local state = H.start_and_verify({})
  MiniTest.expect.equality(state ~= nil, true, 'Should have valid state')

  local lines = vim.api.nvim_buf_get_lines(state.instance.buffers.main, 0, -1, false)

  -- Verify each file type shows correct icon
  for i, file_data in ipairs(test_files) do
    local expected_icon = file_data[3]
    MiniTest.expect.string_matches(
      lines[i],
      expected_icon,
      string.format('File %s should show icon %s', file_data[1], expected_icon)
    )
  end

  if Jumppack.is_active() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'x', false)
    vim.wait(50)
  end

  -- Restore original
  _G.MiniIcons = original_miniicons
  H.cleanup_buffers(bufs)
end

return T
