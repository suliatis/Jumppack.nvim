# Makefile for Jumppack plugin

.PHONY: test test-interactive format format-check lint ci ci-act doc doc-check help

# Default target
help:
	@echo "Available targets:"
	@echo "  test           - Run tests in headless mode"
	@echo "  test-interactive - Run tests in interactive mode"
	@echo "  format         - Format Lua code with stylua"
	@echo "  format-check   - Check code formatting (for CI)"
	@echo "  lint           - Lint Lua code with luacheck"
	@echo "  doc            - Generate documentation with mini.doc"
	@echo "  doc-check      - Check documentation generation (for CI)"
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

# Generate documentation with mini.doc
doc:
	@echo "Generating documentation..."
	@mkdir -p doc
	@if [ -f scripts/generate_docs.lua ]; then \
		nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/generate_docs.lua" -c "qa!"; \
	else \
		echo "Documentation script not found. Creating..."; \
		$(MAKE) create-doc-script; \
		nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/generate_docs.lua" -c "qa!"; \
	fi
	@echo "Documentation generated in doc/jumppack.txt"

# Check documentation generation (for CI)
doc-check:
	@echo "Checking if documentation is up-to-date..."
	@if [ ! -f doc/jumppack.txt ]; then \
		echo "Error: doc/jumppack.txt not found. Run 'make doc' first."; \
		exit 1; \
	fi
	@echo "Backing up existing documentation..."
	@cp doc/jumppack.txt doc/jumppack.txt.backup
	@echo "Generating temporary documentation for comparison..."
	@mkdir -p /tmp/jumppack-doccheck
	@if TEMP_DOC=/tmp/jumppack-doccheck/jumppack.txt nvim --headless --noplugin \
		-u scripts/minimal_init.lua -c "luafile scripts/generate_docs.lua" 2>/dev/null; then \
		mv doc/jumppack.txt.backup doc/jumppack.txt; \
		if diff -q doc/jumppack.txt /tmp/jumppack-doccheck/jumppack.txt >/dev/null 2>&1; then \
			echo "✓ Documentation is up-to-date"; \
			rm -rf /tmp/jumppack-doccheck; \
		else \
			echo "✗ Documentation is out of date!"; \
			echo "  Run 'make doc' to update and commit the changes."; \
			rm -rf /tmp/jumppack-doccheck; \
			exit 1; \
		fi; \
	else \
		mv doc/jumppack.txt.backup doc/jumppack.txt 2>/dev/null || true; \
		echo "✗ Failed to generate documentation"; \
		rm -rf /tmp/jumppack-doccheck; \
		exit 1; \
	fi

# Run all CI checks locally
ci: test format-check lint doc-check
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
