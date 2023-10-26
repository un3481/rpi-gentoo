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

# Default Values
TMPDIR="/tmp"
PASSWORD_ENTER="Enter password. Press Return/ESC if connection is stored."

# menu command, should read from stdin and write to stdout.
MENU_CMD="wofi --dmenu --location=3 --x=-180 --cache-file=/tmp/wofi-dump-cache"

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
	{ [[ $(nmcli dev wifi con "$1" password "$2" ifname "${IWIRELESS}" | grep -c "successfully activated") -eq "1" ]]; }
}

enter_passwword() {
	PROMPT="Enter_Password" && PASS=$(echo "$PASSWORD_ENTER" | MENU_CMD "$PASSWORD_ENTER" 4 "--password")
}

enter_ssid() {
	PROMPT="Enter_SSID" && SSID=$(MENU_CMD "" 40)
}

stored_connection() {
	check_wifi_connected
	{ [[ $(nmcli dev wifi con "$1" ifname "${IWIRELESS}" | grep -c "successfully activated") -eq "1" ]]; }
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
			nmcli con add type wifi con-name "$SSID" ssid "$SSID" ifname "${IWIRELESS}"
			nmcli con modify "$SSID" wifi-sec.key-mgmt wpa-psk
			nmcli con modify "$SSID" wifi-sec.psk "$PASS"
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

	image_file="$TMPDIR/wofi-network-qrcode-$ssid.png"
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

	# launch wofi and choose option
	selected="$(printf %b "" | $MENU_CMD -p "$ssid" --width=280 --height=260 --style="$menu_style")"

	# do not keep cache
	rm "/tmp/wofi-dump-cache"

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

	# launch wofi and choose option
	selected="$(printf %b "$options" | $MENU_CMD -p "$ssid" --width=280 --height=260)"

	# do not keep cache
	rm "/tmp/wofi-dump-cache"

	# match selected option to command
	case $selected in
		"" )
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

# opens a wofi menu with current interface status and options to connect
interface_menu() {
	local options selected actions interface interface_info
	interface=$1

	# get interface info
	interface_info=$(nmcli device show "$interface")

	# get local wifi list
	wifi_list=$(nmcli device wifi list ifname "$interface" --rescan no)

	# get menu options
	options=""

	# separate options and actions
	actions=()
	IFS=$'\n' read -rd '' -a actions <<< ${options##*&}
	options=${options%&*}

	# launch wofi and choose option
	selected="$(echo -e "$options" | $MENU_CMD -p "$interface" --width=280 --height=300)"
	
	# do not keep cache
	rm "/tmp/wofi-dump-cache"

	# match selected option to command
	case $selected in
		"")
            ;;
		"back")
			network_menu
	        ;;
	 	"enable")
			nmcli device connect "$interface"
			interface_menu "$interface"
			;;
		"disable")
			nmcli device disconnect "$interface"
			interface_menu "$interface"
			;;
		"turn wifi on")
			nmcli radio wifi on
			interface_menu "$interface"
			;;
		"turn wifi off")
			nmcli radio wifi off
			interface_menu "$interface"
			;;
		"disconnect")
			nmcli connection down id "$active_ssid"
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
			for i in "${actions[@]}"; do
				if [[ "$selected" == "$i" ]]; then
					connection="$selected"
				fi
			done
			if [[ "$device" == "" ]]; then
				interface_menu "$interface"
			else
				connection_menu "$device" "$connection"
			fi
	        ;;
	esac
}

# opens a wofi menu with current network status and options to connect
network_menu() {
	local options selected interfaces networking_state 

	interfaces=()
	networking_state=$(nmcli networking)
	
	if [[ "$networking_state" == "enabled" ]]; then
		local interfaces_full interfaces_status

		interfaces_full=()
		interfaces_status=$(nmcli device status)
		IFS=$'\n' read -rd '' -a interfaces_full <<< "$interfaces_status"

		for i in "${interfaces_full[@]}"; do
			local interface_name interface_type interface_state interface_connection

			interface_name=$(printf %b "$i" | awk '{print $1}')
			interface_type=$(printf %b "$i" | awk '{print $2}')

			if	[[ "$interface_type" == "TYPE"     ]] || \
				[[ "$interface_type" == "loopback" ]] || \
				[[ "$interface_type" == "wifi-p2p" ]]; then
				continue
			fi

			local sp ss ep es
			sp=${interfaces_full[0]%%"STATE"*}
			ss=${#sp}
			ep=${interfaces_full[0]%%"CONNECTION"*}
			es=${#ep}
			interface_state=${i:ss:((es - ss))}
			interface_state="${interface_state#"${interface_state%%[![:space:]]*}"}"

			interface_connection=$(printf %b "$i" | sed "s/$interface_state/\:/g" | cut -d ":" -f 2)
			interface_connection="${interface_connection#"${interface_connection%%[![:space:]]*}"}"

			options="$options$interface_name: [$interface_type] $interface_connection\n"
			interfaces+=("$interface_name: [$interface_type] $interface_connection")
		done

		options="${options}turn off\n"
	else
		options="${options}turn on\n"
	fi

	options="${options}open connection editor\nexit"

	# launch wofi and choose option
	selected="$(printf %b "$options" | $MENU_CMD -p "Network" --width=280 --height=260)"

	# do not keep cache
	rm "/tmp/wofi-dump-cache"

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
			local interface
			for i in "${interfaces[@]}"; do
				if [[ "$selected" == "$i" ]]; then
					interface=$(printf %b "$selected" | cut -d ":" -f 1)
					printf %b "$interface"
				fi
			done
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
