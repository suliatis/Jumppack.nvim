# Makefile for Jumppack plugin

.PHONY: test test-interactive test-watch format format-check lint ci ci-act help

# Default target
help:
	@echo "Available targets:"
	@echo "  test           - Run tests in headless mode"
	@echo "  test-interactive - Run tests in interactive mode"
	@echo "  format         - Format Lua code with stylua"
	@echo "  format-check   - Check code formatting (for CI)"
	@echo "  lint           - Lint Lua code with luacheck"
	@echo "  ci             - Run all CI checks locally"
	@echo "  ci-act         - Run GitHub Actions workflow locally with act"
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

# Check code formatting with stylua (for CI)
format-check:
	@if command -v stylua >/dev/null 2>&1; then \
		echo "Checking Lua code formatting..."; \
		stylua --check lua/ tests/ scripts/; \
	else \
		echo "stylua not found. Install with: cargo install stylua"; \
		exit 1; \
	fi

# Lint code with luacheck (if available)
lint:
	@if command -v luacheck >/dev/null 2>&1; then \
		echo "Linting Lua code..."; \
		luacheck lua/ tests/ scripts/ --globals vim; \
	else \
		echo "luacheck not found. Install with: luarocks install luacheck"; \
	fi

# Run all CI checks locally
ci: test format-check lint
	@echo "All CI checks passed!"

# Run GitHub Actions workflow locally with act
ci-act:
	@if command -v act >/dev/null 2>&1; then \
		echo "Running GitHub Actions workflow locally..."; \
		act --container-architecture linux/amd64 --reuse; \
	else \
		echo "act not found. Install with: brew install act"; \
		exit 1; \
	fi