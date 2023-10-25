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

# Constants
divider="-------------------------"

# Rofi command to pipe into, can add any options here
wofi_command="wofi --dmenu --location=3 --x=-160 --cache-file=/tmp/wofi-dump-cache"

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
    else
        if rfkill list bluetooth | grep -q 'blocked: yes'; then
            rfkill unblock bluetooth && sleep 3
        fi
        bluetoothctl power on
    fi
}

# Checks if controller is scanning for new devices
scan_on() {
  if bluetoothctl show | grep -q "Discovering: yes"; then
    echo "scan (on)"
    return 0
  else
    echo "scan (off)"
    return 1
  fi
}

# Toggles scanning state
toggle_scan() {
    if scan_on; then
        kill $(pgrep -f "bluetoothctl scan on")
        bluetoothctl scan off
    else
        bluetoothctl scan on
        sleep 5
    fi
}

# Checks if controller is able to pair to devices
pairable_on() {
  if bluetoothctl show | grep -q "Pairable: yes"; then
    echo "pairable (yes)"
    return 0
  else
    echo "pairable (no)"
    return 1
  fi
}

# Toggles pairable state
toggle_pairable() {
    if pairable_on; then
        bluetoothctl pairable off
    else
        bluetoothctl pairable on
    fi
}

# Checks if controller is discoverable by other devices
discoverable_on() {
  if bluetoothctl show | grep -q "Discoverable: yes"; then
    echo "discoverable (yes)"
    return 0
  else
    echo "discoverable (no)"
    return 1
  fi
}

# Toggles discoverable state
toggle_discoverable() {
    if discoverable_on; then
        bluetoothctl discoverable off
    else
        bluetoothctl discoverable on
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
      echo "paired - yes"
      return 0
    else
      echo "paired - no"
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
      echo "trusted - yes"
        return 0
    else
      echo "trusted - no"
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
      connected="connected - yes"
    else
      connected="connected - no"
    fi
    paired=$(device_paired $mac)
    trusted=$(device_trusted $mac)
    options="$connected\n$paired\n$trusted"

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
        *)
            ;;
    esac
}

# opens a wofi menu with current bluetooth status and options to connect
bluetooth_menu() {

    # Get menu options
    if power_on; then
        power="turn off"

        # Human-readable names of devices, one per line
        # If scan is off, will only list paired devices
        full_devices=$(bluetoothctl devices)
        devices=$(printf %s "$full_devices" | grep Device | cut -d ' ' -f 3-)

        # Get controller flags
        scan=$(scan_on)
        pairable=$(pairable_on)
        discoverable=$(discoverable_on)

        # Options passed to wofi
        options="$devices\n$divider\n$power\n$scan\n$pairable\n$discoverable"
        
        width="200"
        height="240"
    else
        power="turn on"
        options="$power"
        
        width="100"
        height="80"
    fi
 
    # launch wofi and choose option
    chosen="$(echo -e "$options" | $wofi_command -p "Bluetooth" --width="$width" --height="$height")"

    # match chosen option to command
    case $chosen in
        $power)
            toggle_active
            bluetooth_menu
            ;;
        $scan)
            toggle_scan
            bluetooth_menu
            ;;
        $discoverable)
            toggle_discoverable
            bluetooth_menu
            ;;
        $pairable)
            toggle_pairable
            bluetooth_menu
            ;;
        "" | $divider)
            bluetooth_menu
            ;;
        *)
            local device
            device=$(printf %s "$full_devices" | grep "$chosen")
            # Open a submenu if a device is selected
            if [[ $device ]]; then
                device_menu "$device"
            else 
                bluetooth_menu
            fi
            ;;
    esac
}

# main
bluetooth_menu

# do not keep cache
rm "/tmp/wofi-dump-cache"