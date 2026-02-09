# icloud-status - macOS iCloud status CLI tool

name := "icloud-status"
version := "0.1.0"
src := "src/main.swift"
build_dir := "build"
install_dir := env_var("HOME") / "bin"

# Default recipe: show help
default:
    @just --list

# Build the release binary
build:
    @mkdir -p {{build_dir}}
    swiftc -O -o {{build_dir}}/{{name}} {{src}}
    @echo "Built {{build_dir}}/{{name}}"

# Build debug binary
build-debug:
    @mkdir -p {{build_dir}}
    swiftc -g -o {{build_dir}}/{{name}}-debug {{src}}
    @echo "Built {{build_dir}}/{{name}}-debug"

# Run the tool (builds first if needed)
run: build
    {{build_dir}}/{{name}}

# Install to ~/bin
install: build
    @mkdir -p {{install_dir}}
    cp {{build_dir}}/{{name}} {{install_dir}}/{{name}}
    @echo "Installed to {{install_dir}}/{{name}}"

# Uninstall from ~/bin
uninstall:
    rm -f {{install_dir}}/{{name}}
    @echo "Uninstalled {{install_dir}}/{{name}}"

# Clean build artifacts
clean:
    rm -rf {{build_dir}}
    @echo "Cleaned build directory"

# Run as script (no compilation)
script:
    swift {{src}}

# Show version
version:
    @echo "{{name}} v{{version}}"

# Format source (requires swift-format)
fmt:
    swift-format -i {{src}} 2>/dev/null || echo "swift-format not installed"

# Check syntax without building
check:
    swiftc -parse {{src}}
    @echo "Syntax OK"

# Install to /usr/local/bin (requires sudo)
install-global: build
    sudo cp {{build_dir}}/{{name}} /usr/local/bin/{{name}}
    @echo "Installed to /usr/local/bin/{{name}}"

# Create release archive
release: build
    @mkdir -p releases
    tar -czvf releases/{{name}}-{{version}}-darwin.tar.gz -C {{build_dir}} {{name}}
    @echo "Created releases/{{name}}-{{version}}-darwin.tar.gz"
