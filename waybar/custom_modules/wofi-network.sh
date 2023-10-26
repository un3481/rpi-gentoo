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
whereis nm-connection-editor > /dev/null || echoexit "'nm-connection-editor' not found."

# constants
TMPDIR="/tmp"
CACHE_FILE="$TMPDIR/wofi-dump-cache"
QRCODE_FILE="$TMPDIR/wofi-network-qrcode"

DIVIDER="---------------------------------"
PASSWORD_ENTER="Enter password. Press Return/ESC if connection is stored."

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
	local property
	property=$(printf %b "$interface_info" | grep "$1" -m 1 | sed "s/$1//g" | trim_whitespaces)
	printf %s "$property"
}

get_list_property() {
	
}

# available options
available_options() {
	case "$SELECTION" in
		"manual/hidden") manual_hidden ;;
		"manual") ssid_manual ;;
		"hidden") ssid_hidden ;;
		*)
			;;
	esac
}

check_wifi_connected() {
	[[ "$(nmcli device status | grep "^${IWIRELESS}." | awk '{print $3}')" == "connected" ]] && disconnect "Connection_Terminated"
}

connect() {
	check_wifi_connected
	{ [[ $(nmcli device wifi con "$1" password "$2" ifname "${IWIRELESS}" | grep -c "successfully activated") -eq "1" ]]; }
}

enter_passwword() {
	PROMPT="Enter_Password" && PASS=$(echo "$PASSWORD_ENTER" | MENU_CMD "$PASSWORD_ENTER" 4 "--password")
}

enter_ssid() {
	PROMPT="Enter_SSID" && SSID=$(MENU_CMD "" 40)
}

stored_connection() {
	check_wifi_connected
	{ [[ $(nmcli device wifi con "$1" ifname "${IWIRELESS}" | grep -c "successfully activated") -eq "1" ]]; }
}

ssid_manual() {
	enter_ssid
	[[ -n $SSID ]] && {
		enter_passwword
		{ [[ -n "$PASS" ]] && [[ "$PASS" != "$PASSWORD_ENTER" ]] && connect "$SSID" "$PASS"; } || stored_connection "$SSID"
	}
}

ssid_hidden() {
	enter_ssid
	[[ -n $SSID ]] && {
		enter_passwword && check_wifi_connected
		[[ -n "$PASS" ]] && [[ "$PASS" != "$PASSWORD_ENTER" ]] && {
			nmcli connection add type wifi con-name "$SSID" ssid "$SSID" ifname "${IWIRELESS}"
			nmcli connection modify "$SSID" wifi-sec.key-mgmt wpa-psk
			nmcli connection modify "$SSID" wifi-sec.psk "$PASS"
		} || [[ $(nmcli -g NAME con show | grep -c "$SSID") -eq "0" ]] && nmcli con add type wifi con-name "$SSID" ssid "$SSID" ifname "${IWIRELESS}"
		{ [[ $(nmcli con up id "$SSID" | grep -c "successfully activated") -eq "1" ]]; }
	}
}

manual_hidden() {
	local options selected

	options="manual\nhidden"
	selected=$(printf %b "$options" | $MENU_CMD)
}

qrencode_menu() {
	local interface ssid security password image_file menu_style
	interface=$1
	ssid=$2
	security=$3
	password=$4

	# set qrcode parameters
	image_file="$QRCODE_FILE-$interface.png"
	text="WIFI:S:$ssid;T:$security;P:$password;;"
	menu_style="
		entry {
			enabled: false;
		}
		window {
			border-radius: 6mm;
			padding: 1mm;
			width: 100mm;
			height: 100mm;
			location: \"Northeast\";
			background-image: url(\"$image_file\", both);
		}
	"
	
	# generate qrcode image in tmp folder
	qrencode -t png -o "$image_file" -l H -s 25 -m 2 --dpi=192 "$text"

	# launch wofi and select option
	selected="$(printf %b "" | $MENU_CMD -p "$ssid" --width=280 --height=260 --style="$menu_style")"

	# do not keep cache
	rm "$CACHE_FILE"

	show_password_menu "$interface"
}

show_password_menu() {
	local options interface credentials ssid password
	interface=$1

	credentials=$(nmcli device wifi show-password ifname "$interface")
	ssid=$(printf %b "$credentials" | grep -oP '(?<=SSID: ).*' | head -1)
	security=$(printf %b "$credentials" | grep -oP '(?<=Security: ).*' | head -1)
	password=$(printf %b "$credentials" | grep -oP '(?<=Password: ).*' | head -1)
	
	options="SSID: $ssid\nsecurity: $security\npassword: $password\nqrcode\nback"

	# launch wofi and select option
	selected="$(printf %b "$options" | $MENU_CMD -p "$ssid" --width=280 --height=260)"

	# do not keep cache
	rm "$CACHE_FILE"

	# match selected option to command
	case $selected in
		"")
            ;;
		"back")
			interface_menu "$interface"
	        ;;
	 	"qrcode")
			qrencode_menu "$interface" "$ssid" "$security" "$password"
	        ;;
	    *)
			show_password_menu "$interface"
	        ;;
	esac
}

connection_menu() {
	local options selected interface connection connection_info
	interface=$1
	connection=$2

	connection_info=$(nmcli connection show "$connection")

	# match selected option to command
	case $selected in
		"")
            ;;
		"back")
			interface_menu "$interface"
	        ;;
		"connect")
			nmcli connection up id "$connection"
			connection_menu "$interface" "$connection"
			;;
		"disconnect")
			nmcli connection down id "$connection"
			connection_menu "$interface" "$connection"
			;;
		"show password")
			show_password_menu "$interface"
			;;
	    *)
			connection_menu "$interface" "$connection"
	        ;;
	esac
}

# opens a wofi menu with current interface status and options to connect
interface_menu() {
	local options selected interface interface_info connections
	interface=$1

	# get interface info
	interface_info=$(nmcli device show "$interface")

	local interface_name interface_type interface_mac interface_state
	interface_name=$(get_show_property "GENERAL.DEVICE:")
	interface_type=$(get_show_property "GENERAL.TYPE:")
	interface_mac=$(get_show_property "GENERAL.HWADDR:")
	interface_state=$(get_show_property "GENERAL.STATE:")
	
	# get menu options
	options="$interface_name:"
	options="$options\n\ttype: $interface_type"
	options="$options\n\tMAC: $interface_mac"
	options="$options\n\tstate: $interface_state"
	
	# get connected options
	if [[ "$interface_state" == *"connected"* ]]; then
		local interface_connection interface_ip interface_gateway
		interface_connection=$(get_show_property "GENERAL.CONNECTION:")

		options="$options\nconnection: $interface_connection"
		options="$options\ndisconnect"
	else
		options="$options\nconnect"
	fi

	# get wifi options
	if [[ "$interface_type" == *"wifi"* ]]; then
		local radio_state
		radio_state=$(nmcli radio wifi)

		if [[ "$radio_state" == *"enabled"* ]]; then
			local wifi_list

			options="$options\nturn off\nscan"
			
			# get local wifi list
			options="$options\nwifi list:"
			wifi_list=$(nmcli device wifi list ifname "$interface" --rescan no)
			options="$options\n$wifi_list"
		else
			options="$options\nturn on"
		fi

		if [[ "$interface_state" == *"connected"* ]]; then
			options="$options\nshow password"
		fi
	fi

	

	options="$options\nback"

	# launch wofi and select option
	selected="$(printf %b "$options" | $MENU_CMD -p "$interface" --width=280 --height=300)"
	
	# do not keep cache
	rm "$CACHE_FILE"

	# match selected option to command
	case $selected in
		"")
            ;;
		"back")
			network_menu
	        ;;
	 	"connect")
			nmcli device connect "$interface"
			interface_menu "$interface"
			;;
		"disconnect")
			nmcli device disconnect "$interface"
			interface_menu "$interface"
			;;
		"turn on")
			nmcli radio wifi on
			interface_menu "$interface"
			;;
		"turn off")
			nmcli radio wifi off
			interface_menu "$interface"
			;;
		"scan")
			nmcli device wifi rescan ifname "$interface"
			interface_menu "$interface"
			;;
		"show password")
			show_password_menu "$interface"
			;;
	    *)
			local connection
			for i in "${connections[@]}"; do
				if [[ "$selected" == "$i" ]]; then
					connection="$selected"
				fi
			done
			if [[ "$connection" == "" ]]; then
				interface_menu "$interface"
			else
				connection_menu "$interface" "$connection"
			fi
	        ;;
	esac
}

# opens a wofi menu with current network status and options to connect
network_menu() {
	local options selected interfaces networking_state 

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

			options="$options\n\t$interface_name: [$interface_type] $interface_connection"
			interfaces="$interfaces\n$interface_name"
		done
	
		options="$options\nturn off"
	else
		options="${options}\nturn on"
	fi

	options="$options\nopen connection editor\nexit"
	options="${options:2}"

	# launch wofi and select option
	selected="$(printf %b "$options" | $MENU_CMD -p "Network" --width=280 --height=260)"

	# do not keep cache
	rm "$CACHE_FILE"

	# match selected option to command
	case $selected in
		"")
            ;;
		"exit")
	        ;;
	 	"turn on")
	        nmcli networking on
			network_menu
	        ;;
	    "turn off")
	        nmcli networking off
			network_menu
	        ;;
	    "open connection editor")
	        nm-connection-editor &
			network_menu
	        ;;
	    *)
			local interface interface_selected
			interface_selected=$(printf %b "$selected" | cut -d ":" -f 1 | trim_whitespaces)
			interface=$(printf %b "$interfaces" | grep "$interface_selected" -m 1)
			if [[ "$interface" == "" ]]; then
				network_menu
			else
				interface_menu "$interface"
			fi
			;;
	esac
}

# main 
network_menu
