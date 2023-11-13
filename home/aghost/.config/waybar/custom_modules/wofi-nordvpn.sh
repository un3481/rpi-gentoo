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

# constants
TMPDIR="/tmp"
CACHE_FILE="$TMPDIR/wofi-dump-cache"

# menu command, should read from stdin and write to stdout
MENU_CMD="wofi --dmenu --location=3 --cache-file=/tmp/wofi-dump-cache"

# Show vpn status.
status_menu() {
    local options selected close
    options="$(nordvpn status | tr -d '\r-' | sed 's/^ *//')"
    options="$options\nback"

    # launch wofi and select option
    selected=$(printf %b "$options" | $MENU_CMD -p "Status" --x=-320 --width=260 --height=240)

    # do not keep cache
	  rm $CACHE_FILE

    # match selected option to command
    case $selected in
      "")
			  exit 0
        ;;
		  "back")
			  close="1"
	      ;;
      *)
        ;;
    esac

    if [[ "$close" == "" ]]; then
		  status_menu
	  fi
}

# Show vpn settings.
settings_menu() {
    local options selected close
    options="$(nordvpn settings | tr -d '\r-' | sed 's/^ *//')"
    options="$options\nback"

    # launch wofi and select option
    selected=$(printf %b "$options" | $MENU_CMD -p "Settings" --x=-320 --width=260 --height=240)

    # do not keep cache
	  rm $CACHE_FILE

    # match selected option to command
    case $selected in
      "")
			  exit 0
        ;;
		  "back")
			  close="1"
	      ;;
      *)
        ;;
    esac

    if [[ "$close" == "" ]]; then
		  settings_menu
	  fi
}

# country selection
countries_menu() {
    local options selected close
    options=$(nordvpn countries | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)
    options="back\ndefault\n$options"

    # launch wofi and select option
    selected=$(printf %b "$options" | $MENU_CMD -p "Countries" --x=-320 --width=200 --height=200)
    
    # do not keep cache
	  rm $CACHE_FILE

    # match selected option to command
    case $selected in
      "")
			  exit 0
        ;;
		  "back")
			  close="1"
	      ;;
      "default")
        nordvpn connect
        ;;
      *)
        nordvpn connect "$selected"
        ;;
    esac

    if [[ "$close" == "" ]]; then
		  countries_menu
	  fi
}

# city selection
cities_menu() {
    local options selected close country
    country=$1
    options=$(nordvpn cities "$country" | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)
    options="back\ndefault\n$options"

    # launch wofi and select option
    selected=$(printf %b "$options" | $MENU_CMD -p "Cities" --x=-320 --width=180 --height=200)

    # do not keep cache
    rm $CACHE_FILE

    # match selected option to command
    case $selected in
      "")
			  exit 0
        ;;
		  "back")
			  close="1"
	      ;;
      "default")
        nordvpn connect "$country"
        ;;
      *)
        nordvpn connect "$country" "$selected"
        ;;
    esac

	if [[ "$close" == "" ]]; then
		cities_menu "$country"
	fi
}

# country and city selection
countries_cities_menu() {
  local options selected close
  options=$(nordvpn countries | tr -d '\r,-' | tr -s "[:blank:]" "\n" | sed '/^\s*$/d' | sort)
  options="back\n$options"

  # launch wofi and select option
  selected=$(printf %b "$options" | $MENU_CMD -p "Countries" --x=-320 --width=200 --height=200)
    
  # do not keep cache
	rm $CACHE_FILE

  # match selected option to command
  case $selected in
    "")
		  exit 0
      ;;
	  "back")
		  close="1"
      ;;
    *)
      cities_menu "$selected"
      ;;
  esac

	if [[ "$close" == "" ]]; then
		countries_cities_menu
	fi
}

# nordvpn connect options
connect_menu() {
    local options selected close
    options="default\ncountries\ncities\np2p\nonion\nback"

    # launch wofi and select option
    selected=$(printf %b "$options" | $MENU_CMD -p "Connect" --x=-320 --width=140 --height=260)

    # do not keep cache
	rm $CACHE_FILE

    # match selected option to command
    case $selected in
        "")
			exit 0
            ;;
		"back")
			close="1"
	        ;;
        "default")
            nordvpn connect
            ;;
        "countries")
            countries_menu
            ;;
        "cities")
            countries_cities_menu
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

	if [[ "$close" == "" ]]; then
		connect_menu
	fi
}

# opens a wofi menu with nordvpn options to connect
nordvpn_menu() {
    local options selected close
    options="connect\ndisconnect\nstatus\nsettings\nexit"

    # launch wofi and select option
    selected=$(printf %b "$options" | $MENU_CMD -p "Nordvpn" --x=-320 --width=140 --height=230)

    # do not keep cache
	rm $CACHE_FILE

    # match selected option to command
    case $selected in
        "")
			exit 0
            ;;
		"exit")
			close="1"
	        ;;
        "connect")
            connect_menu
            ;;
        "disconnect")
            nordvpn disconnect
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

	if [[ "$close" == "" ]]; then
		nordvpn_menu
	fi
}

# main
nordvpn_menu
