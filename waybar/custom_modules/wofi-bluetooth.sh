#!/usr/bin/env bash
#
# WOFI BLUETOOTH
#
# Source: https://github.com/arpn/wofi-bluetooth
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
whereis bluetoothctl > /dev/null || echoexit "'bluetoothctl' not found."

# constants
TMPDIR="/tmp"
CACHE_FILE="$TMPDIR/wofi-dump-cache"

# menu command to pipe into, can add any options here
MENU_CMD="wofi --dmenu --location=3 --cache-file=$CACHE_FILE"

# A submenu for a specific device that allows connecting, pairing, and trusting
device_menu() {
    local options selected close device device_name mac device_info
    device=$1

    # Get device name and mac address
    device_name=$(printf %s "$device" | cut -d ' ' -f 3)
    device_mac=$(printf %s "$device" | cut -d ' ' -f 2)
    device_info=$(bluetoothctl info "$device_mac")

    if $(printf %s "$device_info" | grep -q "Connected: yes"); then
        options="$options\nconnected [yes]"
    else
        options="$options\nconnected [no]"
    fi

    if $(printf %s "$device_info" | grep -q "Paired: yes"); then
        options="$options\npaired [yes]"
    else
        options="$options\npaired [no]"
    fi

    if $(printf %s "$device_info" | grep -q "Trusted: yes"); then
        options="$options\ntrusted [yes]"
    else
        options="$options\ntrusted [no]"
    fi

    options="$options\nback"

    # open wofi menu, read selected option
    selected="$(echo -e "$options" | $MENU_CMD -p "$device_name" --x=-160 --width=200 --height=230)"

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
        "connected [no]")
            bluetoothctl connect "$device_mac"
            ;;
        "connected [yes]")
            bluetoothctl disconnect "$device_mac"
            ;;
        "paired [no]")
            bluetoothctl pair "$device_mac"
            ;;
        "paired [yes]")
            bluetoothctl remove "$device_mac"
            ;;
        "trusted [no]")
            bluetoothctl trust "$device_mac"
            ;;
        "trusted [yes]")
            bluetoothctl untrust "$device_mac"
            ;;
        *)
            ;;
    esac

    if [[ "$close" == "" ]]; then
        device_menu "$device"
    fi
}

# opens a wofi menu with current bluetooth status and options to connect
bluetooth_menu() {
    local options selected close bluetooth_status bluetooth_enabled

    bluetooth_status=$(bluetoothctl show)
    bluetooth_enabled=$(printf %s "$bluetooth_status" | grep "Powered: yes")
     
    # Get menu options
    if [[ -n $bluetooth_enabled ]]; then
        local bluetooth_devices devices

        options="devices:"
        bluetooth_devices=$(bluetoothctl devices)

        devices=$(printf %s "$bluetooth_devices" | grep "Device" | cut -d ' ' -f 3 | sed "s/^/\t/g")
        if [[ -n "$devices" ]]; then
            options="$options\n$devices"
        fi

        if $(printf %s "$bluetooth_status" | grep -q "Discovering: yes"); then
            options="$options\nscan [on]"
        else
            options="$options\nscan [off]"
        fi

        if $(printf %s "$bluetooth_status" | grep -q "Pairable: yes"); then
            options="$options\npairable [yes]"
        else
            options="$options\npairable [no]"
        fi

        if $(printf %s "$bluetooth_status" | grep -q "Discoverable: yes"); then
            options="$options\ndiscoverable [yes]"
        else
            options="$options\ndiscoverable [no]"
        fi
        
        options="$options\nturn off"
    else
        options="turn on"
    fi

    options="$options\nexit"
 
    # launch wofi and choose option
    selected="$(echo -e "$options" | $MENU_CMD -p "Bluetooth" --x=-160 --width=200 --height=230)"

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
            if rfkill list bluetooth | grep -q 'blocked: yes'; then
                rfkill unblock bluetooth
                sleep 3
            fi
            bluetoothctl power on
            ;;
        "turn off")
            bluetoothctl power off
            ;;
        "scan [off]")
            (bluetoothctl scan on) &
            sleep 3
            ;;
        "scan [on]")
            kill $(pgrep -f "bluetoothctl scan on")
            bluetoothctl scan off
            ;;
        "pairable [off]")
            bluetoothctl pairable on
            ;;
        "pairable [on]")
            bluetoothctl pairable off
            ;;
        "discoverable [off]")
            bluetoothctl discoverable on
            ;;
        "discoverable [on]")
            bluetoothctl discoverable off
            ;;
        *)
            local sel device
            sel=$(printf %s "$selected" | trim_whitespaces)
            device=$(printf %s "$bluetooth_devices" | grep "$sel")
            if [[ -n $device ]]; then
                device_menu "$device"
            fi
            ;;
    esac

    if [[ "$close" == "" ]]; then
        bluetooth_menu
    fi
}

# main
bluetooth_menu
