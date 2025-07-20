-- Test runner script for Jumppack plugin
-- This script runs all tests using mini.test in headless mode

local function run_tests()
  -- Load the test file
  local test_file = 'tests/test_jumppack.lua'
  local test_set = dofile(test_file)

  -- Run the tests
  local result = require('mini.test').run(test_set, {
    -- Configuration for test execution
    execute = {
      reporter = require('mini.test').gen_reporter.stdout({ group_depth = 2 }),
      stop_on_error = false,
    },
  })

  -- Exit with appropriate code
  if result and (result.n_fail > 0 or result.n_error > 0) then
    vim.cmd('cquit 1')
  else
    vim.cmd('qall')
  end
end

-- Schedule the test run to happen after initialization
vim.schedule(run_tests)
