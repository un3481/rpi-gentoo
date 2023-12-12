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
whereis wofi > /dev/null || echoexit "'wofi' not found."
whereis nmcli > /dev/null || echoexit "'nmcli' not found."
whereis qrencode > /dev/null || echoexit "'qrencode' not found."
whereis swayimg > /dev/null || echoexit "'swayimg' not found."
whereis wayland-info > /dev/null || echoexit "'wayland-info' not found."
whereis nm-connection-editor > /dev/null || echoexit "'nm-connection-editor' not found."

# constants
TMPDIR="/tmp"
CACHE_FILE="$TMPDIR/wofi-dump-cache"
QRCODE_FILE="$TMPDIR/wofi-network-qrcode"

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

get_show_property() {
	local text label property
	text=$1
	label=$2
	property=$(\
		printf %b "$text" \
		| grep "$label" -m 1 \
		| sed "s/$label//g" \
		| trim_whitespaces \
	)
	printf %s "$property"
}

qrcode_display() {
	local interface ssid security password image_file
	interface=$1
	ssid=$2
	security=$3
	password=$4
	
	# set qrcode parameters
	image_file="$QRCODE_FILE-$interface.png"
	text="WIFI:S:$ssid;T:$security;P:$password;;"

	# generate qrcode image in tmp folder
	qrencode -t png -o "$image_file" -l H -s 25 -m 2 --dpi=192 "$text"
	
	# find monitor resolution and calculate image position
	local wl_output_mode display_width xpos
	wl_output_mode=$(wayland-info --interface "wl_output" | grep "width:" | grep "height:" | grep "refresh:")
	display_width=$(printf %s "$wl_output_mode" | cut -d ":" -f 2 | trim_whitespaces | cut -d " " -f 1)
	xpos=$(( $display_width - 420 ))

	# launch swayimg at specified position
	swayimg "$image_file" --geometry="$xpos,24,240,240"

	# remove image file
	rm "$image_file"
}

secret_menu() {
	local options selected close interface connection credentials ssid security password
	interface=$1
	connection=$2

	if [[ -n "$connection" ]]; then
		credentials=$(nmcli --show-secrets connection show "$connection")
		ssid="$connection"
		security="WPA"
		password=$(get_show_property "$credentials" "802-11-wireless-security.psk:")
	else
		credentials=$(nmcli device wifi show-password ifname "$interface")
		ssid=$(printf %b "$credentials" | grep -oP '(?<=SSID: ).*' | head -1)
		security=$(printf %b "$credentials" | grep -oP '(?<=Security: ).*' | head -1)
		password=$(printf %b "$credentials" | grep -oP '(?<=Password: ).*' | head -1)
	fi
	
	options="SSID: $ssid\npassword: $password\nqrcode\nback"

	# launch wofi and select option
	selected="$(printf %b "$options" | $MENU_CMD -p "$ssid" --width=240 --height=200)"

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
	 	"qrcode")
			qrcode_display "$interface" "$ssid" "$security" "$password"
	    ;;
	  *)
	    ;;
	esac

	if [[ "$close" == "" ]]; then
		secret_menu "$interface" "$connection"
	fi
}

saved_connections_menu() {
	local options selected close interface interface_info interface_type
	interface=$1

	interface_info=$(nmcli device show "$interface")
	interface_type=$(get_show_property "$interface_info" "GENERAL.TYPE:")

	connections=$(\
		nmcli -g "NAME" connection show \
		| cut -d ":" -f 1 \
		| sed "s/^/\t/g" \
	)

	options="connections:"
	if [[ -n $connections ]]; then
		options="$options\n$connections"
	fi
	options="$options\nadd connection\nback"

	# launch wofi and select option
	selected=$(printf %b "$options" | $MENU_CMD -p "Saved Connections" --width=240 --height=300)

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
		"add connection")
			local ssid password

			ssid=$(printf %b "\n" | $MENU_CMD -p "Enter SSID" --width=240 --height=100)
			if [[ -n "$ssid" ]]; then

				password=$(printf %b "\n" | $MENU_CMD -p "Enter Password" --password --width=240 --height=100)
				if [[ -n "$password" ]]; then 

					nmcli connection add type wifi con-name "$ssid" ssid "$ssid" ifname "$interface"
					nmcli connection modify "$ssid" wifi-sec.key-mgmt wpa-psk
					nmcli connection modify "$ssid" wifi-sec.psk "$password"
				fi
			fi
			;;
	    *)
			local connection
			connection=$(trim_whitespaces "$selected")
			connection_menu "$interface" "$connection"
	        ;;
	esac
	
	if [[ "$close" == "" ]]; then
		saved_connections_menu "$interface"
	fi
}

network_menu() {
	local options selected close interface connection connection_info
	interface=$1
	connection=$2

	# get connection info
	connection_info=$(nmcli connection show "$connection")

	options="connection:"
	options="$options\n\tname: $connection"

	local connection_type
	connection_type=$(get_show_property "$connection_info" "connection.type:")
	options="$options\n\ttype: $connection_type"

	if [[ "$connection_type" == "802-11-wireless" ]]; then
		local connection_bssid
		connection_bssid=$(get_show_property "$connection_info" "802-11-wireless.seen-bssids:")
		options="$options\n\tMAC: $connection_bssid"
	fi

	local connection_saved
	connection_saved=$(nmcli -g UUID,NAME,DEVICE,UUID connection show | grep ":$connection:")
	if [[ "$connection_saved" == "" ]]; then
		options="$options\nadd connection"
	else
		local interface_info interface_state interface_connection

		interface_info=$(nmcli device show "$interface")
		interface_state=$(get_show_property "$interface_info" "GENERAL.STATE:")
		interface_connection=$(get_show_property "$interface_info" "GENERAL.CONNECTION:")
		if [[ "$interface_state" == *"100 ("* ]] && [[ "$interface_connection" == "$connection" ]]; then
			options="$options\ndisconnect"
		else
			options="$options\nconnect"
		fi

		options="$options\nshow password"
		options="$options\ndelete connection"
	fi

	options="$options\nback"

	# launch wofi and select option
	selected="$(printf %b "$options" | $MENU_CMD -p "$connection" --width=240 --height=260)"

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
			nmcli connection up id "$connection"
			;;
		"disconnect")
			nmcli connection down id "$connection"
			;;
		"show password")
			secret_menu "$interface" "$connection"
			;;
		"add connection")
			local password
			password=$(printf %b "\n" | $MENU_CMD -p "Enter Password" --password --width=240 --height=100)
			if [[ -n "$password" ]]; then
				nmcli connection add type wifi con-name "$connection" ssid "$connection" ifname "$interface"
				nmcli connection modify "$connection" wifi-sec.key-mgmt wpa-psk
				nmcli connection modify "$connection" wifi-sec.psk "$password"
			fi
			;;
		"delete connection")
			nmcli connection delete id "$connection"
			;;
		*)
			;;
	esac

	if [[ "$close" == "" ]]; then
		network_menu "$interface" "$connection"
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
		
		# get connected options
		if [[ "$if_status" == "up" ]]; then
			local wpa_status active_ssid wpa_scan_results

			# get local wifi list
			options+="\nnetworks:"

			# get wpa_supplicant status
			wpa_status=$(sudo wpa_cli status)
		
			# extract wireless ssid
			active_ssid=$(printf "$wpa_status" | grep "^ssid=" | sed "s/^ssid\=//g")

			# get wpa_supplicant scan results
			wpa_scan_results=$(sudo wpa_cli scan_results | tail -n +3)

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
			options="$options\nscan"

			# get connected options
			if [[ "$if_conn" == "connected" ]]; then
				options="$options\ndisconnect"
				options="$options\nshow password"
			else
				options="$options\nconnect"
			fi

			options="$options\nsaved connections"
			options="$options\ndisable"
		else
			options="$options\nenable"
		fi
	fi

	options="$options\nback"

	# launch wofi and select option
	selected="$(printf %b "$options" | $MENU_CMD -p "$interface" --width=260 --height=300)"
	
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
			nmcli device connect "$interface"
			;;
		"disconnect")
			nmcli device disconnect "$interface"
			;;
		"scan")
			sudo wpa_cli scan
			;;
		"show password")
			secret_menu "$interface" ""
			;;
		"saved connections")
			saved_connections_menu "$interface"
			;;
		"disable")
			wofi_password | sudo -S rc-service "net.$interface" stop
			;;
		"enable")
			wofi_password | sudo -S rc-service "net.$interface" start
			;;
		*)
			local ssid network
			ssid=$(printf %s "$selected" | sed "s/    //g" | sed "s/  <<//g")
			for i in "${networks[@]}"; do
				local net_iter
				net_iter=$(printf "$i" | awk -F '\t' '{ print $5 }')
				if [[ "$net_iter" == "$ssid" ]]; then
					network="$ssid"
				fi
			done
			if [[ "$network" != "" ]]; then
				network_menu "$interface" "$network"
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
base_menu() {
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
			if_selected=$(printf "$selected" | cut -d ":" -f 1 | trim_whitespaces)
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

