#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="close"
TARGET_DIR="/usr/local/bin"
TARGET_PATH="$TARGET_DIR/$SCRIPT_NAME"

if [ "$(id -u)" -ne 0 ]; then
  echo "This installer needs sudo to write to $TARGET_DIR."
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

# Check that source file exists
if [ ! -f "./close.sh" ]; then
  echo "Error: ./close.sh not found in current directory."
  echo "Run this installer from the same folder as close.sh."
  exit 1
fi

# Copy to /usr/local/bin
echo "Installing close.sh -> $TARGET_PATH"
cp ./close.sh "$TARGET_PATH"

# Make it executable
chmod +x "$TARGET_PATH"

echo "✅ Installed 'close' into $TARGET_PATH"
echo
echo "You can now run:"
echo "    close"
echo
echo "Try: close -n   # dry-run (shows what would be closed)"
echo "     close -f   # force kill stubborn apps (ask then kill)"
echo "     close -F   # immediate SIGKILL (no graceful shutdown)"
echo "     close -b   # do not kill browsers"
echo "     close -h   # show help"
echo "     close -Fbn # immediate SIGKILL, no browser, dry run"

