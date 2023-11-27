#!/bin/sh
#
# WAYBAR NORDVPN
#
# Based on: https://github.com/etrigan63/wofi-nordvpn
#

# exit when any command fails
set -T

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis nordvpn-rc > /dev/null || echoexit "'nordvpn-rc' not found."

# nordvpn waybar module json format
waybar_json() {
	local status tooltip conn_on conn_off

	# get status
	status=$(sudo nordvpn-rc --nocolor gs) || exit $?
	tooltip=$(printf %s "$status" | tail -13 | sed -z 's/\n/\\n/g')

	conn_on=$(printf %s "$status" | grep -m 1 "^status: connected$")
	conn_off=$(printf %s "$status" | grep -m 1 "^status: disconnected$")

	# if status disconnected
	if [[ "$conn_off" != "" ]]; then
		printf "%s\n" "{\"text\":\"Disconnected\",\"tooltip\":\"$tooltip\",\"class\":\"disconnected\",\"alt\":\"disconnected\"}"

	# if status connected
	elif [[ "$conn_on" != "" ]]; then
		local city host
		city="$(printf %s "$status" | grep "^  city: " | cut -d ":" -f 2 | tr -d ' ')"
		host="$(printf %s "$status" | grep "^  hostname: " | cut -d ":" -f 2 | tr -d ' ' | cut -d "." -f 1)"

		printf "%s\n" "{\"text\":\"$city ($host)\",\"tooltip\":\"$tooltip\",\"class\":\"connected\",\"alt\":\"connected\"}"

	# if status unknown
	else
		printf "%s\n" "{\"text\":\"Unknown\",\"tooltip\":\"Unknown status.\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
	fi
}

# main
waybar_json
