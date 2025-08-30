local MiniTest = require('mini.test')
MiniTest.setup()

-- Function to parse test arguments
local function parse_test_args()
  -- Look for --test-file=path and --test-case=name in vim.v.argv
  local test_file = nil
  local test_case = nil

  for _, arg in ipairs(vim.v.argv or {}) do
    local file_match = arg:match('^--test%-file=(.+)$')
    local case_match = arg:match('^--test%-case=(.+)$')

    if file_match then
      test_file = file_match
    elseif case_match then
      test_case = case_match
    end
  end

  -- Fallback to environment variables
  test_file = test_file or vim.env.TEST_FILE
  test_case = test_case or vim.env.TEST_CASE

  return test_file, test_case
end

-- Parse arguments
local test_file, test_case = parse_test_args()

-- Run tests based on parameters
if test_file then
  print(string.format('Running tests from: %s', test_file))
  if test_case then
    print(string.format('  Specific case: %s', test_case))
  end

  local opts = test_case and { test_case } or nil
  MiniTest.run_file(test_file, opts)
else
  print('Running all tests...')
  MiniTest.run()
end

-- Exit after tests complete (only in headless mode)
-- Check for headless mode by looking at argv or checking for display
local is_headless = false
for _, arg in ipairs(vim.v.argv or {}) do
  if arg == '--headless' then
    is_headless = true
    break
  end
end

if is_headless then
  vim.cmd('quit!')
end
