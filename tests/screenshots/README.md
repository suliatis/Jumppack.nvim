# Screenshot Testing

This directory contains reference screenshots for Jumppack.nvim's integration tests. The screenshot testing system captures text-based UI output from child Neovim processes and compares it with reference images.

## How It Works

### Screenshot Capture
- Tests use `H.expect_screenshot()` to capture and verify UI state
- Screenshots are text-based (not image files) - captured screen content as strings
- Each test captures the complete terminal output using MiniTest's `child.get_screenshot()`

### Reference Management
Reference screenshots are stored as `.txt` files with descriptive names:
```
test_jumps-Jumps-opens-picker-with-ctrl-o.txt
test_jumps-Jumps-navigate-backward-002.txt
test_jumps-Jumps-filter-by-directory.txt
```

### Environment Variables
Control screenshot behavior with environment variables:

- **`JUMPPACK_TEST_SCREENSHOTS=verify`** (default): Compare with existing references
- **`JUMPPACK_TEST_SCREENSHOTS=update`**: Update/create all reference screenshots
- **`JUMPPACK_TEST_SCREENSHOTS=skip`**: Skip screenshot verification entirely

## Usage

### Running Tests
```bash
# Normal test run - compares with references
make test:jumps

# Update all reference screenshots
make screenshots

# Skip screenshot verification (faster)
JUMPPACK_TEST_SCREENSHOTS=skip make test:jumps
```

### Debugging Failed Tests
When screenshot tests fail:

1. **`.actual` files are created** showing what was captured
2. **Use diff tools** to see what changed:
   ```bash
   make screenshots-diff
   ```
3. **Clean up debug files**:
   ```bash
   make screenshots-clean
   ```

### Adding New Screenshot Tests
```lua
-- In test file
H.expect_screenshot(child, 'Jumps', 'test-description')

-- With sequence number for multiple captures
H.expect_screenshot(child, 'Jumps', 'multi-step-test', 1)
H.expect_screenshot(child, 'Jumps', 'multi-step-test', 2)

-- With custom options
H.expect_screenshot(child, 'Jumps', 'slow-test', nil, {
  timeout = 500,     -- Wait longer for UI to settle
  retry_count = 3    -- More retry attempts
})
```

## Error Recovery

The screenshot system includes robust error handling:

- **Retry Logic**: Failed captures are retried (default: 2 attempts)
- **Configurable Timeouts**: Adjust wait time for UI settling (default: 200ms)
- **Child Process Monitoring**: Detects crashed child processes
- **Graceful Fallbacks**: Clear error messages when capture fails

## File Organization

```
tests/screenshots/
├── README.md                                    # This file
├── test_jumps-Jumps-*.txt                      # Reference screenshots
└── test_jumps-Jumps-*.actual                   # Debug files (gitignored)
```

## Best Practices

### When to Add Screenshot Tests
- **User-visible changes**: Any change that affects the picker UI
- **Key interactions**: Important user workflows and edge cases
- **Bug fixes**: Prevent regressions in visual behavior

### When to Update References
- **Intentional UI changes**: Use `make screenshots` to update all references
- **New features**: Add new tests and generate their references
- **Bug fixes**: Ensure fixes are captured in updated references

### Avoiding Flaky Tests
- **Let UI settle**: Always wait before capture (handled automatically)
- **Use consistent test data**: Use standardized jumplist setup via `H.setup_jumplist()`
- **Avoid timing dependencies**: Focus on final state, not intermediate transitions

## Maintenance

### Regular Tasks
- **Review .actual files** when tests fail to understand changes
- **Clean up debug files** regularly with `make screenshots-clean`
- **Update references** when making intentional UI changes

### CI Integration
- Tests run in headless mode with reference comparison
- Failed tests save `.actual` files for debugging
- Use `JUMPPACK_TEST_SCREENSHOTS=skip` for faster CI runs when UI hasn't changed

### Troubleshooting
- **Empty screenshots**: Child process may have crashed - check test setup
- **Consistent failures**: May need timeout adjustment for slower CI environments
- **Missing references**: Run `make screenshots` to generate initial references