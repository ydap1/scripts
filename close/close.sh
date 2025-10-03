#!/usr/bin/env bash
# close-all-apps.sh
# Quit all visible GUI apps on macOS (including Finder).
#   -n, --dry-run       : show what would be quit (no quitting)
#   -f, --force         : force-kill apps that refuse to quit
#   -b, --no-browser    : do NOT close browsers
#   -h, --help          : show this help message
#
# Examples:
#   close                 # quit apps
#   close -n              # dry-run
#   close --dry-run       # same as -n
#   close -b              # don't close browsers
#   close -f --no-browser # force-kill, but don't touch browsers

set -euo pipefail

DRY_RUN=0
FORCE=0
NO_BROWSER=0

SCRIPT_NAME="$(basename "$0")"

show_help() {
  cat <<-EOF
Usage: $SCRIPT_NAME [options]

Options:
  -n, --dry-run       Show which GUI apps would be quit, do not quit them.
  -f, --force         After asking apps to quit, force-kill any that remain.
  -b, --no-browser    Exclude common web browsers (Safari, Chrome, Firefox, etc.).
  -h, --help          Show this help message and exit.

Notes:
  - The script excludes common terminal emulators by default so the shell running
    this command remains usable (Terminal, iTerm2, Alacritty, kitty, WezTerm, etc.).
  - Quitting Finder is included; macOS may relaunch Finder automatically.
  - You may lose unsaved work in apps that are quit. Use --dry-run to preview.

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME -n
  $SCRIPT_NAME --dry-run --no-browser
  $SCRIPT_NAME -f -b

EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    -b|--no-browser)
      NO_BROWSER=1
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    --) # end of options
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      show_help
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

# Ensure macOS
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is for macOS (Darwin) only." >&2
  exit 1
fi

# apps to exclude so we don't kill the terminal running this script
EXCLUDE_PROGS=("Terminal" "iTerm2" "iTerm" "Hyper" "Alacritty" "kitty" "WezTerm" "WezTerm.app" "tmux" "Screen" "ssh")

# If requested, add common browsers to the exclusion list
if [ "$NO_BROWSER" -eq 1 ]; then
  BROWSERS_TO_EXCLUDE=(
    "Safari"
    "Safari Technology Preview"
    "Google Chrome"
    "Google Chrome Canary"
    "Firefox"
    "Brave Browser"
    "Microsoft Edge"
    "Chromium"
    "Opera"
    "Vivaldi"
    "Tor Browser"
  )
  EXCLUDE_PROGS+=("${BROWSERS_TO_EXCLUDE[@]}")
fi

# Get list of running GUI app names (non-background processes)
raw_apps=$(osascript -e 'tell application "System Events" to get name of (application processes whose background only is false)') || raw_apps=""
IFS=',' read -ra APP_ARRAY <<< "$raw_apps"

_trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf "%s" "$var"
}

TO_QUIT=()
for raw in "${APP_ARRAY[@]}"; do
  app=$(_trim "$raw")
  [ -z "$app" ] && continue
  skip=0
  for ex in "${EXCLUDE_PROGS[@]}"; do
    if [ "$app" = "$ex" ]; then
      skip=1
      break
    fi
  done
  [ "$skip" -eq 1 ] && continue
  TO_QUIT+=("$app")
done

if [ ${#TO_QUIT[@]} -eq 0 ]; then
  echo "No GUI apps found to quit (after exclusions)."
  exit 0
fi

echo "Apps to be quit (${#TO_QUIT[@]}):"
for a in "${TO_QUIT[@]}"; do
  echo "  - $a"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--- Dry-run mode: no apps will be quit."
  [ "$FORCE" -eq 1 ] && echo "Note: --force given but not applied during dry-run."
  exit 0
fi

for app in "${TO_QUIT[@]}"; do
  echo "Quitting \"$app\"..."
  # Request application to quit politely
  osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || true
  # slight delay to let app process the quit request
  sleep 0.4
done

sleep 0.8

STILL_RUNNING=()
for app in "${TO_QUIT[@]}"; do
  is_running=$(osascript -e "tell application \"System Events\" to (exists application process \"$app\")")
  if [ "$is_running" = "true" ]; then
    STILL_RUNNING+=("$app")
  fi
done

if [ ${#STILL_RUNNING[@]} -eq 0 ]; then
  echo "All requested apps quit successfully (or restarted automatically)."
else
  echo "These apps did not quit:"
  for a in "${STILL_RUNNING[@]}"; do echo "  - $a"; done
  if [ "$FORCE" -eq 1 ]; then
    echo "Force-killing..."
    for a in "${STILL_RUNNING[@]}"; do
      # gentle first
      killall "$a" >/dev/null 2>&1 || true
      sleep 0.3
      still=$(osascript -e "tell application \"System Events\" to (exists application process \"$a\")")
      if [ "$still" = "true" ]; then
        # escalate: find PIDs and SIGKILL them
        pids=$(pgrep -f "$a" || true)
        if [ -n "$pids" ]; then
          echo "$pids" | xargs -r kill -9 >/dev/null 2>&1 || true
        else
          killall -9 "$a" >/dev/null 2>&1 || true
        fi
      fi
    done
    echo "Force-kill finished."
  else
    echo "Run again with --force (or -f) to attempt force-kill of remaining apps."
  fi
fi

echo "Done."

