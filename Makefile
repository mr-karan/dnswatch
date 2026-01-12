.PHONY: build run clean xcode lint format

# App configuration
APP_NAME = DNSWatch
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

# Compiler flags
SWIFT_FLAGS = -O
LINK_FLAGS = -lpcap

# Source files
SOURCES = $(shell find DNSWatch/Sources -name "*.swift")

build: $(APP_BUNDLE)

$(APP_BUNDLE): $(SOURCES)
	@echo "Building $(APP_NAME)..."
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources

	# Compile Swift sources
	swiftc \
		$(SWIFT_FLAGS) \
		-sdk $(shell xcrun --show-sdk-path) \
		-target arm64-apple-macos14.0 \
		$(LINK_FLAGS) \
		-o $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) \
		$(SOURCES)

	# Copy Info.plist
	@cp DNSWatch/Resources/Info.plist $(APP_BUNDLE)/Contents/
	@sed -i '' 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' $(APP_BUNDLE)/Contents/Info.plist
	@sed -i '' 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.dnswatch.app/g' $(APP_BUNDLE)/Contents/Info.plist
	@sed -i '' 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' $(APP_BUNDLE)/Contents/Info.plist
	@sed -i '' 's/$$(MACOSX_DEPLOYMENT_TARGET)/14.0/g' $(APP_BUNDLE)/Contents/Info.plist

	# Copy app icon
	@cp DNSWatch/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/

	@echo "Build complete: $(APP_BUNDLE)"

run: build
	@echo "Running $(APP_NAME)..."
	@echo "Note: You may need to grant BPF permissions first:"
	@echo "  sudo chmod o+r /dev/bpf*"
	@open $(APP_BUNDLE)

run-sudo: build
	@echo "Running $(APP_NAME) with sudo..."
	@sudo $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned build directory"

# Lint code (CI mode - fails on issues)
lint:
	@echo "Running SwiftFormat lint..."
	@swiftformat DNSWatch/Sources --lint
	@echo "Running SwiftLint..."
	@swiftlint --strict

# Format code (auto-fix)
format:
	@echo "Formatting code..."
	@swiftformat DNSWatch/Sources
	@echo "Format complete"

# Generate Xcode project using xcodegen (if installed)
xcode:
	@if command -v xcodegen &> /dev/null; then \
		xcodegen generate; \
		open $(APP_NAME).xcodeproj; \
	else \
		echo "xcodegen not found. Install with: brew install xcodegen"; \
		echo "Or create project manually in Xcode (see README.md)"; \
	fi

# Grant BPF permissions (requires sudo)
permissions:
	@echo "Granting read permissions to BPF devices..."
	@sudo chmod o+r /dev/bpf*
	@echo "Done. You may need to re-run this after reboot."

help:
	@echo "DNSWatch Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make build       - Build the app bundle"
	@echo "  make run         - Build and run (needs BPF permissions)"
	@echo "  make run-sudo    - Build and run with sudo"
	@echo "  make clean       - Remove build artifacts"
	@echo "  make lint        - Run linters (swiftformat + swiftlint)"
	@echo "  make format      - Auto-format code with swiftformat"
	@echo "  make xcode       - Generate Xcode project (needs xcodegen)"
	@echo "  make permissions - Grant BPF device permissions (needs sudo)"
	@echo ""
	@echo "Before running, you need BPF permissions. Either:"
	@echo "  1. Run: sudo chmod o+r /dev/bpf*"
	@echo "  2. Use: make run-sudo"
