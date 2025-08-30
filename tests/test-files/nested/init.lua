-- ============================================================================
-- JUMPPACK TEST FILE - Nested Init Module
-- ============================================================================
--
-- This init.lua file tests directory path display and filename disambiguation.
-- When multiple init.lua files exist, Jumppack should show directory context
-- to help users distinguish between them in the picker interface.
--
-- Test scenarios:
-- - Ambiguous filename resolution (nested/init.lua vs other init.lua files)
-- - Directory filtering with nested paths
-- - Complex nested data structures for realistic jump targets
local init = {}

function init.setup()
  -- Setup function
  return true
end

function init.run()
  -- Run function with multiple lines
  local config = {
    setting1 = 'value1',
    setting2 = 'value2',
    setting3 = {
      nested_setting = 'nested_value',
    },
  }

  return config
end

return init
