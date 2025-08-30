-- ============================================================================
-- JUMPPACK TEST FILE - Deep Path Testing
-- ============================================================================
--
-- This file tests how Jumppack handles deeply nested directory structures.
-- Located at: tests/test-files/long_path/deeply/nested/file.lua
--
-- Test scenarios:
-- - Long path display and smart truncation
-- - Directory filtering with deep nesting
-- - Path disambiguation in picker interface
-- - CWD filtering behavior with nested structures
local deeply_nested = {}

function deeply_nested.test_function()
  local data = {
    very_long_variable_name = 'test_value',
    another_long_name = 'another_value',
  }

  return data
end

-- More content for meaningful line numbers
function deeply_nested.another_function()
  print('Testing line positioning')
  print('With multiple print statements')
  print('For cursor position testing')
end

return deeply_nested
