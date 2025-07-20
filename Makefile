# Makefile for Jumppack plugin

.PHONY: test test-interactive test-watch format lint help

# Default target
help:
	@echo "Available targets:"
	@echo "  test           - Run tests in headless mode"
	@echo "  test-interactive - Run tests in interactive mode"
	@echo "  format         - Format Lua code with stylua"
	@echo "  lint           - Lint Lua code with luacheck"
	@echo "  help           - Show this help message"

# Run tests in headless mode (suitable for CI)
test:
	@echo "Running tests in headless mode..."
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

# Run tests in interactive mode (for development)
test-interactive:
	@echo "Running tests in interactive mode..."
	nvim -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

# Format code with stylua (if available)
format:
	@if command -v stylua >/dev/null 2>&1; then \
		echo "Formatting Lua code..."; \
		stylua lua/ tests/ scripts/; \
	else \
		echo "stylua not found. Install with: cargo install stylua"; \
	fi

# Lint code with luacheck (if available)
lint:
	@if command -v luacheck >/dev/null 2>&1; then \
		echo "Linting Lua code..."; \
		luacheck lua/ tests/ scripts/ --globals vim; \
	else \
		echo "luacheck not found. Install with: luarocks install luacheck"; \
	fi