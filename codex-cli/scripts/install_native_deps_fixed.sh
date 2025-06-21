#!/usr/bin/env bash

# Fixed version of install_native_deps.sh that works around the gh command conflict
#
# This script temporarily renames the conflicting gh command to allow
# the real GitHub CLI to work during the installation process.

set -euo pipefail

# ------------------
# Parse arguments (same as original)
# ------------------

DEST_DIR=""
INCLUDE_RUST=0

for arg in "$@"; do
  case "$arg" in
    --full-native)
      INCLUDE_RUST=1
      ;;
    *)
      if [[ -z "$DEST_DIR" ]]; then
        DEST_DIR="$arg"
      else
        echo "Unexpected argument: $arg" >&2
        exit 1
      fi
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Determine where the binaries should be installed (same as original)
# ----------------------------------------------------------------------------

if [[ $# -gt 0 ]]; then
  CODEX_CLI_ROOT="$1"
  BIN_DIR="$CODEX_CLI_ROOT/bin"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CODEX_CLI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  BIN_DIR="$CODEX_CLI_ROOT/bin"
fi

mkdir -p "$BIN_DIR"

# ----------------------------------------------------------------------------
# Work around the gh command conflict
# ----------------------------------------------------------------------------

# Check if the system gh command is the GitHub CLI
GH_IS_GITHUB_CLI=false
if /usr/bin/gh --version 2>/dev/null | grep -q "gh version"; then
    GH_IS_GITHUB_CLI=true
    echo "Found GitHub CLI at /usr/bin/gh"
else
    echo "GitHub CLI not found at /usr/bin/gh, using the one in PATH"
fi

# Temporarily rename the conflicting gh command if it exists and is not GitHub CLI
CUSTOM_GH_RENAMED=false
if [[ -f /usr/local/bin/gh ]] && ! /usr/local/bin/gh --version 2>/dev/null | grep -q "gh version"; then
    echo "Temporarily renaming conflicting gh command..."
    sudo mv /usr/local/bin/gh /usr/local/bin/gh.backup
    CUSTOM_GH_RENAMED=true
fi

# Function to restore the custom gh command
restore_custom_gh() {
    if [[ "$CUSTOM_GH_RENAMED" == "true" ]]; then
        echo "Restoring custom gh command..."
        sudo mv /usr/local/bin/gh.backup /usr/local/bin/gh
    fi
}

# Set up trap to restore the custom gh command on exit
trap restore_custom_gh EXIT

# ----------------------------------------------------------------------------
# Download and decompress the artifacts from the GitHub Actions workflow
# ----------------------------------------------------------------------------

WORKFLOW_URL="https://github.com/openai/codex/actions/runs/15483730027"
WORKFLOW_ID="${WORKFLOW_URL##*/}"

ARTIFACTS_DIR="$(mktemp -d)"
trap 'rm -rf "$ARTIFACTS_DIR"; restore_custom_gh' EXIT

# Use the correct GitHub CLI binary
if [[ "$GH_IS_GITHUB_CLI" == "true" ]]; then
    GH_CMD="/usr/bin/gh"
else
    GH_CMD="gh"
fi

echo "Using GitHub CLI: $GH_CMD"
"$GH_CMD" run download --dir "$ARTIFACTS_DIR" --repo openai/codex "$WORKFLOW_ID"

# Decompress the artifacts for Linux sandboxing (force overwrite existing files)
zstd -d --force "$ARTIFACTS_DIR/x86_64-unknown-linux-musl/codex-linux-sandbox-x86_64-unknown-linux-musl.zst" \
     -o "$BIN_DIR/codex-linux-sandbox-x64"

zstd -d --force "$ARTIFACTS_DIR/aarch64-unknown-linux-musl/codex-linux-sandbox-aarch64-unknown-linux-musl.zst" \
     -o "$BIN_DIR/codex-linux-sandbox-arm64"

if [[ "$INCLUDE_RUST" -eq 1 ]]; then
  # x64 Linux
  zstd -d --force "$ARTIFACTS_DIR/x86_64-unknown-linux-musl/codex-x86_64-unknown-linux-musl.zst" \
      -o "$BIN_DIR/codex-x86_64-unknown-linux-musl"
  # ARM64 Linux
  zstd -d --force "$ARTIFACTS_DIR/aarch64-unknown-linux-musl/codex-aarch64-unknown-linux-musl.zst" \
      -o "$BIN_DIR/codex-aarch64-unknown-linux-musl"
  # x64 macOS
  zstd -d --force "$ARTIFACTS_DIR/x86_64-apple-darwin/codex-x86_64-apple-darwin.zst" \
      -o "$BIN_DIR/codex-x86_64-apple-darwin"
  # ARM64 macOS
  zstd -d --force "$ARTIFACTS_DIR/aarch64-apple-darwin/codex-aarch64-apple-darwin.zst" \
      -o "$BIN_DIR/codex-aarch64-apple-darwin"
fi

echo "Installed native dependencies into $BIN_DIR"