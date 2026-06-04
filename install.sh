#!/bin/bash
# Install claude-switch into ~/.local/bin by default.
# Override with PREFIX=/path or BIN_DIR=/path/to/bin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/claude-switch"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
DEST="$BIN_DIR/claude-switch"

if [ ! -f "$SRC" ]; then
	echo "❌ claude-switch not found: $SRC" >&2
	exit 1
fi

if ! bash -n "$SRC"; then
	echo "❌ syntax check failed: $SRC" >&2
	exit 1
fi

mkdir -p "$BIN_DIR"
cp "$SRC" "$DEST"
chmod +x "$DEST"

echo "✅ installed: $DEST"

case ":$PATH:" in
*":$BIN_DIR:"*) ;;
*)
	echo "⚠️  $BIN_DIR is not in PATH"
	echo "   Add this to your shell config:"
	echo "   export PATH=\"$BIN_DIR:\$PATH\""
	;;
esac

if command -v claude-switch >/dev/null 2>&1; then
	echo "active command: $(command -v claude-switch)"
fi
