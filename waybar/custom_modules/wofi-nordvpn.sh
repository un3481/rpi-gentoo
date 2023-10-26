#!/bin/sh
#
# WOFI NORDVPN
#
# reference: https://github.com/etrigan63/wofi-nordvpn
#

# exit when any command fails
set -e

echoexit() {
    # print to stderr and exit
    printf "%s\n" "$@" 1>&2
    exit 1
}

# checking dependencies:
whereis wofi > /dev/null || echoexit "'wofi' not found."
whereis nordvpn > /dev/null || echoexit "'nordvpn' not found."

# menu command, should read from stdin and write to stdout
wofi_command="wofi --dmenu --location=3 --cache-file=/tmp/wofi-dump-cache"

# Show vpn status.
status_menu() {
    local options selected
    options="$(nordvpn status | tr -d '\r-' | sed 's/^ *//')"
    options="$options\nback"

    # launch wofi and select option
    selected=$(printf %b "$options" | $wofi_command -p "Status" --x=-320 --width="260" --height="240")

    # match selected option to command
    case $selected in
        "")
            ;;
        "back")
            nordvpn_menu
            ;;
        *)
            status_menu
            ;;
    esac
}

# Show vpn settings.
settings_menu() {
    local options selected
    options="$(nordvpn settings | tr -d '\r-' | sed 's/^ *//')"
    options="$options\nback"

    # launch wofi and select option
    selected=$(printf %b "$options" | $wofi_command -p "Settings" --x=-320 --width="260" --height="240")

    # match selected option to command
    case $selected in
        "")
            ;;
        "back")
            nordvpn_menu
            ;;
        *)
            settings_menu
            ;;
    esac
}

# country selection
countries_menu() {
    local options selected nl
    options=$(nordvpn countries | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)
    options="back\ndefault\n$options"

    # launch wofi and select option
    selected=$(printf %b "$options" | $wofi_command -p "Countries" --x=-320 --width="200" --height="200")
    
    # match selected option to command
    case $selected in
        "")
            ;;
        "back")
            connect_menu
            ;;
        "default")
            nordvpn connect
            countries_menu
            ;;
        *)
            nordvpn connect "$selected"
            countries_menu
            ;;
    esac
}

# city selection
cities_menu() {
    local options selected country
    country=$1
    options=$(nordvpn cities "$country" | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)
    options="back\n$options"

    # launch wofi and select option
    selected=$(printf %b "$options" | $wofi_command -p "Cities" --x=-320 --width="180" --height="200")

    # match selected option to command
    case $selected in
        "")
            ;;
        "back")
            countries_cities_menu
            ;;
        "default")
            nordvpn connect "$country"
            cities_menu "$country"
            ;;
        *)
            nordvpn connect "$country" "$selected"
            cities_menu "$country"
            ;;
    esac
}

# country and city selection
countries_cities_menu() {
    local options selected
    options=$(nordvpn countries | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)
    options="back\n$options"

    # launch wofi and select option
    selected=$(printf %b "$options" | $wofi_command -p "Countries" --x=-320 --width="200" --height="200")
    
    # match selected option to command
    case $selected in
        "")
            ;;
        "back")
            connect_menu
            ;;
        *)
            cities_menu "$selected"
            ;;
    esac
}

# nordvpn connect options
connect_menu() {
    local options selected
    options="default\ncountries\ncities\np2p\nonion\nback"

    # launch wofi and select option
    selected=$(printf %b "$options" | $wofi_command -p "Connect" --x=-320 --width="140" --height="230")

    # match selected option to command
    case $selected in
        "")
            ;;
        "back")
            nordvpn_menu
            ;;
        "default")
            nordvpn connect
            connect_menu
            ;;
        "countries")
            countries_menu
            ;;
        "cities")
            countries_cities_menu
            ;;
        "p2p")
            nordvpn connect p2p
            connect_menu
            ;;
        "onion")
            nordvpn connect onion_over_vpn
            connect_menu
            ;;
        *)
            connect_menu
            ;;
    esac
}

# opens a wofi menu with nordvpn options to connect
nordvpn_menu() {
    local options selected
    options="connect\ndisconnect\nstatus\nsettings\nexit"

    # launch wofi and select option
    selected=$(printf %b "$options" | $wofi_command -p "Nordvpn" --x=-320 --width="140" --height="200")

    # match selected option to command
    case $selected in
        "")
            ;;
        "exit")
            ;;
        "connect")
            connect_menu
            ;;
        "disconnect")
            nordvpn disconnect
            nordvpn_menu
            ;;
        "status")
            status_menu
            ;;
        "settings")
            settings_menu
            ;;
        *)
            nordvpn_menu
            ;;
    esac
}

# main
nordvpn_menu

# do not keep cache
rm "/tmp/wofi-dump-cache"