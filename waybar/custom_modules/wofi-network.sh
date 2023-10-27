#!/bin/bash
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

connection_menu() {
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
		connection_menu "$interface" "$connection"
	fi
}

# opens a wofi menu with current interface status and options to connect
interface_menu() {
	local options selected close interface interface_info connections
	interface=$1

	# get interface info
	interface_info=$(nmcli device show "$interface")

	local interface_name interface_type interface_mac interface_state
	interface_name=$(get_show_property "$interface_info" "GENERAL.DEVICE:")
	interface_type=$(get_show_property "$interface_info" "GENERAL.TYPE:")
	interface_mac=$(get_show_property "$interface_info" "GENERAL.HWADDR:")
	interface_state=$(get_show_property "$interface_info" "GENERAL.STATE:")
	
	# get menu options
	options="$interface_name:"
	options="$options\n\ttype: $interface_type"
	options="$options\n\tMAC: $interface_mac"
	options="$options\n\tstate: $interface_state"
	
	# get wifi options
	if [[ "$interface_type" == *"wifi"* ]]; then
		local radio_state
		radio_state=$(nmcli radio wifi)

		if [[ "$radio_state" == *"enabled"* ]]; then
			local wifi_list

			# get local wifi list
			options="$options\nnetworks:"

			wifi_list=$(nmcli -g "IN-USE,SSID,BARS" device wifi list ifname "$interface" --rescan no)
			connections=()
			IFS=$'\n' read -rd '' -a connections <<< "$(printf %s "$wifi_list" | cut -d ":" -f 2)"
			wifi_list=$(printf %s "$wifi_list" | sed "s/\:/\t/g")
			
			if [[ -n "$wifi_list" ]]; then
				options="$options\n$wifi_list"
			fi

			# add wifi options
			options="$options\nscan"

			# get connected options
			if [[ "$interface_state" == *"100 ("* ]]; then
				options="$options\ndisconnect"
				options="$options\nshow password"
			else
				options="$options\nconnect default"
			fi

			options="$options\nturn off"
		else
			options="$options\nturn on"
		fi

		options="$options\nsaved connections"
	else
		# get connected options
		if [[ "$interface_state" == *"100 ("* ]]; then
			local interface_connection interface_ip interface_gateway
			interface_connection=$(get_show_property "$interface_info" "GENERAL.CONNECTION:")

			options="$options\nconnection: $interface_connection"
			options="$options\ndisconnect"
		else
			options="$options\nconnect"
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
	 	"connect" | "connect default")
			nmcli device connect "$interface"
			;;
		"disconnect")
			nmcli device disconnect "$interface"
			;;
		"turn on")
			nmcli radio wifi on
			;;
		"turn off")
			nmcli radio wifi off
			;;
		"scan")
			nmcli device wifi rescan ifname "$interface"
			;;
		"show password")
			secret_menu "$interface" ""
			;;
		"saved connections")
			saved_connections_menu "$interface"
			;;
	    *)
			local connection ssid
			ssid=$(printf %s "$selected" | sed "s/\t/\:/g" | cut -d ":" -f 2 | sed "s/\*//g" | trim_whitespaces)
			for i in "${connections[@]}"; do
				local conn
				conn=$(printf %s "$i" | trim_whitespaces)
				if [[ "$ssid" == "$conn" ]]; then
					connection="$ssid"
				fi
			done
			if [[ -n "$connection" ]]; then
				connection_menu "$interface" "$connection"
			fi
	        ;;
	esac

	if [[ "$close" == "" ]]; then
		interface_menu "$interface"
	fi
}

# opens a wofi menu with current network status and options to connect
network_menu() {
	local options selected close interfaces networking_state 

	networking_state=$(nmcli networking)
	
	if [[ "$networking_state" == "enabled" ]]; then
		local interfaces_array interfaces_status

		interfaces_array=()
		interfaces_status=$(nmcli device status)
		IFS=$'\n' read -rd '' -a interfaces_array <<< "$interfaces_status"

		options="$options\ninterfaces:"

		for i in "${interfaces_array[@]}"; do
			local interface_name interface_type interface_state interface_connection

			interface_name=$(printf %b "$i" | awk '{print $1}')
			interface_type=$(printf %b "$i" | awk '{print $2}')

			if	[[ "$interface_type" == "TYPE"     ]] || \
				[[ "$interface_type" == "loopback" ]] || \
				[[ "$interface_type" == "wifi-p2p" ]]; then
				continue
			fi

			local sp ss ep es
			sp=${interfaces_array[0]%%"STATE"*}
			ss=${#sp}
			ep=${interfaces_array[0]%%"CONNECTION"*}
			es=${#ep}
			interface_state=${i:ss:((es - ss))}
			interface_state="$(trim_whitespaces "$interface_state")"

			interface_connection=$(printf %b "$i" | sed "s/$interface_state/\:/g" | cut -d ":" -f 2 | trim_whitespaces)

			options="$options\n\t$interface_name: $interface_connection"
			interfaces="$interfaces\n$interface_name"
		done
	
		options="$options\nturn off"
	else
		options="${options}\nturn on"
	fi

	options="$options\nopen connection editor\nexit"
	options="${options:2}"

	# launch wofi and select option
	selected="$(printf %b "$options" | $MENU_CMD -p "Network" --width=240 --height=260)"

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
	 	"turn on")
	        nmcli networking on
	        ;;
	    "turn off")
	        nmcli networking off
	        ;;
	    "open connection editor")
	        nm-connection-editor &
	        ;;
	    *)
			local interface interface_selected
			interface_selected=$(printf %b "$selected" | cut -d ":" -f 1 | trim_whitespaces)
			interface=$(printf %b "$interfaces" | grep "$interface_selected" -m 1)
			if [[ -n "$interface" ]]; then
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
