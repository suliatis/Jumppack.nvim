# Contributing to Jumppack.nvim

## 🧪 Testing

Essential commands:
```bash
make test                     # Run all tests
make test:jumps CASE="name"   # Run specific test case
make screenshots              # Update reference screenshots
make ci                       # Full CI suite
```

Test pattern:
```lua
local H = dofile('tests/helpers.lua')
local child = H.new_child_neovim()

T['Feature']['action'] = function()
  H.setup_jumplist(child)
  child.type_keys('<C-o>')
  H.expect_screenshot(child, 'Feature', 'action')
  H.expect_eq(result, expected, 'Context for assertion')
end
```

Use real user interactions and screenshot testing for UI verification.

## 📝 Architecture

**Flat namespace pattern** - single file (`lua/Jumppack.lua`):
```lua
-- Public API
Jumppack.setup(), Jumppack.start()

-- Internal helpers by responsibility
H.jumplist.*    -- Jumplist processing
H.display.*     -- Rendering/formatting
H.instance.*    -- State management
H.actions.*     -- User actions
H.utils.*       -- Shared utilities
```

**Patterns:**
- Use `H.namespace.function()`, avoid deep nesting
- Guard clauses with early returns
- Public API: `H.utils.error()` with context
- Internal functions: return `nil/false` for expected failures

## 🔍 Logging

Jumppack includes comprehensive debug logging for troubleshooting issues.

**Log Levels** (hierarchical):
```lua
H.log.trace(...)  -- Verbose internal state (selection changes, detailed flow)
H.log.debug(...)  -- Key operations (API calls, jumplist processing, filters)
H.log.info(...)   -- User-visible operations (picker started, navigation)
H.log.warn(...)   -- Recoverable issues (empty jumplist, edge reached)
H.log.error(...)  -- Critical failures (config errors, invalid state)
```

**Configuration:**
```lua
-- In config
Jumppack.setup({ options = { log_level = 'debug' } })

-- Or via environment variable (takes precedence)
JUMPPACK_LOG_LEVEL=trace nvim
```

**When to Log:**

Use **trace** for:
- Internal state changes (selection index, filter counts)
- Detailed flow tracking (function entry/exit with state)
- Low-level operations (buffer/window IDs, item counts)

Use **debug** for:
- Public API entry points with parameters
- Key operation results (jumplist size, filter results)
- Internal function operations with context

Use **info** for:
- User-initiated actions (picker started, navigation)
- State changes visible to user (filter enabled/disabled)
- Successful completions

Use **warn** for:
- Expected edge cases (empty lists, boundaries reached)
- Fallback behavior (missing icons, invalid indices)
- Non-critical validation failures

Use **error** for:
- Configuration validation failures
- Type check failures (already logged by `H.utils.error()`)
- Unexpected state that prevents operation

**Example:**
```lua
function H.filters.toggle_file(filters)
  filters.file_only = not filters.file_only
  H.log.debug('toggle_file: file_only=', filters.file_only)
  H.log.info('File filter', filters.file_only and 'enabled' or 'disabled')
  return filters
end
```

**Testing with Logs:**
```bash
# View logs while developing
tail -f ~/.local/state/nvim/jumppack.log

# Run tests with logging
JUMPPACK_LOG_LEVEL=debug make test

# Clear log file
rm ~/.local/state/nvim/jumppack.log
```

**Note:** Default `log_level='off'` ensures zero runtime cost in production.

## 📋 Before Submitting PR

```bash
make format  # Format code with stylua
make ci      # All must pass
```

Requirements:
- Follow existing `H.namespace` patterns
- Include tests for new functionality
- Screenshot tests for UI changes
- Update documentation: `make doc` (uses `---@tag`, `---@class` patterns)
