#!/bin/sh
#
# WOFI NORDVPN
#
# Source: https://github.com/etrigan63/wofi-nordvpn
#

# exit when any command fails
set -e

echoexit() {
    # Print to stderr and exit
    printf "%s\n" "$@" 1>&2
    exit 1
}

# Checking dependencies:
whereis wofi > /dev/null || echoexit "'wofi' not found."
whereis nordvpn > /dev/null || echoexit "'nordvpn' not found."

# Menu command, should read from stdin and write to stdout.
wofi_command="wofi --dmenu --location=3 --cache-file=/tmp/wofi-dump-cache"

# nordvpn connect options.
connect_menu() {
    local choices
    choices="default\ncountries\ncities\np2p\nonion"
    printf "%b" "$choices" | $wofi_command -p "Connect" --x=-320 --width="140" --height="230"
}

# Country selection.
countries_menu() {
    local choices
    choices="$(nordvpn countries | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)"
    printf "%s" "$choices" | $wofi_command -p "Countries" --x=-320 --width="200" --height="200"
}

# City selection.
cities_menu() {
    local choices
    choices="$(nordvpn cities "$1" | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)"
    printf "%s" "$choices" | $wofi_command -p "Cities" --x=-320 --width="180" --height="200"
}

# Show vpn status.
status_menu() {
    local choices
    choices="$(nordvpn status | tr -d '\r-' | sed 's/^ *//')"
    printf "%s" "$choices" | $wofi_command -p "Status" --x=-320 --width="260" --height="240"
}

# Show vpn settings.
settings_menu() {
    local choices
    choices="$(nordvpn settings | tr -d '\r-' | sed 's/^ *//')"
    printf "%s" "$choices" | $wofi_command -p "Settings" --x=-320 --width="260" --height="240"
}

# opens a wofi menu with nordvpn options to connect
nordvpn_menu() {
    local options chosen
    options="connect\ndisconnect\nstatus\nsettings"

    # launch wofi and choose option
    chosen=$(printf "%b" "$options" | $wofi_command -p "Nordvpn" --x=-320 --width="140" --height="200")

    # match chosen option to command
    case $chosen in
        "connect")
            case $(connect_menu) in
                "default")
                    nordvpn connect
                    connect_menu
                    ;;
                "countries")
                    local country
                    country="$(countries_menu)"
                    if [ -n "$country" ]; then
                        nordvpn connect "$country"
                    fi
                    countries_menu
                    ;;
                "cities")
                    local country
                    country="$(countries_menu)"
                    if [ -n "$country" ]; then
                        local city
                        city="$(cities_menu "$country")"
                        if [ -n "$city" ]; then
                            nordvpn connect "$country" "$city"
                        fi
                        cities_menu
                    fi
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
                    ;;
            esac
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
            ;;
    esac
}

# main
main

# do not keep cache
rm "/tmp/wofi-dump-cache"