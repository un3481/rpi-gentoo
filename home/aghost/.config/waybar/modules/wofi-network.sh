#!/bin/sh
#
# WOFI NETWORK-MANAGER
#
# reference: https://github.com/sadiksaifi/wofi-network-manager
#

# exit when any command fails
set -T

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis foot > /dev/null || echoexit "'foot' not found."
whereis wofi > /dev/null || echoexit "'wofi' not found."
whereis wpa_cli > /dev/null || echoexit "'wpa_cli' not found."

# constants
TMPDIR="/tmp"
CACHE_FILE="$TMPDIR/wofi-dump-cache"

# menu command, should read from stdin and write to stdout.
MENU_CMD="wofi --dmenu --location=3 --x=-180 --cache-file=$CACHE_FILE"

trim_whitespaces() {
	local text
	text=$1
	if [[ "$text" == "" ]]; then
		read text
	fi
	text="${text#"${text%%[![:space:]]*}"}"
	printf %s "$text"
}

show_secret() {
	local options selected close interface connection connection
	interface=$1
	connection=$2

	foot --hold doas printf "$(
		wpa_passwd="$(cat "/etc/wpa_supplicant/wpa_supplicant.conf" \
			| grep -A 5 "ssid=\"$connection\"$" \
			| grep "^\spsk=\"" \
			| sed "s/^\spsk=\"//g" \
			| sed "s/\"$//g" \
		)"; \
		printf "SSID: $connection\nPassword: $wpa_passwd\n";
	)"
}

saved_networks_menu() {
	local options selected close interface wpa_networks
	interface=$1

	options="networks:"
	
	# get wpa supplicant networks
	wpa_list_networks=$(doas /usr/bin/wpa_cli list_networks | tail -n +3)

	networks=()
	IFS=$'\n' read -rd '' -a networks <<< "$(printf "$wpa_list_networks")"
	for i in "${networks[@]}"; do
		local network ssid is_active
		network=$i

		# get ssid from results
		ssid=$(printf "$network" | awk -F '\t' '{ print $2 }')

		# mark active ssid
		is_active="$(printf "$network" | sed "s/\t/#@:/g" | grep -o "#@:\[CURRENT\]$")"
		if [[ $is_active != "" ]]; then
			is_active="  <<"
		fi

		options+="\n    ${ssid}${is_active}"
	done
	
	options+="\nadd network\nback"

	# launch wofi and select option
	selected=$(printf "$options" | $MENU_CMD -p "Saved Connections" --width=240 --height=300)

	# do not keep cache
	rm "$CACHE_FILE"

	# match selected option to command
	case $selected in
		"")
			exit 0
			;;
		"back")
			close="1"
			;;
		"add network")
			local ssid
			ssid=$(printf "\n" | $MENU_CMD -p "Enter WiFi SSID here." --width=240 --height=100)
			if [[ "$ssid" != "" ]]; then
				local password
				password=$(printf "\n" | $MENU_CMD -p "Enter WiFi password here." --password --width=240 --height=100)
				
				# add network to wpa_config
				add_network "$interface" "$ssid" "$password"
			fi
			;;
		*)
			local ssid network
			network=""
			ssid=$(printf "$selected" | sed "s/^    //g" | sed "s/  <<$//g")
			for i in "${networks[@]}"; do
				local net_iter
				net_iter=$(printf "$i" | awk -F '\t' '{ print $2 }')
				if [[ "$net_iter" == "$ssid" ]]; then
					network="$ssid"
				fi
			done
			if [[ "$network" != "" ]]; then
				wpa_network_menu "$interface" "$network"
			fi			
			;;
	esac
	
	if [[ "$close" == "" ]]; then
		saved_networks_menu "$interface"
	fi
}

add_network() {
	local interface ssid password
	interface=$1
	ssid=$2
	password=$3

	foot doas \ 
		net_id="$(wpa_cli -i "$interface" add_network)"; \
		wpa_cli -i "$interface" set_network "$net_id" ssid "\"$ssid\""; \
		wpa_cli -i "$interface" set_network "$net_id" psk "\"$password\""; \
		wpa_cli -i "$interface" set_network "$net_id" scan_ssid "1"; \
		wpa_cli -i "$interface" set_network "$net_id" key_mgmt "WPA-PSK"; \
		wpa_cli -i "$interface" set_network "$net_id" proto "RSN"; \
		wpa_cli -i "$interface" disable_network "$net_id"; \
		wpa_cli -i "$interface" save_config;
}

wpa_network_menu() {
	local options selected close interface network if_type
	interface=$1
	network=$2

	# set options
	options="network:"
	options+="\n    name: $network"

	# get network type
	if_type=$(get_if_type "$interface")	
	options+="\n    type: $if_type"

	local net_id
	net_id=""

	if [[ "$if_type" == "wireless" ]]; then
		local bssid
		
		# get connection MAC address
		bssid=$(doas /usr/bin/wpa_cli scan_results | sed "s/\t/#@:/g" | grep -m 1 "#@:$network$" | cut -d "#" -f 1)
		[[ "$bssid" == "" ]] || options+="\n    MAC: $bssid"

		net_id=$(doas /usr/bin/wpa_cli list_networks | sed "s/\t/#@:/g" | grep -m 1 "#@:$network#@:" | cut -d "#" -f 1)
		if [[ "$net_id" == "" ]]; then
			options+="\nadd network"
		else
			local wpa_status active_ssid
			
			options+="\ndelete network"
			options+="\nshow password"
			
			# get wpa_supplicant status
			wpa_status=$(doas /usr/bin/wpa_cli status)

			# extract wireless ssid
			active_ssid=$(printf "$wpa_status" | grep "^ssid=" | sed "s/^ssid\=//g")			
			if [[ "$active_ssid" == "$connection" ]]; then
				options+="\ndisconnect"
			else
				options+="\nconnect"
			fi
		fi
	fi

	options+="\nback"

	# launch wofi and select option
	selected="$(printf "$options" | $MENU_CMD -p "$network" --width=240 --height=260)"

	# do not keep cache
	rm "$CACHE_FILE"

	# match selected option to command
	case $selected in
		"")
			exit 0
			;;
		"back")
			close="1"
			;;
		"connect")
			foot doas \
				wpa_cli -i "$interface" select_network "$net_id"; \
				wpa_cli -i "$interface" save_config;
			;;
		"disconnect")
			foot doas \
				wpa_cli -i "$interface" disable_network all; \
				wpa_cli -i "$interface" save_config;
			;;
		"show password")
			show_secret "$interface" "$network"
			;;
		"add network")
			local net_passwd
			net_passwd=$(printf "\n" | $MENU_CMD -p "Enter WiFi password here." --password --width=240 --height=100)
			add_network "$interface" "$network" "$net_passwd"
			;;
		"delete network")
			foot doas \
				wpa_cli -i "$interface" remove_network "$net_id"; \
				wpa_cli -i "$interface" save_config;
			;;
		*)
			;;
	esac

	if [[ "$close" == "" ]]; then
		wpa_network_menu "$interface" "$network"
	fi
}

get_conn_status() {
	local interface if_conn
	interface=$1

	# check con status
	if_conn=$(cat "/sys/class/net/$interface/carrier" 2>/dev/null || printf "0")
	
	# return status
	if (( $if_conn > 0 )); then
		printf "connected"
	else
		printf "disconnected"
	fi
}

get_rf_status() {
	local interface if_rfkill_index if_rfkill_blocked
	interface=$1

	# get rfkiill data
	if_rfkill_index=$(cat "/sys/class/net/$interface/device/ieee80211/*/rfkill1/index" 2>/dev/null)
	if_rfkill_blocked=$(rfkill list $if_rfkill_index | grep "Soft blocked\|Hard blocked" | grep -c "yes")
	
	# return status
	if (( $if_rfkill_blocked > 0 )); then
		printf "disabled"
	else
		printf "enabled"
	fi
}

# opens a wofi menu with current interface status and options to connect
interface_menu() {
	local options selected close interface networks
	interface=$1

	local if_type if_status if_dev if_driver if_addr if_conn

	# get interface info
	if_type=$(get_if_type "$interface")
	if_status=$(get_if_status "$interface")
	if_dev=$(cat "/sys/class/net/$interface/uevent" 2>/dev/null | grep "^DEVTYPE=" | sed "s/^DEVTYPE=//g")
	if_driver=$(cat "/sys/class/net/$interface/device/uevent" 2>/dev/null | grep "^DRIVER=" | sed "s/^DRIVER=//g")
	if_addr=$(cat "/sys/class/net/$interface/address" 2>/dev/null)
	if_conn=$(get_conn_status "$interface")
	
	if [[ "$if_status" == "down" ]]; then
		if_conn="disabled"
	fi

	# get menu options
	options="$interface:"
	[[ "$if_type" == "" ]] || options+="\n    type: $if_type"
	[[ "$if_dev" == "" ]] || [[ "$if_type" == "wireless" ]] || options+="\n    dev: $if_dev"
	[[ "$if_driver" == "" ]] || options+="\n    driver: $if_driver"
	[[ "$if_addr" == "" ]] || options+="\n    address: $if_addr"
	[[ "$if_conn" == "" ]] || options+="\n    status: $if_conn"
	
	# get wifi options
	if [[ "$if_type" == "wireless" ]]; then
		local if_rf_status

		# get rfkill status
		if_rf_status=$(get_rf_status "$interface")
		
		if [[ "$if_rf_status" != "enabled" ]]; then
			options+="\n    error: radio disabled"
		fi
		
		# get up options
		if [[ "$if_status" == "up" ]]; then
			local wpa_status active_ssid wpa_scan_results

			# get local wifi list
			options+="\nnetworks:"

			# get wpa_supplicant status
			wpa_status=$(doas /usr/bin/wpa_cli status)
		
			# extract wireless ssid
			active_ssid=$(printf "$wpa_status" | grep "^ssid=" | sed "s/^ssid\=//g")

			# get wpa_supplicant scan results
			wpa_scan_results=$(doas /usr/bin/wpa_cli scan_results | tail -n +3)

			networks=()
			IFS=$'\n' read -rd '' -a networks <<< "$(printf "$wpa_scan_results")"
			for i in "${networks[@]}"; do
				local network ssid is_active
				network=$i

				# get ssid from results
				ssid=$(printf "$network" | awk -F '\t' '{ print $5 }')

				# mark active ssid
				is_active=""
				if [[ "$ssid" == "$active_ssid" ]]; then
					is_active="  <<"
				fi

				options+="\n    ${ssid}${is_active}"
			done

			# add wifi options
			options+="\nscan"
			options+="\nsaved networks"
		fi
	fi

	# get up options
	if [[ "$if_status" == "up" ]]; then
		options+="\ndisable"
	else
		options+="\nenable"
	fi
	
	options+="\nback"

	# launch wofi and select option
	selected="$(printf "$options" | $MENU_CMD -p "$interface" --width=260 --height=300)"
	
	# do not keep cache
	rm "$CACHE_FILE"

	# match selected option to command
	case $selected in
		"")
			exit 0
			;;
		"back")
			close="1"
			;;
		"scan")
			doas /usr/bin/wpa_cli scan	
			;;
		"saved networks")
			saved_networks_menu "$interface"
			;;
		"disable")
			foot doas rc-service "net.$interface" stop
			;;
		"enable")
			foot doas rc-service "net.$interface" start
			;;
		*)
			local ssid network
			network=""
			ssid=$(printf "$selected" | sed "s/^    //g" | sed "s/  <<$//g")
			for i in "${networks[@]}"; do
				local net_iter
				net_iter=$(printf "$i" | awk -F '\t' '{ print $5 }')
				if [[ "$net_iter" == "$ssid" ]]; then
					network="$ssid"
				fi
			done
			if [[ "$network" != "" ]]; then
				wpa_network_menu "$interface" "$network"
			fi
			;;
	esac

	if [[ "$close" == "" ]]; then
		interface_menu "$interface"
	fi
}

get_if_list() {
	ls "/etc/init.d/" | grep "^net\." | grep -v "^net\.lo$" | sed "s/^net\.//g"
}

get_if_type() {
	local interface if_type is_wired is_wireless is_virtual
	interface=$1

	# default interface type
	if_type="unknown"	
	
	# check if interface is wired
	is_wired=$(cat "/sys/class/net/$interface/phydev/uevent" 2>/dev/null | grep -c "ethernet")
	if (( $is_wired > 0 )); then
		if_type="wired"
        fi

       	# check if interface is wireless
        is_wireless=$(ls /sys/class/ieee80211/*/device/net/ | grep -c "^$interface$")
        if (( $is_wireless > 0 )); then
		if_type="wireless"
        fi

	# check if interface is virtual
	is_virtual=$(ls -l "/sys/class/net" | grep " $interface -> " | grep -c "/devices/virtual/net/$interface$")
	if (( $is_virtual > 0 )); then
		if_type="virtual"
        fi

	# return type
	printf "$if_type"
}

get_if_status() {
	local interface is_up
	interface=$1

	# check interface status
	is_up=$(rc-service "net.$interface" status | grep -c "started$")
	if (( $is_up > 0 )); then
		printf "up"
	else
		printf "down"
	fi
}

# opens a wofi menu with current network status and options to connect
network_menu() {
	local options selected close interfaces networking_state 

	local interfaces_array interfaces_status

		# get all interfaces
        	if_all=$(get_if_list)
		if_array=()
		IFS=$'\n' read -rd '' -a if_array <<< "$if_all"

		options="interfaces:"

		for i in "${if_array[@]}"; do
			local interface if_type if_status
			interface=$i

			# get interface type
			if_type=$(get_if_type "$interface")

			# check if interface is active
			if_status=$(get_if_status "$interface")

			options+="\n    $interface: $if_type [$if_status]"
		done

	options+="\nexit"

	# launch wofi and select option
	selected="$(printf "$options" | $MENU_CMD -p "Network" --width=240 --height=260)"

	# do not keep cache
	rm "$CACHE_FILE"

	# match selected option to command
	case $selected in
		"")
			exit 0
			;;
		"exit")
			close="1"
			;;
		*)
			local interface if_selected
			if_selected=$(printf "$selected" | cut -d ":" -f 1 | sed "s/^    //g")
			interface=$(printf "$if_all" | grep -m 1 "$if_selected")
			if [[ "$interface" != "" ]]; then
				interface_menu "$interface"
			fi
			;;
	esac

	if [[ "$close" == "" ]]; then
		network_menu
	fi
}

# main
network_menu

