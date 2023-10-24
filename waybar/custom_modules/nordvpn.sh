#!/bin/sh
#
#   NORDVPN-STATUS: A part of wofi-nordvpn
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

# Get status.
status="$(nordvpn status | tr -d '\r-' | awk '{$1=$1;print}')"
tooltip="$(echo "$status" | sed -z 's/\n/\\n/g')"
tooltip="${tooltip::-2}"

# Check status
if [[ $status == *"Disconnected"* ]]; then
  printf "%s" "{\"text\":\"Disconnected\",\"tooltip\":\"$tooltip\",\"class\":\"disconnected\",\"alt\":\"disconnected\"}"

elif [[ $status == *"Connected"* ]]; then
	stts_city="$(echo "$status" | grep "City" | cut -d ":" -f 2 | tr -d ' ')"
	stts_host="$(echo "$status" | grep "Hostname" | cut -d ":" -f 2 | tr -d ' ' | cut -d "." -f 1)"
 	printf "%s" "{\"text\":\"$stts_city ($stts_host)\",\"tooltip\":\"$tooltip\",\"class\":\"connected\",\"alt\":\"connected\"}"
  
else
  printf "%s" "{\"text\":\"Unknown\",\"tooltip\":\"Unable to access daemon.\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
fi

