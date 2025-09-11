# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Jumppack is a Neovim plugin that provides an enhanced navigation interface for Vim's jumplist. The plugin creates a floating window picker that allows users to visualize and navigate their jump history with preview functionality.

## Development Environment
- **Language**: Lua (LuaJIT)
- **LSP**: Configured via `.luarc.json` for Neovim development
- **Code Style**: StyLua with 2-space indentation, 120 character width
- **Plugin Structure**: Single-file plugin in `lua/Jumppack.lua` (~2,400 lines)

## Code Architecture
The plugin follows a modular flat namespace design pattern:
- **Jumppack** namespace: Public API (`setup()`, `start()`, `refresh()`)
- **H** namespace: Internal helper functions organized by responsibility
- **Flat Structure**: All functions use `H.namespace.function()` pattern (no deep nesting)
- **Instance Management**: Single active instance with state tracking

### H Namespace Organization
- **H.jumplist**: Jumplist processing and source creation
- **H.display**: ALL rendering, formatting, and preview functionality
- **H.instance**: ALL state management and lifecycle operations
- **H.filters**: Filter logic and toggles (file_only, cwd_only, show_hidden)
- **H.window**: Window creation and management
- **H.actions**: User action handlers (choose, move, toggle)
- **H.utils**: Shared utilities and error handling
- **H.hide**: Persistent hide system for jump entries

### Key Components
- **Picker Interface**: Float window with item selection and preview
- **Jumplist Integration**: Processes Vim's jumplist in `H.jumplist.create_source()`
- **Action System**: Configurable keymaps for different navigation actions
- **Preview System**: Syntax-highlighted preview of jump locations
- **Icon Support**: Integration with MiniIcons and nvim-web-devicons
- **Filter System**: Real-time filtering by file, directory, or visibility

## Common Development Commands

### Testing
```bash
make test                  # Run all tests in headless mode (for CI)
make test-interactive      # Run all tests in interactive mode (for development)
make test-list             # List all available test targets

# Run specific test files (automatically generated targets)
make test:jumps            # Run test_jumps.lua (headless integration tests)
make test:jumps-interactive # Run test_jumps.lua (interactive)

# Run specific test case with CASE parameter
make test:jumps CASE="opens picker with <C-o>"
make test:jumps-interactive CASE="navigates with <C-o> and <C-i>"

# Screenshot testing commands
make screenshots           # Update all reference screenshots
make screenshots-diff      # View differences between expected and actual
make screenshots-clean     # Remove .actual debug files
```

### Code Quality
```bash
make format               # Format Lua code with stylua
make format-check         # Check code formatting (for CI)
make lint                 # Lint Lua code with luacheck
make doc                  # Generate documentation with mini.doc
make doc-check           # Check documentation is up-to-date (for CI)
make ci                   # Run all CI checks locally
```

### Manual Testing
```bash
# Test as a plugin by symlinking to Neovim config
ln -s $(pwd) ~/.config/nvim/pack/dev/start/jumppack

# Then in Neovim:
# :lua Jumppack.setup()
# :lua Jumppack.start({})
```

## Testing Architecture
The plugin uses a modern testing setup with **mini.test** running in actual Neovim:

- **Framework**: mini.test (part of mini.nvim)
- **Execution**: Tests run in headless Neovim, not standalone Lua
- **No Mocking**: Uses real vim APIs instead of complex mocks
- **Screenshot Testing**: Text-based UI verification with reference comparison
- **Test Infrastructure**:
  - `scripts/minimal_init.lua` - Minimal Neovim config for testing
  - `scripts/test.lua` - Unified test runner with support for specific files/cases and proper exit handling
  - `tests/helpers.lua` - Centralized test helpers (~200 lines, highly optimized)
  - `tests/test_jumps.lua` - Integration tests with screenshot verification (17 tests)
  - `tests/test-files/` - Real test files for jumplist navigation
  - `tests/screenshots/` - Reference screenshots and documentation

### Screenshot Testing System
The integration tests use screenshot-based verification to test the complete UI:

- **Environment Control**: `JUMPPACK_TEST_SCREENSHOTS=update|skip|verify`
- **Text-Based**: Captures terminal output as text, not image files
- **Reference Management**: Stores expected output in `tests/screenshots/*.txt`
- **Debug Support**: Creates `.actual` files for failed tests and diff tools
- **Child Process Isolation**: Each test runs in separate Neovim instance

### Test Writing Practices

#### Helper Usage Guidelines
All tests use the centralized helpers from `tests/helpers.lua`. Follow these patterns:

**Integration Test Pattern:**
```lua
local H = dofile('tests/helpers.lua')
local child = H.new_child_neovim()

-- Setup jumplist and test user interactions
T['Jumps']['opens picker with <C-o>'] = function()
  H.setup_jumplist(child)           -- Create realistic jumplist
  child.type_keys('<C-o>')          -- Simulate user keypress
  H.expect_screenshot(child, 'Jumps', 'opens-picker-with-ctrl-o')

  -- Verify picker state
  local is_active = child.lua_get('Jumppack.is_active()')
  H.expect_eq(is_active, true, 'Picker should be active after <C-o>')
end
```

**Screenshot Testing:**
```lua
-- Basic screenshot capture
H.expect_screenshot(child, 'Jumps', 'test-name')

-- Multi-step screenshots with sequence numbers
H.expect_screenshot(child, 'Jumps', 'navigation-test', 1)
child.type_keys('<C-o>')
H.expect_screenshot(child, 'Jumps', 'navigation-test', 2)

-- With custom options for slower environments
H.expect_screenshot(child, 'Jumps', 'complex-test', nil, {
  timeout = 500,      -- Wait longer for UI to settle
  retry_count = 3     -- More retry attempts
})
```

**Custom Expectations (always with context):**
```lua
H.expect_eq(#lines, 2, 'Should render 2 items')
H.expect_match(lines[1], '^↑1.*test%.lua 10:5', 'First item should have up arrow')
```

#### Context Parameter Philosophy
Always provide context for test expectations - replace comments with context parameters:

```lua
-- BAD: Comment separate from assertion
-- Should render all 4 items including hidden ones
H.expect_eq(#lines, 4)

-- GOOD: Context in assertion
H.expect_eq(#lines, 4, 'Should render all 4 items including hidden ones')
```

#### Error Testing Patterns
```lua
-- Test expected crashes with context
MiniTest.expect.error(function()
  Jumppack.setup('invalid config')
end, 'config.*table')

-- Test should-not-crash scenarios
MiniTest.expect.no_error(function()
  require('lua.Jumppack').show_items(invalid_buf, items)
end, 'Invalid buffer should not crash')
```

#### Test Organization
- **User-focused test names** - `T['Jumps']['opens picker with <C-o>']` (what user does)
- **Real interactions** - Use `child.type_keys()`, not direct API calls
- **Screenshot verification** - Capture complete UI state for integration tests
- **Automatic cleanup** - Child processes restart between tests for isolation
- **Context over comments** - Use expectation context instead of explanatory comments

### Test Coverage
Current test suite includes:
- **Integration tests** (`test_jumps.lua`): 17 tests covering complete user workflows with screenshot verification
- **Real file navigation**: Uses actual test files in `tests/test-files/` for realistic jumplist scenarios
- **UI state verification**: Screenshot-based testing captures the full picker interface
- **Error handling**: Child process isolation prevents test contamination

## Error Handling Architecture
The codebase follows standardized error handling principles:

### Error Handling Strategy
- **Public API functions** (`Jumppack.*`): Use `H.utils.error()` with clear, contextual messages
- **Internal helper functions** (`H.*`): Return `nil` or `false` for expected failures
- **Validation**: Always performed at function entry with early returns (guard clauses)
- **Error messages**: Include function context: `"function_name(): explanation"`

### Error Message Format
```lua
-- Public API errors (user-facing)
H.utils.error('start(): options must be a table, got ' .. type(opts))
H.utils.error('setup(): window.config must be table or callable, got ' .. type(config))

-- Internal functions return nil/false for expected conditions
function H.jumplist.create_source(opts)
  if #all_jumps == 0 then
    return nil  -- Expected condition, handled by caller
  end
end
```

### Guard Clause Pattern
Functions use early validation to avoid nested conditionals:
```lua
function H.instance.move_selection(instance, by, to)
  -- Early validation - guard clauses
  if not instance or not instance.items or #instance.items == 0 then
    return
  end
  -- Trusted state after validation - no further nil checks needed
end
```

## Code Structure Notes
- Main plugin logic in `lua/Jumppack.lua` (~2,400 lines)
- Uses Neovim's floating window API extensively
- Jumplist processing happens in `H.jumplist.create_source()`
- Preview functionality in `H.display.render_preview()` and `Jumppack.preview_item()`
- Item formatting in `H.display.item_to_string()` and `Jumppack.show_items()`
- Instance management through `H.instance` with proper cleanup
- Constants defined at namespace level close to usage (not centralized)

## Configuration
Default keymaps:
- `<C-o>/<C-i>`: Navigate jumplist back/forward
- `<CR>`: Choose jump location
- `<C-s>/<C-v>/<C-t>`: Open in split/vsplit/tab
- `<Esc>`: Exit picker
- `<C-p>`: Toggle preview

## Development Guidelines
- Follow existing code patterns in the H namespace for internal functions
- Use 2-space indentation and single quotes (enforced by StyLua)
- Maintain compatibility with Neovim's floating window API
- Keep all functionality in the single main file unless absolutely necessary
- **Constants**: Define at namespace level close to usage (not centralized)
- **Error Handling**: Use guard clauses and early returns, follow established patterns
- **Flat Structure**: Maintain `H.namespace.function()` pattern, avoid deep nesting
- Run tests before committing changes: `make test`
- Run full CI suite before major changes: `make ci`

## Dependencies and Installation
- **stylua**: Required for code formatting (`cargo install stylua`)
- **luacheck**: Required for linting (`luarocks install luacheck`)
- **mini.test**: Testing framework (downloaded automatically during tests)
- **mini.doc**: Documentation generation (downloaded automatically during doc generation)
- Prefer local function name() ... end instead of local name = function() ... end.
