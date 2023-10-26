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
	options="interface: $interface_name"
	options="$options\ntype: $interface_type"
	options="$options\nMAC: $interface_mac"
	options="$options\nstate: $interface_state"
	
	# get connected options
	if [[ "$interface_state" == *"connected"* ]]; then
		local interface_connection interface_ip interface_gateway
		interface_connection=$(get_show_property "GENERAL.CONNECTION:")
		interface_ip=$(get_show_property "IP4.ADDRESS\[1\]:")
		interface_gateway=$(get_show_property "IP4.GATEWAY:")

		options="$options\nconnection: $interface_connection"
		options="$options\nIP: $interface_ip"
		options="$options\ngateway: $interface_gateway"
		options="$options\n$DIVIDER"
		options="$options\ndisconnect"
	else
		options="$options\n$DIVIDER"
		options="$options\nconnect"
	fi

	# get local wifi list
	wifi_list=$(nmcli device wifi list ifname "$interface" --rescan no)

	options="$options\nback"

	# launch wofi and select option
	selected="$(echo -e "$options" | $MENU_CMD -p "$interface" --width=280 --height=300)"
	
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
		"wifi [off]")
			nmcli radio wifi on
			interface_menu "$interface"
			;;
		"wifi [on]")
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
			interface_state="$(trim_whitespaces "$interface_state")"

			interface_connection=$(printf %b "$i" | sed "s/$interface_state/\:/g" | cut -d ":" -f 2 | trim_whitespaces)

			options="$options\n$interface_name: [$interface_type] $interface_connection"
			interfaces+=("$interface_name: [$interface_type] $interface_connection")
		done

		options="$options\n$DIVIDER"
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

teste="$(trim_whitespaces "   woopsie    ")"
echo "$teste"
teste=$(printf %s "     eelo  " | trim_whitespaces)
echo "$teste"

# main 
network_menu
