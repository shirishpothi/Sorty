# FileOrganizer Makefile

.PHONY: build run test clean help cli install-cli

# Default target
all: build

build:
	@chmod +x build.sh
	@./build.sh

run: build
	@echo "🚀 Launching FileOrganizer..."
	@open FileOrganizer.app

test:
	@echo "🧪 Running Swift tests..."
	@swift test

clean:
	@echo "🧹 Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@rm -rf FileOrganizer.app/Contents/MacOS/FileOrganizerApp
	@echo "✨ Clean complete"

# Build the learnings CLI tool
cli:
	@echo "🔨 Building learnings CLI..."
	@swift build --product learnings
	@echo "✅ CLI built at .build/debug/learnings"
	@echo ""
	@echo "Run with: .build/debug/learnings --help"

# Install CLI to /usr/local/bin
install-cli: cli
	@echo "📦 Installing learnings CLI to /usr/local/bin..."
	@sudo cp .build/debug/learnings /usr/local/bin/learnings
	@echo "✅ Installed! Run with: learnings --help"

help:
	@echo "Available commands:"
	@echo "  make build       - Compile and update the .app bundle"
	@echo "  make run         - Build and launch the app"
	@echo "  make test        - Run all Swift tests"
	@echo "  make clean       - Remove build artifacts"
	@echo "  make cli         - Build the learnings CLI tool"
	@echo "  make install-cli - Install CLI to /usr/local/bin (requires sudo)"

