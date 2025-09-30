# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Jumppack is a Neovim plugin that provides an enhanced navigation interface for Vim's jumplist. The plugin creates a floating window picker that allows users to visualize and navigate their jump history with preview functionality.

## Development Environment
- **Language**: Lua (LuaJIT)
- **LSP**: Configured via `.luarc.json` for Neovim development
- **Code Style**: StyLua with 2-space indentation, 120 character width
- **Plugin Structure**: Modular architecture in `lua/Jumppack/` (~3,276 lines across 9 files)

## Code Architecture

The plugin follows a **modular flat namespace design** with clean separation of concerns and explicit dependency injection.

### Module Structure

```
lua/Jumppack/
├── init.lua         (1,067 lines) - Main entry point, public API, config, logging
├── utils.lua        (341 lines)   - Utilities & logging (no dependencies)
├── hide.lua         (93 lines)    - Session-persistent hide system
├── filters.lua      (191 lines)   - Filter logic (file/cwd/hidden)
├── window.lua       (85 lines)    - Float window creation & management
├── display.lua      (546 lines)   - Rendering, formatting, preview
├── sources.lua     (190 lines)   - Jumplist processing & source creation
├── instance.lua     (565 lines)   - Instance lifecycle & state (singleton)
└── actions.lua      (198 lines)   - User action handlers
```

### Module Dependencies (Clean DAG)

```
utils (logging, errors, vim helpers)
  ↓
hide (session persistence)
filters (file/cwd/hidden filtering)
window (float windows)
  ↓
display (rendering, preview) ← filters, window
sources (jumplist processing) ← utils, filters, hide
  ↓
instance (lifecycle, state) ← window, display, filters, hide, sources
  ↓
actions (user handlers) ← instance, filters, hide, display
  ↓
init (public API, config) ← all modules
```

**Key architectural principles:**
- **No circular dependencies**: Clean dependency graph
- **Flat structure**: All modules export `H` table, accessed as `H.module_name.*`
- **Explicit dependencies**: Modules receive dependencies via `set_*()` injection functions
- **Singleton state**: Only `instance.lua` manages stateful singleton (active picker instance)
- **Pure functions**: Most modules are stateless, working with passed data

### Module Responsibilities

**init.lua** - Entry point
- Public API (`Jumppack.setup()`, `Jumppack.start()`, etc.)
- Configuration management (`H.config.*`)
- Logging system (`H.log.*`) with levels (trace/debug/info/warn/error)
- Module coordination and dependency injection

**utils.lua** - Foundation utilities
- Error handling (`H.error()`, `H.check_type()`)
- Buffer/window operations (`H.create_scratch_buf()`, `H.set_buflines()`)
- Vim API wrappers (safe operations that pcall internally)
- Path utilities (`H.full_path()`, `H.get_fs_type()`)
- No dependencies on other modules

**hide.lua** - Hide system
- Session-persistent hide management via `vim.g.Jumppack_hidden_items`
- Functions: `H.load()`, `H.save()`, `H.toggle()`, `H.is_hidden()`, `H.mark_items()`
- Storage: Newline-separated string (Vim sessions only save strings/numbers)
- Depends on: utils (for logging)

**filters.lua** - Filter logic
- Runtime filters: file_only, cwd_only, show_hidden
- Functions: `H.apply()`, `H.toggle_*()`, `H.reset()`, `H.is_active()`, `H.get_status_text()`
- Filters are NOT persistent (reset when picker closes)
- Depends on: utils (for path operations)

**window.lua** - Window management
- Float window creation and configuration
- Functions: `H.create_buffer()`, `H.create_window()`, `H.compute_config()`
- Constants: GOLDEN_RATIO (0.618), WINDOW_ZINDEX (251)
- Depends on: utils

**display.lua** - Rendering & preview
- ALL rendering logic: list view, preview mode, border updates
- Item formatting: `H.item_to_string()` with icon/path/position/preview
- Preview with syntax highlighting: `H.render_preview()`, `H.preview_set_lines()`
- Smart filename display for ambiguous names
- Depends on: utils, window, filters (injected), instance (injected)

**sources.lua** - Jumplist processing
- Processes Vim's jumplist into picker items
- Functions: `H.create_source()`, `H.get_all()`, `H.create_item()`, `H.find_target_offset()`
- Handles offset calculation for navigation (backward/forward)
- Depends on: utils, filters, hide

**instance.lua** - Instance lifecycle (stateful singleton)
- **ONLY module with singleton state**: `local active = nil`
- Instance creation, event loop, state management
- Functions: `H.create()`, `H.run_loop()`, `H.update()`, `H.set_items()`, `H.get_active()`
- Selection management: `H.set_selection()`, `H.move_selection()`, `H.get_selection()`
- Focus tracking and cleanup: `H.track_focus()`, `H.destroy()`
- Depends on: utils, window, display, filters, hide

**actions.lua** - User actions
- Action handlers for all keymaps
- Functions: `H.jump_back()`, `H.jump_forward()`, `H.choose()`, `H.toggle_*()`, etc.
- Integrates with instance, filters, and hide systems
- Depends on: instance, filters, hide, display, utils

### Key Components

- **Picker Interface**: Float window with item selection and preview (instance + display + window)
- **Jumplist Integration**: Processes Vim's jumplist (sources.lua)
- **Action System**: Configurable keymaps (actions.lua)
- **Preview System**: Syntax-highlighted preview (display.lua)
- **Icon Support**: Integration with MiniIcons and nvim-web-devicons (display.lua)
- **Filter System**: Real-time filtering (filters.lua)
- **Hide System**: Persistent hide storage (hide.lua)

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
function H.sources.create_source(opts)
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

### Entry Points
- **User entry**: `lua/Jumppack/init.lua` exports `Jumppack` table (public API)
- **Module loading**: `require('jumppack')` loads init.lua which coordinates all submodules
- **Global access**: After `setup()`, global `Jumppack` variable is available

### State Management
- **Singleton pattern**: Only `instance.lua` maintains stateful singleton (`local active = nil`)
- **State access**: Other modules call `Instance.get_active()` to access current picker state
- **State lifecycle**: Created in `H.instance.create()`, destroyed in `H.instance.destroy()`
- **No global state**: All other modules are stateless, working with passed data

### Dependency Injection Pattern
All module dependencies are injected explicitly in `init.lua`:
```lua
-- Example injections
H.filters.set_logger(H.log)
H.display.set_namespaces(H.ns_id)
H.display.set_filters(H.filters)
H.display.set_instance(H.instance)
H.instance.set_display(H.display)
H.actions.set_instance(H.instance)
```

This approach:
- Avoids circular dependencies
- Makes dependencies explicit and testable
- Allows independent module testing with mocks

### Important Implementation Details
- **Flat namespace**: All functions use `H.namespace.function()` pattern (no deep nesting)
- **Constants**: Defined at module level close to usage (not centralized)
- **Floating window API**: Extensive use of Neovim's float window APIs (window.lua)
- **Jumplist processing**: Core logic in `sources.lua` (`H.create_source()`, `H.get_all()`)
- **Preview rendering**: Syntax highlighting in `display.lua` (`H.render_preview()`, `H.preview_set_lines()`)
- **Item formatting**: Display strings in `display.lua` (`H.item_to_string()`)
- **Action handlers**: All user actions in `actions.lua` as `H.action_name()` functions

## Configuration
Default keymaps:
- `<C-o>/<C-i>`: Navigate jumplist back/forward
- `<CR>`: Choose jump location
- `<C-s>/<C-v>/<C-t>`: Open in split/vsplit/tab
- `<Esc>`: Exit picker
- `<C-p>`: Toggle preview

## Development Guidelines

### Module Development
- **Adding new functionality**: Place in appropriate existing module based on responsibility
- **Creating new modules**: Rare - only if responsibility doesn't fit existing modules
- **Module exports**: Always export `H` table (not `M`), maintain `H.function_name()` pattern
- **Dependencies**: Use dependency injection via `set_*()` functions, never `require()` other jumppack modules directly
- **State**: Keep modules stateless unless managing the singleton (only `instance.lua`)

### Code Style
- Use 2-space indentation and single quotes (enforced by StyLua)
- Prefer `local function name() ... end` over `local name = function() ... end`
- **Constants**: Define at module level close to usage (not centralized)
- **Error Handling**: Use guard clauses and early returns, follow established patterns
- **Flat Structure**: Maintain `H.function_name()` pattern, avoid deep nesting
- **Comments**: Document "why" not "what", use concise explanations

### Testing & Quality
- Run tests before committing changes: `make test`
- Run full CI suite before major changes: `make ci`
- Update screenshots if UI changes: `make screenshots`
- Maintain compatibility with Neovim's floating window API
- All new functions should follow existing error handling patterns

### Working with Modules

**When modifying display logic:**
- Edit `lua/Jumppack/display.lua`
- Rendering functions use injected dependencies (filters, instance)
- Test with both list and preview modes

**When modifying user actions:**
- Edit `lua/Jumppack/actions.lua`
- Actions receive instance via `Instance.get_active()`
- Follow existing action signature: `function(instance, count)`

**When modifying filters:**
- Edit `lua/Jumppack/filters.lua`
- Filters are runtime-only (not persistent)
- Test with combinations of filters active

**When modifying state management:**
- Edit `lua/Jumppack/instance.lua` with extreme care
- This is the ONLY stateful module
- Ensure proper cleanup in `H.destroy()`

## Dependencies and Installation
- **stylua**: Required for code formatting (`cargo install stylua`)
- **luacheck**: Required for linting (`luarocks install luacheck`)
- **mini.test**: Testing framework (downloaded automatically during tests)
- **mini.doc**: Documentation generation (downloaded automatically during doc generation)
- Prefer local function name() ... end instead of local name = function() ... end.
