---@diagnostic disable: duplicate-set-field

local MiniTest = require('mini.test')

local H = {}

---=== CORE TEST INFRASTRUCTURE ===---

--- Creates a new child neovim process for integration testing
--- Based on mini.nvim pattern for child process testing
--- @return table Child neovim object
H.new_child_neovim = function()
  local child = MiniTest.new_child_neovim()

  -- Enhanced child functions for our use case
  child.setup = function()
    child.restart({ '-u', 'scripts/minimal_init.lua', '--clean' })
    child.bo.readonly = false

    -- Ensure clean environment
    child.lua([[
      -- Clear any existing autocmds that might interfere
      vim.api.nvim_clear_autocmds({})

      -- Reset window/buffer state
      vim.cmd('only')
      vim.cmd('enew')
    ]])
  end

  -- Helper to wait for UI to settle with validation
  child.wait = function(ms)
    ms = ms or 100

    -- Use vim.wait with proper timeout handling
    child.lua(string.format(
      [[
      local success = vim.wait(%d, function() return true end, 10)
      if not success then
        print("Warning: UI wait timeout after %dms")
      end
    ]],
      ms,
      ms
    ))
  end

  -- Add cursor methods that may not exist in mini.test
  if not child.set_cursor then
    child.set_cursor = function(line, col, win_id)
      win_id = win_id or 0
      child.lua(string.format('vim.api.nvim_win_set_cursor(%d, {%d, %d})', win_id, line, col))
    end
  end

  if not child.get_cursor then
    child.get_cursor = function(win_id)
      win_id = win_id or 0
      return child.lua_get(string.format('vim.api.nvim_win_get_cursor(%d)', win_id))
    end
  end

  -- Note: child.get_screenshot() already exists from MiniTest

  return child
end

--- Sets up a standard jumplist with multiple files for testing
--- @param child table Child neovim process
H.setup_jumplist = function(child)
  -- Navigate through multiple files to build jumplist
  child.cmd('edit tests/test-files/file1.lua')
  child.set_cursor(6, 2) -- At print statement

  child.cmd('edit tests/test-files/file2.txt')
  child.set_cursor(12, 0) -- At section header

  child.cmd('edit tests/test-files/nested/init.lua')
  child.set_cursor(15, 4) -- In config table

  child.cmd('edit tests/test-files/file3.md')
  child.set_cursor(8, 0) -- At features header

  child.cmd('edit tests/test-files/long_path/deeply/nested/file.lua')
  child.set_cursor(18, 2) -- At print statement

  -- Navigate back to create meaningful jumplist
  child.cmd('edit tests/test-files/file1.lua')
  child.set_cursor(20, 4) -- Different position

  -- This creates a jumplist with 6+ entries for comprehensive testing
end

---=== CUSTOM EXPECTATIONS ===---

--- Expects values to be equal with optional context
--- @param actual any Actual value
--- @param expected any Expected value
--- @param context string|nil Optional failure context
--- @usage H.expect_eq(#lines, 2, 'Should have 2 lines after rendering')
H.expect_eq = function(actual, expected, context)
  if context then
    MiniTest.expect.equality(actual, expected, context)
  else
    MiniTest.expect.equality(actual, expected)
  end
end

---=== SCREENSHOT VERIFICATION ===---

--- Capture current screen state using MiniTest's built-in screenshot functionality
--- @param child table Child neovim process
--- @param opts table|nil Options: {only_lines}
--- @return string Screen content as string
H.get_screenshot = function(child, opts)
  opts = opts or {}

  -- Use MiniTest's built-in screenshot functionality
  local screenshot = child.get_screenshot()

  if not screenshot or not screenshot.text then
    return ''
  end

  -- If only_lines is specified, filter to those lines
  if opts.only_lines then
    local lines = {}
    for _, row in ipairs(opts.only_lines) do
      if screenshot.text[row] then
        table.insert(lines, table.concat(screenshot.text[row], ''))
      end
    end
    return table.concat(lines, '\n')
  end

  -- Convert full 2D text array to string
  local lines = {}
  for _, row in ipairs(screenshot.text) do
    table.insert(lines, table.concat(row, ''))
  end

  return table.concat(lines, '\n')
end

--- Unified screenshot expectation function with automatic path generation
--- @param child table Child neovim process
--- @param test_group_or_path string Either test group name (e.g., 'Jumps') or direct path
--- @param test_name string|nil Test case name (optional if using direct path)
--- @param sequence number|nil Optional sequence number for multiple shots
--- @param opts table|nil Options: {only_lines, timeout=200, retry_count=2}
H.expect_screenshot = function(child, test_group_or_path, test_name, sequence, opts)
  -- Handle different calling patterns
  local reference_path

  if test_name then
    -- Auto-generate path from test_group + test_name + sequence
    reference_path = H.get_screenshot_path(test_group_or_path, test_name, sequence)
  else
    -- Direct path provided
    reference_path = test_group_or_path
  end

  opts = opts or {}
  local timeout = opts.timeout or 200
  local retry_count = opts.retry_count or 2

  -- Let UI settle before capture with configurable timeout
  child.wait(timeout)

  -- Attempt screenshot capture with retry logic
  local actual
  for attempt = 1, retry_count do
    local success, result = pcall(H.get_screenshot, child, opts)
    if success and result and result ~= '' then
      actual = result
      break
    elseif attempt == retry_count then
      error(
        string.format(
          'Screenshot capture failed after %d attempts for %s. Child process may have crashed.',
          retry_count,
          reference_path
        )
      )
    else
      -- Wait before retry
      child.wait(50)
    end
  end

  -- Determine screenshot mode
  local mode = vim.env.JUMPPACK_TEST_SCREENSHOTS or 'verify'
  local ref_file = 'tests/screenshots/' .. reference_path

  if mode == 'update' or vim.fn.filereadable(ref_file) == 0 then
    -- Create or update reference screenshot
    vim.fn.mkdir('tests/screenshots', 'p')
    vim.fn.writefile(vim.split(actual, '\n'), ref_file)
    if mode ~= 'update' then
      print('Created reference screenshot: ' .. ref_file)
    end
  elseif mode == 'verify' then
    -- Compare with existing reference
    local reference = table.concat(vim.fn.readfile(ref_file), '\n')
    if actual ~= reference then
      -- Save actual for debugging
      vim.fn.writefile(vim.split(actual, '\n'), ref_file .. '.actual')
      error(
        string.format(
          'Screenshot mismatch: %s\n'
            .. 'Expected length: %d, actual length: %d\n'
            .. 'Run with JUMPPACK_TEST_SCREENSHOTS=update to update reference\n'
            .. 'Use `make diff-screenshots` to see differences',
          reference_path,
          #reference,
          #actual
        )
      )
    end
  end
  -- mode == 'skip' just returns without doing anything
end

--- Generate screenshot path from test context with robust naming
--- @param test_group string Test group name
--- @param test_name string Test case name
--- @param sequence number|nil Optional sequence number for multiple shots
--- @return string Path for screenshot file
H.get_screenshot_path = function(test_group, test_name, sequence)
  -- Validate inputs
  if not test_group or test_group == '' then
    test_group = 'unknown'
  end
  if not test_name or test_name == '' then
    test_name = 'test'
  end

  -- Sanitize names for filesystem compatibility
  local clean_group = test_group:gsub('[^%w%-_%.]', '-'):gsub('%-+', '-'):gsub('^%-+', ''):gsub('%-+$', '')
  local clean_name = test_name:gsub('[^%w%-_%.]', '-'):gsub('%-+', '-'):gsub('^%-+', ''):gsub('%-+$', '')

  -- Prevent excessively long filenames (filesystem limits)
  if #clean_group > 50 then
    clean_group = clean_group:sub(1, 50):gsub('%-$', '')
  end
  if #clean_name > 100 then
    clean_name = clean_name:sub(1, 100):gsub('%-$', '')
  end

  -- Build path with consistent format
  local path = string.format('test_jumps-%s-%s', clean_group, clean_name)

  if sequence then
    -- Ensure sequence is valid
    local seq_num = tonumber(sequence) or 1
    path = path .. '-' .. string.format('%03d', seq_num)
  end

  return path .. '.txt'
end

--- Waits for async operations to complete (scheduled functions, UI updates)
--- @param ms number|nil Wait time in milliseconds (default: 50)
H.wait_for_async = function(ms)
  ms = ms or 50
  vim.wait(ms)
  vim.cmd('redraw')
end

return H
