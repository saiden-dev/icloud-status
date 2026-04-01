#!/bin/sh
set -eu

REPO="saiden-dev/icloud-status"
INSTALL_DIR="${ICLOUD_STATUS_INSTALL_DIR:-/usr/local/bin}"

main() {
  need_cmd curl
  need_cmd uname
  need_cmd tar

  os=$(uname -s)
  arch=$(uname -m)

  if [ "$os" != "Darwin" ]; then
    err "icloud-status is macOS only"
  fi

  version=$(latest_version)
  url="https://github.com/${REPO}/releases/download/${version}/icloud-status-${version}-macos.tar.gz"

  printf "Installing icloud-status %s (macOS/%s)\n" "$version" "$arch"
  printf "  from: %s\n" "$url"
  printf "  to:   %s/icloud-status\n" "$INSTALL_DIR"

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  curl -fsSL "$url" -o "${tmp}/icloud-status.tar.gz"
  tar xzf "${tmp}/icloud-status.tar.gz" -C "${tmp}"
  chmod +x "${tmp}/icloud-status"

  if [ -w "$INSTALL_DIR" ]; then
    mv "${tmp}/icloud-status" "${INSTALL_DIR}/icloud-status"
  else
    printf "\nElevated permissions required to install to %s\n" "$INSTALL_DIR"
    sudo mv "${tmp}/icloud-status" "${INSTALL_DIR}/icloud-status"
  fi

  printf "\nicloud-status %s installed successfully.\n" "$version"
  printf "Run 'icloud-status --help' to get started.\n"
}

latest_version() {
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' \
    | head -1 \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'
}

need_cmd() {
  if ! command -v "$1" > /dev/null 2>&1; then
    err "required command not found: $1"
  fi
}

err() {
  printf "error: %s\n" "$1" >&2
  exit 1
}

main
