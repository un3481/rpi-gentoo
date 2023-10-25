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

# temporary file for storing timestamp
TMPDIR="/tmp"
TMPFILE="$TMPDIR/waybar-module-checkupdates.lastrun"

# update checkupdates local database
update_db() {
  local lastrun_file preset lastrun thisrun elapsed
  lastrun_file=$1
  preset=$2

  # create file if not exists
  touch "$lastrun_file"

  # get timestamp of last run
  lastrun=$(cat "$lastrun_file")
  if [[ "$lastrun" == "" ]]; then
    lastrun="0"
  fi

  # calculate elapsed time since last run
  thisrun=$(date '+%s')
  elapsed=$(($thisrun - $lastrun))

  # update if elapsed time >= preset time
  if (( $elapsed >= $preset )); then
    checkupdates --nocolor
    echo -e "$thisrun" > "$lastrun_file"
  fi
}

# checkupdates waybar module json format
waybar_json() {
  local updates

  # get available updates
  updates=$(checkupdates --nocolor --nosync)

  # if updates found
  if [[ $updates == *"->"* ]]; then
    local update_count tooltip
    update_count=$(echo -e "$updates" | tr " " "\n" | grep -c "\->")
    tooltip=$(echo -e "$updates" | sed "s/\"/\\\"/g" | sed "s/\n/\\n/g")

    printf %s "{\"text\":\"$update_count\",\"tooltip\":\"$tooltip\",\"class\":\"has-updates\",\"alt\":\"has-updates\"}"

  # if updates not found
  elif [[ "$updates" == "" ]]; then
    printf %s "{\"text\":\"0\",\"tooltip\":\"System updated\",\"class\":\"updated\",\"alt\":\"updated\"}"

  # if unknown response given
  else
    printf %s "{\"text\":\"?\",\"tooltip\":\"Unknown response from checkupdates\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
  fi
}

# main
update_db $TMPFILE 300
waybar_json
