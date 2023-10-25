#!/bin/bash
#
# WOFI NETWORK-MANAGER
#
# Source: https://github.com/sadiksaifi/wofi-network-manager
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

# Menu command, should read from stdin and write to stdout.
wofi_command="wofi --dmenu --location=3 --x=-130"

# Default Values
LOCATION=3
QRCODE_LOCATION=$LOCATION
Y_AXIS=0
X_AXIS=-120
NOTIFICATIONS_INIT="off"
QRCODE_DIR="/tmp/"
WIDTH_FIX_MAIN=1
WIDTH_FIX_STATUS=10
PASSWORD_ENTER="Enter password. Or press Return/ESC if connection is stored."

# menu choices for device selection
function init_menu_choices() {

	local choices actions device_status devices
	
	choices=""
	actions=""

	device_status=$(nmcli device status)
	devices=()
	IFS=$'\n' read -rd '' -a devices <<< "$device_status"

	for i in "${devices[@]}"; do
		local device_name device_type device_state device_connection
		
		device_name=$(echo -e "$i" | awk '{print $1}')
		device_type=$(echo -e "$i" | awk '{print $2}')

		local sp ss ep es
		sp=${devices[0]%%"STATE"*}
		ss=${#sp}
		ep=${devices[0]%%"CONNECTION"*}
		es=${#ep}
		device_state=${i:ss:((es - ss))}
		device_state="${device_state#"${device_state%%[![:space:]]*}"}"

		device_connection=$(echo -e "$i" | sed "s/$device_state/\:/g" | cut -d ":" -f 2)
		device_connection="${device_connection#"${device_connection%%[![:space:]]*}"}"

		if	[[ "$device_type" == "TYPE"     ]] || \
			[[ "$device_type" == "loopback" ]] || \
			[[ "$device_type" == "wifi-p2p" ]]; then
			continue
		fi

		choices="$choices$device_name ($device_type):\n"
		actions="$actions$device_name ($device_type):\n"

		choices="$choices\tstate: $device_state\n"
		
		if [[ "$device_connection" == *"--"* ]]; then
			continue
		fi

		choices="$choices\tconnection: $device_connection\n"
		
	done

	printf "%b" "$choices&$actions"
}

function notification() {
	[[ "$NOTIFICATIONS_INIT" == "on" && -x "$(command -v notify-send)" ]] && notify-send -r "5" -u "normal" $1 "$2"
}

function wofi_menu() {
	{ [[ ${#WIRELESS_INTERFACES[@]} -gt "1" ]] && OPTIONS="${OPTIONS}Change Wifi Interface\nMore Options"; } || { OPTIONS="${OPTIONS}More Options"; }
	{ [[ "$WIRED_CON_STATE" == "connected" ]] && PROMPT="${WIRED_INTERFACES_PRODUCT}[$WIRED_INTERFACES]"; } || PROMPT="${IWIRELESS_PRODUCT}[${IWIRELESS}]"
	SELECTION=$(echo -e "$OPTIONS" | wofi_cmd "$OPTIONS" $WIDTH_FIX_MAIN "-a 0")
	SSID=$(echo "$SELECTION" | sed "s/\s\{2,\}/\|/g" | awk -F "|" '{print $1}')
	selection_action
}
function wofi_cmd() {
	{ [[ -n "${1}" ]] && WIDTH=$(echo -e "$1" | awk '{print length}' | sort -n | tail -1) && ((WIDTH += $2)) && ((WIDTH = WIDTH / 2)); } || { ((WIDTH = $2 / 2)); }
	wofi --dmenu --normal-window=false --location=$LOCATION --y=$Y_AXIS --x=$X_AXIS $3 --theme "$RASI_DIR" --theme-str 'window{width: '$WIDTH'em;}textbox-prompt-colon{str:"'$PROMPT':";}'"$4"''
}
function change_wireless_interface() {
	{ [[ ${#WIRELESS_INTERFACES[@]} -eq "2" ]] && { [[ $IWIRELESS_INT -eq "0" ]] && IWIRELESS_INT=1 || IWIRELESS_INT=0; }; } || {
		LIST_IWIRELESS_INT=""
		for i in "${!WIRELESS_INTERFACES[@]}"; do LIST_IWIRELESS_INT=("${LIST_IWIRELESS_INT[@]}${WIRELESS_INTERFACES_PRODUCT[$i]}[${WIRELESS_INTERFACES[$i]}]\n"); done
		LIST_IWIRELESS_INT[-1]=${LIST_IWIRELESS_INT[-1]::-2}
		CHANGE_IWIRELESS_INT=$(echo -e "${LIST_IWIRELESS_INT[@]}" | wofi_cmd "${LIST_IWIRELESS_INT[@]}" $WIDTH_FIX_STATUS)
		for i in "${!WIRELESS_INTERFACES[@]}"; do [[ $CHANGE_IWIRELESS_INT == "${WIRELESS_INTERFACES_PRODUCT[$i]}[${WIRELESS_INTERFACES[$i]}]" ]] && IWIRELESS_INT=$i && break; done
	}
	update_interfaces_status
	wofi_menu
}
function scan() {
	[[ "$WIFI_CON_STATE" =~ "unavailable" ]] && change_wifi_state "Wi-Fi" "Enabling Wi-Fi connection" "on" && sleep 2
	notification "-t 0 Wifi" "Please Wait Scanning"
	WIFI_LIST=$(nmcli --fields IN-USE,SSID,SECURITY,BARS device wifi list ifname "${IWIRELESS}" --rescan yes | awk -F'  +' '{ if (!seen[$2]++) print}' | sed "s/^IN-USE\s//g" | sed "/*/d" | sed "s/^ *//" | awk '$1!="--" {print}')
	update_interfaces_status
	notification "-t 1 Wifi" "Please Wait Scanning"
	wofi_menu
}
function change_wifi_state() {
	notification "$1" "$2"
	nmcli radio wifi "$3"
}
function change_wired_state() {
	notification "$1" "$2"
	nmcli device "$3" "$4"
}
function net_restart() {
	notification "$1" "$2"
	nmcli networking off && sleep 3 && nmcli networking on
}
function disconnect() {
	ACTIVE_SSID=$(nmcli -t -f GENERAL.CONNECTION dev show "${IWIRELESS}" | cut -d ':' -f2)
	notification "$1" "You're now disconnected from Wi-Fi network '$ACTIVE_SSID'"
	nmcli con down id "$ACTIVE_SSID"
}
function check_wifi_connected() {
	[[ "$(nmcli device status | grep "^${IWIRELESS}." | awk '{print $3}')" == "connected" ]] && disconnect "Connection_Terminated"
}
function connect() {
	check_wifi_connected
	notification "-t 0 Wi-Fi" "Connecting to $1"
	{ [[ $(nmcli dev wifi con "$1" password "$2" ifname "${IWIRELESS}" | grep -c "successfully activated") -eq "1" ]] && notification "Connection_Established" "You're now connected to Wi-Fi network '$1'"; } || notification "Connection_Error" "Connection can not be established"
}
function enter_passwword() {
	PROMPT="Enter_Password" && PASS=$(echo "$PASSWORD_ENTER" | wofi_cmd "$PASSWORD_ENTER" 4 "--password")
}
function enter_ssid() {
	PROMPT="Enter_SSID" && SSID=$(wofi_cmd "" 40)
}
function stored_connection() {
	check_wifi_connected
	notification "-t 0 Wi-Fi" "Connecting to $1"
	{ [[ $(nmcli dev wifi con "$1" ifname "${IWIRELESS}" | grep -c "successfully activated") -eq "1" ]] && notification "Connection_Established" "You're now connected to Wi-Fi network '$1'"; } || notification "Connection_Error" "Connection can not be established"
}
function ssid_manual() {
	enter_ssid
	[[ -n $SSID ]] && {
		enter_passwword
		{ [[ -n "$PASS" ]] && [[ "$PASS" != "$PASSWORD_ENTER" ]] && connect "$SSID" "$PASS"; } || stored_connection "$SSID"
	}
}
function ssid_hidden() {
	enter_ssid
	[[ -n $SSID ]] && {
		enter_passwword && check_wifi_connected
		[[ -n "$PASS" ]] && [[ "$PASS" != "$PASSWORD_ENTER" ]] && {
			nmcli con add type wifi con-name "$SSID" ssid "$SSID" ifname "${IWIRELESS}"
			nmcli con modify "$SSID" wifi-sec.key-mgmt wpa-psk
			nmcli con modify "$SSID" wifi-sec.psk "$PASS"
		} || [[ $(nmcli -g NAME con show | grep -c "$SSID") -eq "0" ]] && nmcli con add type wifi con-name "$SSID" ssid "$SSID" ifname "${IWIRELESS}"
		notification "-t 0 Wifi" "Connecting to $SSID"
		{ [[ $(nmcli con up id "$SSID" | grep -c "successfully activated") -eq "1" ]] && notification "Connection_Established" "You're now connected to Wi-Fi network '$SSID'"; } || notification "Connection_Error" "Connection can not be established"
	}
}
function interface_status() {
	local -n INTERFACES=$1 && local -n INTERFACES_PRODUCT=$2
	for i in "${!INTERFACES[@]}"; do
		CON_STATE=$(nmcli device status | grep "^${INTERFACES[$i]}." | awk '{print $3}')
		INT_NAME=${INTERFACES_PRODUCT[$i]}[${INTERFACES[$i]}]
		[[ "$CON_STATE" == "connected" ]] && STATUS="$INT_NAME:\n\t$(nmcli -t -f GENERAL.CONNECTION dev show "${INTERFACES[$i]}" | awk -F '[:]' '{print $2}') ~ $(nmcli -t -f IP4.ADDRESS dev show "${INTERFACES[$i]}" | awk -F '[:/]' '{print $2}')" || STATUS="$INT_NAME: ${CON_STATE^}"
		echo -e "${STATUS}"
	done
}
function status() {
	OPTIONS=""
	[[ ${#WIRED_INTERFACES[@]} -ne "0" ]] && ETH_STATUS="$(interface_status WIRED_INTERFACES WIRED_INTERFACES_PRODUCT)" && OPTIONS="${OPTIONS}${ETH_STATUS}"
	[[ ${#WIRELESS_INTERFACES[@]} -ne "0" ]] && IWIRELESS_STATUS="$(interface_status WIRELESS_INTERFACES WIRELESS_INTERFACES_PRODUCT)" && { [[ -n ${OPTIONS} ]] && OPTIONS="${OPTIONS}\n${IWIRELESS_STATUS}" || OPTIONS="${OPTIONS}${IWIRELESS_STATUS}"; }
	ACTIVE_VPN=$(nmcli -g NAME,TYPE con show --active | awk '/:vpn/' | sed 's/:vpn.*//g')
	[[ -n $ACTIVE_VPN ]] && OPTIONS="${OPTIONS}\n${ACTIVE_VPN}[VPN]: $(nmcli -g ip4.address con show "${ACTIVE_VPN}" | awk -F '[:/]' '{print $1}')"
	echo -e "$OPTIONS" | wofi_cmd "$OPTIONS" $WIDTH_FIX_STATUS "" "mainbox{children:[listview];}"
}
function share_pass() {
	SSID=$(nmcli dev wifi show-password | grep -oP '(?<=SSID: ).*' | head -1)
	PASSWORD=$(nmcli dev wifi show-password | grep -oP '(?<=Password: ).*' | head -1)
	OPTIONS="SSID: ${SSID}\nPassword: ${PASSWORD}"
	[[ -x "$(command -v qrencode)" ]] && OPTIONS="${OPTIONS}\nQrCode"
	SELECTION=$(echo -e "$OPTIONS" | wofi_cmd "$OPTIONS" $WIDTH_FIX_STATUS "-a -1" "mainbox{children:[listview];}")
	selection_action
}
function gen_qrcode() {
	DIRECTIONS=("Center" "Northwest" "North" "Northeast" "East" "Southeast" "South" "Southwest" "West")
	[[ -e $QRCODE_DIR$SSID.png ]] || qrencode -t png -o $QRCODE_DIR$SSID.png -l H -s 25 -m 2 --dpi=192 "WIFI:S:""$SSID"";T:""$(nmcli dev wifi show-password | grep -oP '(?<=Security: ).*' | head -1)"";P:""$PASSWORD"";;"
	wofi_cmd "" "0" "" "entry{enabled:false;}window{location:"${DIRECTIONS[QRCODE_LOCATION]}";border-radius:6mm;padding:1mm;width:100mm;height:100mm;
	background-image:url(\"$QRCODE_DIR$SSID.png\",both);}"
}
function manual_hidden() {
	OPTIONS="Manual\nHidden" && SELECTION=$(echo -e "$OPTIONS" | wofi_cmd "$OPTIONS" $WIDTH_FIX_STATUS "" "mainbox{children:[listview];}")
	selection_action
}
function vpn() {
	ACTIVE_VPN=$(nmcli -g NAME,TYPE con show --active | awk '/:vpn/' | sed 's/:vpn.*//g')
	[[ $ACTIVE_VPN ]] && OPTIONS="Deactive $ACTIVE_VPN" || OPTIONS="$(nmcli -g NAME,TYPE connection | awk '/:vpn/' | sed 's/:vpn.*//g')"
	VPN_ACTION=$(echo -e "$OPTIONS" | wofi_cmd "$OPTIONS" "$WIDTH_FIX_STATUS" "" "mainbox {children:[listview];}")
	[[ -n "$VPN_ACTION" ]] && { { [[ "$VPN_ACTION" =~ "Deactive" ]] && nmcli connection down "$ACTIVE_VPN" && notification "VPN_Deactivated" "$ACTIVE_VPN"; } || {
		notification "-t 0 Activating_VPN" "$VPN_ACTION" && VPN_OUTPUT=$(nmcli connection up "$VPN_ACTION" 2>/dev/null)
		{ [[ $(echo "$VPN_OUTPUT" | grep -c "Connection successfully activated") -eq "1" ]] && notification "VPN_Successfully_Activated" "$VPN_ACTION"; } || notification "Error_Activating_VPN" "Check your configuration for $VPN_ACTION"
	}; }
}
function more_options() {
	OPTIONS=""
	[[ "$WIFI_CON_STATE" == "connected" ]] && OPTIONS="Share Wifi Password\n"
	OPTIONS="${OPTIONS}Status\nRestart Network"
	[[ $(nmcli -g NAME,TYPE connection | awk '/:vpn/' | sed 's/:vpn.*//g') ]] && OPTIONS="${OPTIONS}\nVPN"
	[[ -x "$(command -v nm-connection-editor)" ]] && OPTIONS="${OPTIONS}\nOpen Connection Editor"
	SELECTION=$(echo -e "$OPTIONS" | wofi_cmd "$OPTIONS" "$WIDTH_FIX_STATUS" "" "mainbox {children:[listview];}")
	selection_action
}
function selection_action() {
	case "$SELECTION" in
	"Disconnect") disconnect "Connection_Terminated" ;;
	"Scan") scan ;;
	"Status") status ;;
	"Share Wifi Password") share_pass ;;
	"Manual/Hidden") manual_hidden ;;
	"Manual") ssid_manual ;;
	"Hidden") ssid_hidden ;;
	"Wi-Fi On") change_wifi_state "Wi-Fi" "Enabling Wi-Fi connection" "on" ;;
	"Wi-Fi Off") change_wifi_state "Wi-Fi" "Disabling Wi-Fi connection" "off" ;;
	"Eth Off") change_wired_state "Ethernet" "Disabling Wired connection" "disconnect" "${WIRED_INTERFACES}" ;;
	"Eth On") change_wired_state "Ethernet" "Enabling Wired connection" "connect" "${WIRED_INTERFACES}" ;;
	"***Wi-Fi Disabled***") ;;
	"***Wired Unavailable***") ;;
	"***Wired Initializing***") ;;
	"Change Wifi Interface") change_wireless_interface ;;
	"Restart Network") net_restart "Network" "Restarting Network" ;;
	"QrCode") gen_qrcode ;;
	"More Options") more_options ;;
	"Open Connection Editor") nm-connection-editor ;;
	"VPN") vpn ;;
	*)
		[[ -n "$SELECTION" ]] && [[ "$WIFI_LIST" =~ .*"$SELECTION".* ]] && {
			[[ "$SSID" == "*" ]] && SSID=$(echo "$SELECTION" | sed "s/\s\{2,\}/\|/g " | awk -F "|" '{print $3}')
			{ [[ "$ACTIVE_SSID" == "$SSID" ]] && nmcli con up "$SSID" ifname "${IWIRELESS}"; } || {
				[[ "$SELECTION" =~ "WPA2" ]] || [[ "$SELECTION" =~ "WEP" ]] && enter_passwword
				{ [[ -n "$PASS" ]] && [[ "$PASS" != "$PASSWORD_ENTER" ]] && connect "$SSID" "$PASS"; } || stored_connection "$SSID"
			}
		}
		;;
	esac
}

# main

# get menu choices
init_choices="$(init_menu_choices)"

# get action array
init_actions=()
IFS=$'\n' read -rd '' -a init_actions <<< ${init_choices##*&}

# launch wofi and choose action
init_choices=${init_choices%&*}
init_choice="$(echo -e "$init_choices" | $wofi_command -p "Network" --width=300 --height=300)"

# check each action
for i in "${init_actions[@]}"; do
	if [[ "$init_choice" == "$i" ]]; then

		# get menu choices
		device_choices="$(device_menu_choices "$init_choice")"

		# get action array
		device_actions=()
		IFS=$'\n' read -rd '' -a device_actions <<< ${device_choices##*&}

		# launch wofi and choose action
		device_choices=${device_choices%&*}
		device_choice="$(echo -e "$device_choices" | $wofi_command -p "$init_choice" --width=300 --height=300)"

	fi
done
