#!/bin/sh
#
#   NORDVPN-WOFI: A part of wofi-nordvpn
#

# exit when any command fails
set -e

echoexit() {
    # Print to stderr and exit
    printf "%s\n" "$@" 1>&2
    exit 1
}

# Checking dependencies:
whereis nordvpn > /dev/null || echoexit "'nordvpn' not found."
whereis wofi > /dev/null || echoexit "'wofi' not found."

# Menu command, should read from stdin and write to stdout.
wofi_command="wofi --dmenu --location=3 --x=-320"

init_menu() {
    # Initial menu.
    local choices
    choices="connect\ndisconnect\nstatus\nsettings"
    printf "%b" "$choices" | $wofi_command -p "Nordvpn" --width="140" --height="200"
}

connect() {
    # nordvpn connect options.
    local choices
    choices="default\ncountries\ncities\np2p\nonion"
    printf "%b" "$choices" | $wofi_command -p "Connect" --width="140" --height="230"
}

countries() {
    # Country selection.
    local choices
    choices="$(nordvpn countries | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)"
    printf "%s" "$choices" | $wofi_command -p "Countries" --width="200" --height="200"
}

cities() {
    # City selection.
    local choices
    choices="$(nordvpn cities "$1" | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)"
    printf "%s" "$choices" | $wofi_command -p "Cities" --width="180" --height="200"
}

disconnect() {
    # disconnect
    nordvpn disconnect
}

vpn_status() {
    # Show vpn status.

    local choices
    choices="$(nordvpn status | tr -d '\r-' | sed 's/^ *//')"

    # The dynamic_lines option doesn't work for me
    # for some reason so I'll work around it.
    lines="$(echo -e "$choices" | wc -l)"

    printf "%s" "$choices" | $wofi_command -p "Status" --width="260" --height="240"
}

settings() {
    # Show vpn settings.

    local choices
    choices="$(nordvpn settings | tr -d '\r-' | sed 's/^ *//')"
    printf "%s" "$choices" | $wofi_command -p "Settings" --width="260" --height="240"
}

# main
case "$(init_menu)" in
    "connect")
        case $(connect) in
            "default")
                nordvpn connect
                ;;
            "countries")
                country="$(countries)"
                [ -n "$country" ] && nordvpn connect "$country"
                ;;
            "cities")
                country="$(countries)"
                [ -n "$country" ] && city="$(cities "$country")"
                [ -n "$city" ] && nordvpn connect "$country" "$city"
                ;;
            "p2p")
                nordvpn connect p2p
                ;;
            "onion")
                nordvpn connect onion_over_vpn
                ;;
            *)
                ;;
        esac
        ;;
    "disconnect")
        disconnect
        ;;
    "status")
        vpn_status
        ;;
    "settings")
        settings
        ;;
    *)
        ;;
esac
