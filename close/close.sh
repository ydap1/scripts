#!/usr/bin/env bash
# close-all-apps.sh
# Quit/kill visible GUI apps on macOS, with options for force, immediate kill, browser exclusion, and dry-run.
# Supports short and long flags, including chained short flags (-fb, -nF, etc.)

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
  -n, --dry-run       Show which GUI apps would be targeted; do not quit/kill.
  -f, --force         Ask apps to quit politely, then force-kill any that remain.
  -F, --immediate     Immediately SIGKILL targeted apps (skips graceful quit) except Finder, which is quit normally.
  -b, --no-browser    Exclude common web browsers from being closed.
  -h, --help          Show this help text and exit.

Short flags can be chained, e.g.:
  $SCRIPT_NAME -fb   (same as -f -b)
  $SCRIPT_NAME -nF   (same as -n -F)
EOF
}

# ---- Preprocess args to support grouped short options ----
RAW_ARGS=("$@")
PARSED_ARGS=()
for arg in "${RAW_ARGS[@]}"; do
  if [ "$arg" = "--" ]; then
    PARSED_ARGS+=("$arg")
    continue
  fi
  if [[ "$arg" == --* ]]; then
    PARSED_ARGS+=("$arg")
    continue
  fi
  if [[ "$arg" == -[!-]* && ${#arg} -gt 2 ]]; then
    letters="${arg#-}"
    for ((i=0;i<${#letters};i++)); do
      PARSED_ARGS+=("-${letters:$i:1}")
    done
    continue
  fi
  PARSED_ARGS+=("$arg")
done
set -- "${PARSED_ARGS[@]:-}"

# ---- Parse options ----
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1; shift ;;
    -f|--force)
      FORCE=1; shift ;;
    -F|--immediate)
      IMMEDIATE=1; FORCE=1; shift ;;
    -b|--no-browser)
      NO_BROWSER=1; shift ;;
    -h|--help)
      show_help; exit 0 ;;
    --)
      shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      show_help; exit 2 ;;
    *)
      break ;;
  esac
done

# Ensure macOS
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is for macOS only." >&2
  exit 1
fi

# Base excluded apps (so your terminal stays alive)
EXCLUDE_PROGS=("Terminal" "iTerm2" "iTerm" "Hyper" "Alacritty" "kitty" "WezTerm" "tmux" "Screen" "ssh")

# Add browser exclusions if requested
if [ "$NO_BROWSER" -eq 1 ]; then
  BROWSERS_TO_EXCLUDE=(
    "Safari" "Safari Technology Preview"
    "Google Chrome" "Google Chrome Canary"
    "Firefox" "Brave Browser"
    "Microsoft Edge" "Chromium" "Opera" "Vivaldi" "Tor Browser"
  )
  EXCLUDE_PROGS+=("${BROWSERS_TO_EXCLUDE[@]}")
fi

# Get list of running GUI apps
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
    [ "$app" = "$ex" ] && skip=1 && break
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

# Immediate mode: SIGKILL all except Finder
if [ "$IMMEDIATE" -eq 1 ]; then
  echo "Immediate mode: sending SIGKILL to targeted apps (excluding Finder)..."
  for app in "${TO_QUIT[@]}"; do
    [ "$app" = "Finder" ] && continue
    echo "  SIGKILL -> $app"
    pids=$(pgrep -f "$app" || true)
    if [ -n "$pids" ]; then
      echo "$pids" | xargs -r kill -9 >/dev/null 2>&1 || true
    else
      killall -9 "$app" >/dev/null 2>&1 || true
    fi
  done

  # Now quit Finder gracefully if present
  for app in "${TO_QUIT[@]}"; do
    [ "$app" = "Finder" ] || continue
    echo "Requesting quit -> \"$app\"..."
    osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || true
  done

  echo "Done (immediate kill + Finder quit)."
  exit 0
fi

# Normal force mode: graceful quit then optional force
for app in "${TO_QUIT[@]}"; do
  echo "Requesting quit -> \"$app\"..."
  osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || true
  sleep 0.4
done

sleep 0.8

STILL_RUNNING=()
for app in "${TO_QUIT[@]}"; do
  is_running=$(osascript -e "tell application \"System Events\" to (exists application process \"$app\")")
  [ "$is_running" = "true" ] && STILL_RUNNING+=("$app")
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

