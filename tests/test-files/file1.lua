-- ============================================================================
-- JUMPPACK TEST FILE 1 - Lua Module
-- ============================================================================
--
-- This file provides a sample Lua module for jumplist navigation testing.
-- Used in integration tests to create realistic jumplist entries with
-- meaningful line positions and content for testing navigation workflows.
--
-- Test scenarios:
-- - Function definitions at various line numbers
-- - Mixed code complexity for realistic navigation
-- - Multiple jump targets within single file
local M = {}

-- Simple function for testing
function M.hello()
  print('Hello from file1')
end

function M.calculate(a, b)
  return a + b
end

-- Some more lines to make navigation meaningful
local function internal_helper()
  return 'helper'
end

function M.complex_function()
  local result = internal_helper()
  if result == 'helper' then
    return M.calculate(10, 20)
  end
  return nil
end

return M
