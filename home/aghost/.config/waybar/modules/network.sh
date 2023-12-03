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
whereis bc > /dev/null || echoexit "'bc' not found."

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
	local status tooltip if_all if_up if_route interface

	# get all interfaces
	if_all=$(ls /etc/init.d/ | grep "^net\." | grep -v "^net\.lo$" | sed "s/^net\.//g")
	
	# get active interfaces
	if_up=$(ip addr | grep 'state UP' | cut -d ':' -f 2 | sed 's/ //g')

	# if no interface is up, return disabled
	if [[ "$if_up" == "" ]]; then
		printf "%s\n" "{\"text\":\"Disabled\",\"tooltip\":\"Interface disabled\",\"class\":\"disabled\",\"alt\":\"disabled\"}"
		return 0
	fi

	# get kernel default ip route interface
	if_route=$(route | grep '^default' | grep -o '[^ ]*$')
	
	# filter by interfaces up
	interface=$(printf "$if_all" | grep "$(printf "$if_up" | tr '\n' ':' | sed 's/:/\\\|/g')")
	
	# filter by default route
	interface=$(printf "$interface" | grep "$if_route")

	# if more than one interface remains, return unknown
	if (( $(printf "$interface" | wc -l) > 0 )); then
		printf "%s\n" "{\"text\":\"Unknown\",\"tooltip\":\"Unknown interface\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
		return 0
	fi

	local if_ip if_wireless if_type

	# get interface ip address 
	if_ip=$(ip addr show dev "$interface" | grep "^    inet " | cut -d " " -f 6)

	# get wireless interfaces
	if_wireless=$(ls /sys/class/ieee80211/*/device/net/)

	# check if interface is wireless
	if_type=$(printf "$if_wireless" | grep -c -o "^$interface$")
	if (( $if_type > 0 )); then
		if_type="wireless"
	else
		if_type="wired"
	fi

	local if_ip_link_1 if_ip_link_2

	# get network data
	if_ip_link_1=$(ip -s link)
	
	# wait for 1 second
	sleep 1
	
	# get network data again
	if_ip_link_2=$(ip -s link)

	# filter interface data
	if_ip_link_1=$(printf "$if_ip_link_1" | grep "$interface" -A 5)
	if_ip_link_2=$(printf "$if_ip_link_2" | grep "$interface" -A 5)

	local if_band_down_1 if_band_down_2 if_band_down

	# get download diff
	if_band_down_1=$(printf "$if_ip_link_1" | grep "RX:" -A 1 | tail -n 1 | awk '{print $1}')
	if_band_down_2=$(printf "$if_ip_link_2" | grep "RX:" -A 1 | tail -n 1 | awk '{print $1}')
	if_band_down=$(( $if_band_down_2 - $if_band_down_1 ))
	if_band_down=$(echo "$if_band_down / 1024 / 1024" | bc -l | awk '{printf "%.2f", $0}')

	local if_band_up_1 if_band_up_2 if_band_up

	# get upload diff
	if_band_up_1=$(printf "$if_ip_link_1" | grep "TX:" -A 1 | tail -n 1 | awk '{print $1}')
	if_band_up_2=$(printf "$if_ip_link_2" | grep "TX:" -A 1 | tail -n 1 | awk '{print $1}')
	if_band_up=$(( $if_band_up_2 - $if_band_up_1 ))
	if_band_up=$(echo "$if_band_up / 1024 / 1024" | bc -l | awk '{printf "%.2f", $0}')

	local if_bandwidth

	# interface bandwidth
	if_bandwidth="$if_band_up Mb/s upload, $if_band_down Mb/s download"

	# tooltip header
	tooltip="interface: $interface"
	tooltip+="\n  type: $if_type"
	
	# wireless tooltip
	if [[ "$if_type" == "wireless" ]]; then
		local wpa_status if_wpa if_con_freq if_con_ssid

		# get wpa_supplicant data
		wpa_status=$(sudo wpa_cli status)
		
		# get wpa_supplicant interface
		if_wpa=$(printf "$wpa_status" | grep "^Selected interface " | sed "s/^Selected interface //g" | sed "s/'//g")
		
		# check wpa_supplicant interface
		if [[ "$interface" != "$if_wpa" ]]; then
			printf "%s\n" "{\"text\":\"Unknown\",\"tooltip\":\"Unknown interface.\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
			exit 0
		fi
		
		# extract wireless ssid
		if_con_ssid=$(printf "$wpa_status" | grep "^ssid=" | sed "s/^ssid\=//g")

		# extract wireless frequency
		if_con_freq=$(printf "$wpa_status" | grep "^freq=" | sed "s/^freq\=//g")

		# wireless tooltip
		tooltip+="\n  ssid: $if_con_ssid"
		tooltip+="\n  freq: $if_con_freq MHz"
	fi

	local if_netmask if_gateway
	
	# get netmask
	if_netmask=$(ifconfig "$interface" | grep " netmask " | sed "s/netmask/:/g" | sed "s/broadcast/:/g" | cut -d ":" -f 2 | trim_whitespaces)

	# get gateway if existent
	if [[ "$interface" == "$if_route" ]]; then
		if_gateway=$(route | grep '^default' | awk '{ printf $2 }')
	fi

	# common tooltip
	tooltip+="\n  bandwidth: $if_bandwidth"
	tooltip+="\n  ip: $if_ip"
	tooltip+="\n  netmask: $if_netmask"
	tooltip+="\n  gateway: $if_gateway"
	
	# if type wireless
	if [[ "$if_type" == "wireless" ]]; then
		printf "%s\n" "{\"text\":\"Connected WiFi\",\"tooltip\":\"$tooltip\",\"class\":\"wireless\",\"alt\":\"wireless\"}"

	# if type wired
	elif [[ "$if_type" == "wired" ]]; then
		local city host
		city="$(printf %s "$status" | grep "^  city: " | cut -d ":" -f 2 | trim_whitespaces)"
		host="$(printf %s "$status" | grep "^  hostname: " | cut -d ":" -f 2 | cut -d "." -f 1 | trim_whitespaces)"

		printf "%s\n" "{\"text\":\"Connected Ethernet\",\"tooltip\":\"$tooltip\",\"class\":\"wired\",\"alt\":\"wired\"}"

	# if type unknown
	else
		printf "%s\n" "{\"text\":\"Unknown\",\"tooltip\":\"Unknown interface.\",\"class\":\"unknown\",\"alt\":\"unknown\"}"
	fi
}

# main
waybar_json

