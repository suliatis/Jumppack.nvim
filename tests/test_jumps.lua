---@diagnostic disable: duplicate-set-field

-- ============================================================================
-- JUMPPACK INTEGRATION TEST SUITE
-- ============================================================================
--
-- This file contains integration tests for Jumppack.nvim that verify the
-- complete user experience through screenshot-based UI testing.
--
-- ## Test Architecture
-- - Uses MiniTest with child Neovim processes for isolation
-- - Captures full screenshots and compares them with reference images
-- - Tests real user interactions (keypresses) rather than direct API calls
--
-- ## Screenshot Verification
-- Screenshots are captured using MiniTest's built-in functionality and
-- compared with reference images stored in tests/screenshots/
--
-- ### Environment Variables:
-- - JUMPPACK_TEST_SCREENSHOTS=update  - Update reference screenshots
-- - JUMPPACK_TEST_SCREENSHOTS=skip    - Skip screenshot verification
-- - JUMPPACK_TEST_SCREENSHOTS=verify  - Compare with references (default)
--
-- ### Commands:
-- - make screenshots        - Update all reference screenshots
-- - make screenshots-diff   - View differences between expected and actual
-- - make screenshots-clean  - Remove .actual debug files
--
-- ### Debugging Failed Tests:
-- When screenshot tests fail, .actual files are created for comparison.
-- Use `make screenshots-diff` to see what changed in the UI.
--
-- ## Test Structure
-- Each test follows this pattern:
-- 1. Set up jumplist with H.setup_jumplist(child)
-- 2. Perform user actions with child.type_keys()
-- 3. Capture screenshot with H.expect_screenshot()
-- 4. Verify state with H.expect_eq() assertions
--
-- ============================================================================

local MiniTest = require('mini.test')
local H = dofile('tests/helpers.lua')

local child = H.new_child_neovim()

-- Test suite setup and teardown
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Ensure clean restart for each test
      child.restart({ '-u', 'scripts/minimal_init.lua', '--clean' })

      -- Wait for startup to complete
      child.wait(100)

      -- Setup Jumppack with default configuration
      child.lua([[require('lua.Jumppack').setup()]])
    end,
    post_case = function()
      -- Stop child process (this handles cleanup)
      child.stop()
    end,
  },
})

-- Main test suite
T['Jumps'] = MiniTest.new_set()

-- Core functionality tests
T['Jumps']['opens picker with <C-o>'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'opens-picker-with-ctrl-o')

  -- Verify picker is active
  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active after <C-o>')
end

T['Jumps']['opens in preview mode by default'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'opens-in-preview-mode')

  -- Verify picker opened and is active
  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active')
end

T['Jumps']['navigates with <C-o> and <C-i>'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'navigate-initial', 1)

  -- Navigate backward in jumplist
  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'navigate-backward', 2)

  -- Navigate forward in jumplist
  child.type_keys('<C-i>')
  H.expect_screenshot(child, 'Jumps', 'navigate-forward', 3)

  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active')
end

T['Jumps']['chooses item with <CR>'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')

  -- Move to a different item
  child.type_keys('<C-o>')

  -- Choose the item
  child.type_keys('<CR>')
  H.expect_screenshot(child, 'Jumps', 'choose-item-with-enter')

  -- Verify picker is closed
  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, false, 'Picker should be closed')
end

-- Filtering tests
T['Jumps']['filters by file with f key'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'before-file-filter', 1)

  -- Apply file filter
  child.type_keys('f')
  H.expect_screenshot(child, 'Jumps', 'after-file-filter', 2)

  -- Picker should still be active
  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active')
end

T['Jumps']['filters by directory with c key'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')

  -- Apply directory filter
  child.type_keys('c')
  H.expect_screenshot(child, 'Jumps', 'filter-by-directory')

  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active')
end

T['Jumps']['resets filters with r key'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')

  -- Apply filters
  child.type_keys('f')
  child.type_keys('c')

  -- Reset filters
  child.type_keys('r')
  H.expect_screenshot(child, 'Jumps', 'reset-filters')

  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active')
end

-- Hide system tests
T['Jumps']['marks item as hidden with x key'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'before-hide-item', 1)

  -- Mark current item as hidden
  child.type_keys('x')
  H.expect_screenshot(child, 'Jumps', 'after-hide-item', 2)

  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active')
end

T['Jumps']['toggles hidden visibility with . key'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')

  -- Hide an item first
  child.type_keys('x')

  -- Toggle hidden visibility
  child.type_keys('.')
  H.expect_screenshot(child, 'Jumps', 'toggle-hidden-visibility')

  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active')
end

-- Preview tests
T['Jumps']['toggles preview with p key'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'preview-mode-default', 1)

  -- Toggle to list mode
  child.type_keys('p')
  H.expect_screenshot(child, 'Jumps', 'list-mode', 2)

  -- Toggle back to preview mode
  child.type_keys('p')
  H.expect_screenshot(child, 'Jumps', 'preview-mode-restored', 3)

  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active')
end

-- Edge cases
T['Jumps']['handles empty jumplist gracefully'] = function()
  -- Don't setup jumplist, start with clean state
  -- Create a clean empty buffer to avoid version-specific startup screen
  child.cmd('enew')
  child.cmd('set shortmess+=I') -- Disable intro message
  child.cmd('redraw!')
  child.wait(100)

  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'empty-jumplist')

  -- Should either not open or handle gracefully
  -- Don't check is_active here as behavior varies for empty jumplist
end

T['Jumps']['handles single jump entry'] = function()
  -- Create minimal jumplist
  child.cmd('edit tests/test-files/file1.lua')
  child.set_cursor(10, 0)

  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Jumps', 'single-jump-entry')
end

-- Smart escape tests
T['Jumps']['closes picker with <Esc>'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')

  -- Close with escape
  child.type_keys('<Esc>')
  H.expect_screenshot(child, 'Jumps', 'close-with-escape')

  -- Verify picker is closed
  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, false, 'Picker should be closed')
end

-- Count navigation tests
T['Jumps']['accepts count prefix'] = function()
  H.setup_jumplist(child)

  -- Jump back 3 times with count
  child.type_keys('3<C-o>')
  H.expect_screenshot(child, 'Jumps', 'count-prefix')

  -- Should show picker or jump directly
  -- Behavior depends on jumplist implementation
end

-- Alternative open modes
T['Jumps']['opens in split with <C-s>'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')

  -- Move to different item and open in split
  child.type_keys('<C-o>')
  child.type_keys('<C-s>')
  H.expect_screenshot(child, 'Jumps', 'open-in-split')

  -- Verify picker is closed and split was created
  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, false, 'Picker should be closed')
end

T['Jumps']['opens in vsplit with <C-v>'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')

  child.type_keys('<C-o>')
  child.type_keys('<C-v>')
  H.expect_screenshot(child, 'Jumps', 'open-in-vsplit')

  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, false, 'Picker should be closed')
end

T['Jumps']['opens in tab with <C-t>'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')

  child.type_keys('<C-o>')
  child.type_keys('<C-t>')
  H.expect_screenshot(child, 'Jumps', 'open-in-tab')

  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, false, 'Picker should be closed')
end

return T
