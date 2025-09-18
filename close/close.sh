#!/usr/bin/env bash
# close-all-apps.sh
# Quit all visible GUI apps on macOS (including Finder).
# Usage:
#   close          # once installed in your shell (see instructions below)
#   close -n       # dry-run (show apps but don’t quit)
#   close -f       # force-kill stubborn apps
#   close -nf      # dry-run + force (force skipped in dry-run)

set -u
DRY_RUN=0
FORCE=0

# parse flags
while getopts ":nf" opt; do
  case ${opt} in
    n ) DRY_RUN=1 ;;
    f ) FORCE=1 ;;
    \? ) echo "Usage: $0 [-n dry-run] [-f force]"; exit 2 ;;
  esac
done

# ensure macOS
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is for macOS (Darwin) only." >&2
  exit 1
fi

# apps to exclude so we don't kill the terminal running this script
EXCLUDE_PROGS=("Terminal" "iTerm2" "iTerm" "Hyper" "Alacritty" "kitty" "WezTerm" "tmux" "Screen" "ssh")

# Get list of running GUI app names
raw_apps=$(osascript -e 'tell application "System Events" to get name of (application processes whose background only is false)')
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
  echo "No GUI apps found to quit (after exclusions)."
  exit 0
fi

echo "Apps to be quit (${#TO_QUIT[@]}):"
for a in "${TO_QUIT[@]}"; do
  echo "  - $a"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--- Dry-run mode: no apps will be quit."
  [ "$FORCE" -eq 1 ] && echo "Note: force flag given but not applied during dry-run."
  exit 0
fi

for app in "${TO_QUIT[@]}"; do
  echo "Quitting \"$app\"..."
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
  echo "These apps did not quit:"
  for a in "${STILL_RUNNING[@]}"; do echo "  - $a"; done
  if [ "$FORCE" -eq 1 ]; then
    echo "Force-killing..."
    for a in "${STILL_RUNNING[@]}"; do
      killall "$a" >/dev/null 2>&1 || true
      sleep 0.3
      still=$(osascript -e "tell application \"System Events\" to (exists application process \"$a\")")
      if [ "$still" = "true" ]; then
        pids=$(pgrep -f "$a" || true)
        [ -n "$pids" ] && echo "$pids" | xargs -r kill -9 >/dev/null 2>&1 || killall -9 "$a" >/dev/null 2>&1 || true
      fi
    done
    echo "Force-kill finished."
  else
    echo "Run again with -f to force-kill."
  fi
fi

echo "Done."

