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
LASTRUN_FILE="$TMPDIR/waybar-module-checkupdates.lastrun"

# update checkupdates local database
check_outdated() {
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

  # write to lastrun file
  echo -e "$thisrun" > "$lastrun_file"

  # return elapsed time >= preset time
  if (( $elapsed >= $preset )); then
    printf %s "outdated"
  else
    printf %s "up-to-date"
  fi
}

# checkupdates waybar module json format
waybar_json() {
  local updates updates_array update_count

  # get available updates
  updates=$(checkupdates --nocolor --nosync)
  updates_array=()
  IFS=$'\n' read -rd '' -a updates_array <<< "$updates"
  update_count=${#updates_array[@]}

  # if updates found
  if (( $update_count > 0 )); then
    for i in "${updates_array[@]}"; do
      tooltip="$tooltip\n$i"
    done
    tooltip=$(printf %s "$tooltip" | sed "s/\"/\\\"/g" | sed "s/\n/\\n/g")
    tooltip="${tooltip:2}"

    printf %s "{\"text\":\"$update_count\",\"tooltip\":\"$tooltip\",\"class\":\"has-updates\",\"alt\":\"has-updates\"}"

  # if updates not found
  elif (( $update_count == 0 )); then
    printf %s "{\"text\":\"0\",\"tooltip\":\"System updated\",\"class\":\"updated\",\"alt\":\"updated\"}"

  # if unknown response given
  else
    printf %s "{\"text\":\"?\",\"tooltip\":\"Unknown response from checkupdates\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
  fi
}

# main
outdated=$(check_outdated $LASTRUN_FILE 300)
if [[ "$outdated" == "outdated" ]]; then
  nohup checkupdates &
fi
waybar_json
