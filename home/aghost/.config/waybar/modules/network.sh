#!/bin/sh
#
# WAYBAR NETIFRC
#

# exit when any command fails
set -T

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis rc-service > /dev/null || echoexit "'rc-service' not found."

trim_whitespaces() {
        local text
        text=$1
        if [[ "$text" == "" ]]; then
                read text
        fi
	text="${text#"${text%%[![:space:]]*}"}"
        printf %s "$text"
}

# netifrc waybar module json format
waybar_json() {
	local status tooltip conn_on conn_off

	# get all interfaces
	interfaces=$(ls /etc/init.d/ | grep "^net\." | grep -v "^net\.lo$" | sed "s/^net\.//g")
	
	# get kernel default ip route interface
	route_if=$(route | grep '^default' | grep -o '[^ ]*$')
	
	# check if matches
	interfaces=$(printf %s "$interfaces" | grep "$route_if")
	
	# if status disconnected
	if [[ "$conn_off" != "" ]]; then
		printf "%s\n" "{\"text\":\"Disconnected\",\"tooltip\":\"$tooltip\",\"class\":\"disconnected\",\"alt\":\"disconnected\"}"

	# if status connected
	elif [[ "$conn_on" != "" ]]; then
		local city host
		city="$(printf %s "$status" | grep "^  city: " | cut -d ":" -f 2 | trim_whitespaces)"
		host="$(printf %s "$status" | grep "^  hostname: " | cut -d ":" -f 2 | cut -d "." -f 1 | trim_whitespaces)"

		printf "%s\n" "{\"text\":\"$city ($host)\",\"tooltip\":\"$tooltip\",\"class\":\"connected\",\"alt\":\"connected\"}"

	# if status unknown
	else
		printf "%s\n" "{\"text\":\"Unknown\",\"tooltip\":\"Unknown status.\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
	fi
}

# main
waybar_json
