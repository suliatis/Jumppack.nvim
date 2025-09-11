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
