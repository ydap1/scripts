#!/usr/bin/env bash
# close (close-all-apps.sh)
# Quit/kill visible GUI apps on macOS.
# Short/Long options:
#   -n, --dry-run     : show which GUI apps would be quit/killed (no action)
#   -f, --force       : ask apps to quit then force-kill remaining
#   -F, --immediate   : immediately SIGKILL matching apps (no graceful quit)
#   -b, --no-browser  : exclude common web browsers
#   -h, --help        : show help
#
# Examples:
#   close -n            # dry-run
#   close -fb           # force remaining and don't close browsers (chained)
#   close -F            # immediate SIGKILL of matched apps 
#   close -nb           # dry-run & don't close browsers

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

DRY_RUN=0
FORCE=0
IMMEDIATE=0
NO_BROWSER=0

show_help() {
  cat <<-EOF
Usage: $SCRIPT_NAME [options]

Options:
  -n, --dry-run       Show which GUI apps would be quit/killed, do not perform actions.
  -f, --force         Ask apps to quit, then force-kill any that remain.
  -F, --immediate     Immediately SIGKILL matching apps (no graceful quit). WARNING: data loss possible.
  -b, --no-browser    Exclude common web browsers (Safari, Chrome, Firefox, etc.).
  -h, --help          Show this help message and exit.

Short flags can be chained, e.g.:
  $SCRIPT_NAME -fb   (same as -f -b)
  $SCRIPT_NAME -nF   (same as -n -F)

Notes:
  - The script excludes common terminal emulators by default so the shell running
    this command remains usable (Terminal, iTerm2, Alacritty, kitty, etc.).
  - Quitting Finder is included; macOS may relaunch Finder automatically.
  - Use --dry-run to preview which apps would be affected.

EOF
}

# ---- Preprocess args to support grouped short options (e.g. -fb) ----
RAW_ARGS=("$@")
PARSED_ARGS=()
for arg in "${RAW_ARGS[@]}"; do
  # preserve standalone "--"
  if [ "$arg" = "--" ]; then
    PARSED_ARGS+=("$arg")
    continue
  fi

  # long options remain intact
  if [[ "$arg" == --* ]]; then
    PARSED_ARGS+=("$arg")
    continue
  fi

  # single dash with multiple letters -> split (e.g. -fb -> -f -b)
  if [[ "$arg" == -[!-]* && ${#arg} -gt 2 ]]; then
    letters="${arg#-}"
    i=0
    while [ $i -lt ${#letters} ]; do
      PARSED_ARGS+=("-${letters:$i:1}")
      i=$((i + 1))
    done
    continue
  fi

  # otherwise keep as-is
  PARSED_ARGS+=("$arg")
done

# Replace positional params with expanded ones
set -- "${PARSED_ARGS[@]:-}"

# ---- Parse options ----
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1; shift ;;
    -f|--force)
      FORCE=1; shift ;;
    -F|--immediate)
      IMMEDIATE=1; FORCE=1; shift ;; # immediate implies force behavior
    -b|--no-browser)
      NO_BROWSER=1; shift ;;
    -h|--help)
      show_help; exit 0 ;;
    --)
      shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      show_help
      exit 2 ;;
    *)
      # positional args (none expected) — break for future extension
      break ;;
  esac
done

# Ensure macOS
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is for macOS (Darwin) only." >&2
  exit 1
fi

# Base excluded apps (so the terminal running this remains usable)
EXCLUDE_PROGS=("Terminal" "iTerm2" "iTerm" "Hyper" "Alacritty" "kitty" "WezTerm" "tmux" "Screen" "ssh")

# Add browser exclusions if requested
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
      skip=1; break
    fi
  done
  [ "$skip" -eq 1 ] && continue
  TO_QUIT+=("$app")
done

if [ ${#TO_QUIT[@]} -eq 0 ]; then
  echo "No GUI apps found to quit/kill (after exclusions)."
  exit 0
fi

echo "Apps targeted (${#TO_QUIT[@]}):"
for a in "${TO_QUIT[@]}"; do
  echo "  - $a"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--- Dry-run mode: no quitting/killing will be performed."
  exit 0
fi

# If immediate: skip graceful quit attempt and send SIGKILL right away
if [ "$IMMEDIATE" -eq 1 ]; then
  echo "Immediate mode: sending SIGKILL (no graceful quit) to targeted apps..."
  for app in "${TO_QUIT[@]}"; do
    echo "  SIGKILL -> $app"
    # try to find PIDs and kill -9 them; fallback to killall -9 by name
    pids=$(pgrep -f "$app" || true)
    if [ -n "$pids" ]; then
      echo "$pids" | xargs -r kill -9 >/dev/null 2>&1 || true
    else
      killall -9 "$app" >/dev/null 2>&1 || true
    fi
  done
  echo "Done (immediate SIGKILL)."
  exit 0
fi

# Normal behavior: ask apps to quit politely, then optionally force remaining
for app in "${TO_QUIT[@]}"; do
  echo "Requesting quit -> \"$app\"..."
  osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || true
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
  echo "Apps still running after polite quit:"
  for a in "${STILL_RUNNING[@]}"; do echo "  - $a"; done

  if [ "$FORCE" -eq 1 ]; then
    echo "Force-killing remaining apps..."
    for a in "${STILL_RUNNING[@]}"; do
      echo "  force -> $a"
      killall "$a" >/dev/null 2>&1 || true
      sleep 0.3
      still=$(osascript -e "tell application \"System Events\" to (exists application process \"$a\")")
      if [ "$still" = "true" ]; then
        pids=$(pgrep -f "$a" || true)
        if [ -n "$pids" ]; then
          echo "$pids" | xargs -r kill -9 >/dev/null 2>&1 || true
        else
          killall -9 "$a" >/dev/null 2>&1 || true
        fi
      fi
    done
    echo "Force-kill attempts finished."
  else
    echo "Run again with --force (or -f) to force-kill remaining apps."
  fi
fi

echo "Done."

