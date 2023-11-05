#!/bin/sh
#
# WAYBAR NORDVPN
#
# Source: https://github.com/etrigan63/wofi-nordvpn
#

# exit when any command fails
set -e

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis nordvpn > /dev/null || echoexit "'nordvpn' not found."

# nordvpn waybar module json format
waybar_json() {
  local status tooltip

  # get status
  status="$(nordvpn status | tr -d '\r-' | awk '{$1=$1;print}')"
  tooltip="$(printf %s "$status" | sed -z 's/\n/\\n/g')"
  tooltip="${tooltip::-2}"

  # if status disconnected
  if [[ $status == *"Disconnected"* ]]; then
    printf %s "{\"text\":\"Disconnected\",\"tooltip\":\"$tooltip\",\"class\":\"disconnected\",\"alt\":\"disconnected\"}"

  # if status connected
  elif [[ $status == *"Connected"* ]]; then
    local city host
  	city="$(printf %s "$status" | grep "City" | cut -d ":" -f 2 | tr -d ' ')"
  	host="$(printf %s "$status" | grep "Hostname" | cut -d ":" -f 2 | tr -d ' ' | cut -d "." -f 1)"
   	
    printf %s "{\"text\":\"$city ($host)\",\"tooltip\":\"$tooltip\",\"class\":\"connected\",\"alt\":\"connected\"}"

  # if status unknown
  else
    printf %s "{\"text\":\"Unknown\",\"tooltip\":\"Unable to access daemon.\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
  fi
}

# main
waybar_json
