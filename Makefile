# Makefile for Jumppack plugin

# Discover all test files and extract their base names
TEST_FILES := $(wildcard tests/test_*.lua)
TEST_NAMES := $(patsubst tests/test_%.lua,%,$(TEST_FILES))

.PHONY: test test-interactive test-list format format-check lint ci ci-act doc doc-check help screenshots screenshots-clean screenshots-diff

# Default target
help:
	@echo "Available targets:"
	@echo "  test           - Run all tests in headless mode"
	@echo "  test-interactive - Run all tests in interactive mode"
	@echo "  test-list      - List all available test targets"
	@echo "  test:NAME      - Run specific test file (e.g., test:setup)"
	@echo "  test:NAME-interactive - Run specific test file interactively"
	@echo "    Optional: CASE=\"test name\" to run specific test case"
	@echo "  format         - Format Lua code with stylua"
	@echo "  format-check   - Check code formatting (for CI)"
	@echo "  lint           - Lint Lua code with luacheck"
	@echo "  doc            - Generate documentation with mini.doc"
	@echo "  doc-check      - Check documentation generation (for CI)"
	@echo "  ci             - Run all CI checks locally"
	@echo "  ci-act         - Run GitHub Actions workflow locally with act"
	@echo "  screenshots        - Update reference screenshots for tests"
	@echo "  screenshots-clean  - Clean actual screenshots (failed comparisons)"
	@echo "  screenshots-diff   - View differences between expected and actual screenshots"
	@echo "  help           - Show this help message"

# Run tests in headless mode (suitable for CI)
test:
	@echo "Running tests in headless mode..."
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

# Run tests in interactive mode (for development)
test-interactive:
	@echo "Running tests in interactive mode..."
	nvim -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

# List all available test targets
test-list:
	@echo "Available test targets:"
	@echo ""
	@echo "Run all tests:"
	@echo "  make test                    # Run all tests (headless)"
	@echo "  make test-interactive        # Run all tests (interactive)"
	@echo ""
	@echo "Run specific test files:"
	@for name in $(TEST_NAMES); do \
		echo "  make test:$$name             # Run test_$$name.lua (headless)"; \
		echo "  make test:$$name-interactive # Run test_$$name.lua (interactive)"; \
	done
	@echo ""
	@echo "Run specific test case (example):"
	@echo "  make test:setup CASE=\"creates globals\""
	@echo "  make test:show-interactive CASE=\"handles hidden items correctly\""

# Generate test:name targets using the unified test script
define make_test_target
test\:$(1):
	@echo "Running test_$(1).lua tests..."
	@if [ -n "$$(CASE)" ]; then \
		echo "  Running specific case: $$(CASE)"; \
	fi
	@TEST_FILE="tests/test_$(1).lua" TEST_CASE="$$(CASE)" \
		nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

test\:$(1)-interactive:
	@echo "Running test_$(1).lua tests interactively..."
	@if [ -n "$$(CASE)" ]; then \
		echo "  Running specific case: $$(CASE)"; \
	fi
	@TEST_FILE="tests/test_$(1).lua" TEST_CASE="$$(CASE)" \
		nvim -u scripts/minimal_init.lua -c "luafile scripts/test.lua"
endef

# Create targets for all discovered test files
$(foreach name,$(TEST_NAMES),$(eval $(call make_test_target,$(name))))

# Format code with stylua and format markdown tables (if available)
format:
	@if command -v stylua >/dev/null 2>&1; then \
		echo "Formatting Lua code..."; \
		stylua lua/ tests/ scripts/; \
	else \
		echo "stylua not found. Install with: cargo install stylua"; \
	fi
	@echo "Formatting markdown tables in doc comments..."
	@lua scripts/format_tables.lua lua/ tests/ scripts/

# Check code formatting with stylua and table formatting (for CI)
format-check:
	@if command -v stylua >/dev/null 2>&1; then \
		echo "Checking Lua code formatting..."; \
		stylua --check lua/ tests/ scripts/; \
	else \
		echo "stylua not found. Install with: cargo install stylua"; \
		exit 1; \
	fi
	@echo "Checking markdown table formatting in doc comments..."
	@lua scripts/format_tables.lua --check lua/ tests/ scripts/

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
	@echo "Documentation generated in doc/Jumppack.txt"

# Check documentation generation (for CI)
doc-check:
	@echo "Checking if documentation is up-to-date..."
	@if [ ! -f doc/Jumppack.txt ]; then \
		echo "Error: doc/Jumppack.txt not found. Run 'make doc' first."; \
		exit 1; \
	fi
	@echo "Backing up existing documentation..."
	@cp doc/Jumppack.txt doc/Jumppack.txt.backup
	@echo "Generating temporary documentation for comparison..."
	@mkdir -p /tmp/jumppack-doccheck
	@if TEMP_DOC=/tmp/jumppack-doccheck/Jumppack.txt nvim --headless --noplugin \
		-u scripts/minimal_init.lua -c "luafile scripts/generate_docs.lua" -c "qa!" 2>/dev/null; then \
		mv doc/Jumppack.txt.backup doc/Jumppack.txt; \
		if diff -q doc/Jumppack.txt /tmp/jumppack-doccheck/Jumppack.txt >/dev/null 2>&1; then \
			echo "✓ Documentation is up-to-date"; \
			rm -rf /tmp/jumppack-doccheck; \
		else \
			echo "✗ Documentation is out of date!"; \
			echo "  Run 'make doc' to update and commit the changes."; \
			rm -rf /tmp/jumppack-doccheck; \
			exit 1; \
		fi; \
	else \
		mv doc/Jumppack.txt.backup doc/Jumppack.txt 2>/dev/null || true; \
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

# Screenshot management targets
screenshots:
	@echo "Updating reference screenshots..."
	JUMPPACK_TEST_SCREENSHOTS=update $(MAKE) test:jumps
	@echo "Reference screenshots updated!"

screenshots-clean:
	@echo "Cleaning actual screenshots..."
	@rm -f tests/screenshots/*.actual
	@echo "Actual screenshots cleaned!"

screenshots-diff:
	@echo "Showing differences between expected and actual screenshots..."
	@found_diffs=0; \
	for actual in tests/screenshots/*.actual; do \
		if [ -f "$$actual" ]; then \
			ref=$${actual%.actual}; \
			if [ -f "$$ref" ]; then \
				echo "=== Diff for $$ref ==="; \
				diff -u "$$ref" "$$actual" || true; \
				echo ""; \
				found_diffs=1; \
			fi; \
		fi; \
	done; \
	if [ $$found_diffs -eq 0 ]; then \
		echo "No screenshot differences found!"; \
	fi
