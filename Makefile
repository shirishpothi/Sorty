# Sorty Makefile

.PHONY: build run debug test test-full test-ui clean help cli install-cli install quick now

# Default target
all: build

build:
	@chmod +x scripts/build.sh
	@./scripts/build.sh

run: build
	@echo "🚀 Launching Sorty..."
	@open releases/Sorty.app

# builds with debug symbols and verbose logging
debug:
	@echo "🛠️  Building in DEBUG mode..."
	@BUILD_CONFIG=debug ./scripts/build.sh
	@echo "🚀 Launching Debug Build..."
	@open releases/Sorty.app

# runs the complete test suite with coverage reports
test:
	@echo "🧪 Running unit tests..."
	@swift test

test-full:
	@echo "🧪 Running unit tests with coverage..."
	@swift test --enable-code-coverage
	@echo "🖥️  Running UI tests..."
	@chmod +x scripts/run_tests.sh
	@./scripts/run_tests.sh --ui
	@echo "✅ All tests completed. Coverage reports available in .build/debug/codecov"

test-ui:
	@echo "🖥️  Running UI tests..."
	@chmod +x scripts/run_tests.sh
	@./scripts/run_tests.sh --ui

# runs basic syntax checks and builds (skips tests)
quick:
	@echo "⚡ Quick build (skipping tests)..."
	@SKIP_TESTS=true ./scripts/build.sh

# skips all checks and builds/runs immediately
now:
	@echo "🏎️  Immediate build and run..."
	@SKIP_TESTS=true ./scripts/build.sh
	@open releases/Sorty.app

clean:
	@echo "🧹 Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@rm -rf releases/
	@echo "✨ Clean complete"

# Build the learnings CLI tool
cli:
	@echo "🔨 Building learnings CLI..."
	@swift build --product learnings
	@echo "✅ CLI built at .build/debug/learnings"

# Install app to /Applications
install: build
	@echo "📦 Installing Sorty to /Applications..."
	@cp -R releases/Sorty.app /Applications/Sorty.app
	@echo "✅ Installed! You can now find Sorty in your Applications folder."

# Install CLI to /usr/local/bin
install-cli: cli
	@echo "📦 Installing learnings CLI to /usr/local/bin..."
	@sudo cp .build/debug/learnings /usr/local/bin/learnings
	@echo "✅ Installed! Run with: learnings --help"

help:
	@echo "Sorty Build System"
	@echo "=================="
	@echo "Available commands:"
	@echo "  make build       - Compile and update the .app bundle (runs unit tests)"
	@echo "  make run         - Build and launch the app"
	@echo "  make debug       - Build in DEBUG mode and launch"
	@echo "  make quick       - Compile immediately (skips tests)"
	@echo "  make now         - Build fast and launch immediately (skips tests)"
	@echo ""
	@echo "Testing:"
	@echo "  make test        - Run unit tests"
	@echo "  make test-ui     - Run UI tests (macOS)"
	@echo "  make test-full   - Run unit and UI tests"
	@echo ""
	@echo "Utility:"
	@echo "  make clean       - Remove all build artifacts and releases"
	@echo "  make install     - Copy built app to /Applications"
	@echo "  make cli         - Build the 'learnings' CLI tool"
	@echo "  make install-cli - Install 'learnings' CLI to /usr/local/bin"
	@echo "  make help        - Show this help message"
