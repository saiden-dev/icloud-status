# icloud-status - macOS iCloud status CLI tool

name := "icloud-status"
version := "0.2.0"
install_dir := env_var("HOME") / "bin"

# Default recipe: show help
default:
    @just --list

# Build release binary
build:
    swift build -c release

# Build debug binary
build-debug:
    swift build

# Run the tool
run *ARGS:
    swift run {{name}} {{ARGS}}

# Run in watch mode
watch:
    swift run {{name}} --watch

# Show brief status
brief:
    swift run {{name}} --brief

# Install to ~/bin
install: build
    @mkdir -p {{install_dir}}
    cp .build/release/{{name}} {{install_dir}}/{{name}}
    @echo "Installed to {{install_dir}}/{{name}}"

# Uninstall from ~/bin
uninstall:
    rm -f {{install_dir}}/{{name}}
    @echo "Uninstalled {{install_dir}}/{{name}}"

# Clean build artifacts
clean:
    swift package clean
    rm -rf .build
    @echo "Cleaned build directory"

# Update dependencies
update:
    swift package update

# Resolve dependencies
resolve:
    swift package resolve

# Show dependencies
deps:
    swift package show-dependencies

# Show version
version:
    @echo "{{name}} v{{version}}"

# Format source (requires swift-format)
fmt:
    swift-format -i -r Sources/ 2>/dev/null || echo "swift-format not installed (brew install swift-format)"

# Install to /usr/local/bin (requires sudo)
install-global: build
    sudo cp .build/release/{{name}} /usr/local/bin/{{name}}
    @echo "Installed to /usr/local/bin/{{name}}"

# Create release archive
release: build
    @mkdir -p releases
    tar -czvf releases/{{name}}-{{version}}-darwin-$(uname -m).tar.gz -C .build/release {{name}}
    @echo "Created releases/{{name}}-{{version}}-darwin-$(uname -m).tar.gz"

# Run tests
test:
    swift test

# Generate Xcode project
xcode:
    swift package generate-xcodeproj
    @echo "Generated {{name}}.xcodeproj"
