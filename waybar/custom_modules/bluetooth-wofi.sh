#!/usr/bin/env bash
#
# BLUETOOTH-WOFI
#
# Source: https://github.com/arpn/wofi-bluetooth
#
# Forked from the excellent rofi-bluetooth script by Nick Clyde
# (https://github.com/nickclyde/rofi-bluetooth). Simply calls wofi
# instead of rofi.
#
# A script that generates a wofi menu that uses bluetoothctl to
# connect to bluetooth devices and display status info.
#
# Depends on:
#   Arch repositories: wofi, bluez-utils (contains bluetoothctl)


# exit when any command fails
set -T

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis bluetoothctl > /dev/null || echoexit "'bluetoothctl' not found."
whereis wofi > /dev/null || echoexit "'wofi' not found."

# Constants
divider="---------"
goback="Back"

# Rofi command to pipe into, can add any options here
wofi_command="wofi --dmenu --location=3 --x=-160"

# Checks if bluetooth controller is powered on
power_on() {
    if bluetoothctl show | grep -q "Powered: yes"; then
        return 0
    else
        return 1
    fi
}

# Toggles power state
toggle_power() {
    if power_on; then
        bluetoothctl power off
        show_menu
    else
        if rfkill list bluetooth | grep -q 'blocked: yes'; then
            rfkill unblock bluetooth && sleep 3
        fi
        bluetoothctl power on
        show_menu
    fi
}

# Checks if controller is scanning for new devices
scan_on() {
  if bluetoothctl show | grep -q "Discovering: yes"; then
    echo "Scan (On)"
    return 0
  else
    echo "Scan (Off)"
    return 1
  fi
}

# Toggles scanning state
toggle_scan() {
    if scan_on; then
        kill $(pgrep -f "bluetoothctl scan on")
        bluetoothctl scan off
        show_menu
    else
        bluetoothctl scan on &
        echo "Scanning..."
        sleep 5
        show_menu
    fi
}

# Checks if controller is able to pair to devices
pairable_on() {
  if bluetoothctl show | grep -q "Pairable: yes"; then
    echo "Pairable (On)"
    return 0
  else
    echo "Pairable (Off)"
    return 1
  fi
}

# Toggles pairable state
toggle_pairable() {
    if pairable_on; then
        bluetoothctl pairable off
        show_menu
    else
        bluetoothctl pairable on
        show_menu
    fi
}

# Checks if controller is discoverable by other devices
discoverable_on() {
  if bluetoothctl show | grep -q "Discoverable: yes"; then
    echo "Discoverable (On)"
    return 0
  else
    echo "Discoverable (Off)"
    return 1
  fi
}

# Toggles discoverable state
toggle_discoverable() {
    if discoverable_on; then
        bluetoothctl discoverable off
        show_menu
    else
        bluetoothctl discoverable on
        show_menu
    fi
}

# Checks if a device is connected
device_connected() {
    device_info=$(bluetoothctl info "$1")
    if echo "$device_info" | grep -q "Connected: yes"; then
        return 0
    else
        return 1
    fi
}

# Toggles device connection
toggle_connection() {
    if device_connected $1; then
        bluetoothctl disconnect $1
        device_menu "$device"
    else
        bluetoothctl connect $1
        device_menu "$device"
    fi
}

# Checks if a device is paired
device_paired() {
    device_info=$(bluetoothctl info "$1")
    if echo "$device_info" | grep -q "Paired: yes"; then
      echo "Paired (Yes)"
      return 0
    else
      echo "Paired (No)"
      return 1
    fi
}

# Toggles device paired state
toggle_paired() {
    if device_paired $1; then
        bluetoothctl remove $1
        device_menu "$device"
    else
        bluetoothctl pair $1
        device_menu "$device"
    fi
}

# Checks if a device is trusted
device_trusted() {
    device_info=$(bluetoothctl info "$1")
    if echo "$device_info" | grep -q "Trusted: yes"; then
      echo "Trusted (Yes)"
        return 0
    else
      echo "Trusted (No)"
        return 1
    fi
}

# Toggles device connection
toggle_trust() {
    if device_trusted $1; then
        bluetoothctl untrust $1
        device_menu "$device"
    else
        bluetoothctl trust $1
        device_menu "$device"
    fi
}

# Prints a short string with the current bluetooth status
# Useful for status bars like polybar, etc.
print_status() {
    if power_on; then
        printf ''

        mapfile -t paired_devices < <(bluetoothctl paired-devices | grep Device | cut -d ' ' -f 2)
        counter=0

        for device in "${paired_devices[@]}"; do
            if device_connected $device; then
                device_alias=$(bluetoothctl info $device | grep "Alias" | cut -d ' ' -f 2-)

                if [ $counter -gt 0 ]; then
                    printf ", %s" "$device_alias"
                else
                    printf " %s" "$device_alias"
                fi

                ((counter++))
            fi
        done
        printf "\n"
    else
        echo ""
    fi
}

# A submenu for a specific device that allows connecting, pairing, and trusting
device_menu() {
    device=$1

    # Get device name and mac address
    device_name=$(echo $device | cut -d ' ' -f 3-)
    mac=$(echo $device | cut -d ' ' -f 2)

    # Build options
    if device_connected $mac; then
      connected="Connected (Yes)"
    else
      connected="Connected (No)"
    fi
    paired=$(device_paired $mac)
    trusted=$(device_trusted $mac)
    options="$connected\n$paired\n$trusted\n$divider\n$goback"

    # Open wofi menu, read chosen option
    chosen="$(echo -e "$options" | $wofi_command -p "$device_name" --width="200" --height="230" )"

    # Match chosen option to command
    case $chosen in
        "" | $divider)
            echo "No option chosen."
            ;;
        $connected)
            toggle_connection $mac
            ;;
        $paired)
            toggle_paired $mac
            ;;
        $trusted)
            toggle_trust $mac
            ;;
        $goback)
            show_menu
            ;;
    esac
}

# Opens a wofi menu with current bluetooth status and options to connect
show_menu() {
    # Get menu options
    if power_on; then
        power="Turn Off"

        # Human-readable names of devices, one per line
        # If scan is off, will only list paired devices
        devices=$(bluetoothctl devices | grep Device | cut -d ' ' -f 3-)

        # Get controller flags
        scan=$(scan_on)
        pairable=$(pairable_on)
        discoverable=$(discoverable_on)

        # Options passed to wofi
        options="$devices\n$divider\n$power\n$scan\n$pairable\n$discoverable"
        
        width="200"
        height="240"
    else
        power="Turn On"
        options="$power"
        
        width="100"
        height="80"
    fi
 
    # Open wofi menu, read chosen option
    chosen="$(echo -e "$options" | $wofi_command -p "Bluetooth" --width="$width" --height="$height")"

    # Match chosen option to command
    case $chosen in
        "" | $divider)
            echo "No option chosen."
            ;;
        $power)
            toggle_power
            ;;
        $scan)
            toggle_scan
            ;;
        $discoverable)
            toggle_discoverable
            ;;
        $pairable)
            toggle_pairable
            ;;
        *)
            device=$(bluetoothctl devices | grep "$chosen")
            # Open a submenu if a device is selected
            if [[ $device ]]; then device_menu "$device"; fi
            ;;
    esac
}

case "$1" in
    --status)
        print_status
        ;;
    *)
        show_menu
        ;;
esac
