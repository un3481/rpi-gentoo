#!/bin/sh
#
# WAYBAR CHECKUPDATES
#
# Source: https://github.com/coffebar/waybar-module-pacman-updates 
#

# exit when any command fails
set -T

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis checkupdates > /dev/null || echoexit "'checkupdates' not found."

# TMP File for storing timestamp
TMPDIR="/tmp"
LASTRUN_FILE="$TMPDIR/waybar-module-checkupdates.lastrun"

# calculate diff from last update
touch "$LASTRUN_FILE"
lastrun=$(cat "$LASTRUN_FILE")
if [ "$lastrun" = "" ]; then
  lastrun="0"
fi

now=$(date '+%s')
diff=$(($now - $lastrun))

# if diff > 5 min then update
if [ $diff -gt 300 ]; then
  checkupdates --nocolor
  echo -e "$now" > "$LASTRUN_FILE"
fi

# Get current updates
updates=$(checkupdates --nocolor --nosync)

# Check current updates
if [[ $updates == *"->"* ]]; then
  update_count=$(echo -e "$updates" | tr " " "\n" | grep -c "\->")
  tooltip=$(echo -e "$updates" | sed "s/\"/\\\"/g" | sed "s/\n/\\n/g")
  printf "%s" "{\"text\":\"$update_count\",\"tooltip\":\"$tooltip\",\"class\":\"has-updates\",\"alt\":\"has-updates\"}"

elif [ "$updates" == "" ]; then
  printf "%s" "{\"text\":\"0\",\"tooltip\":\"System updated\",\"class\":\"updated\",\"alt\":\"updated\"}"

else
  printf "%s" "{\"text\":\"?\",\"tooltip\":\"Unknown response from checkupdates\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
fi

