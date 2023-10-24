#!/bin/sh
#
# METWORK MANAGER WOFI
#

# exit when any command fails
set -T

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis nmctl > /dev/null || echoexit "'nmctl' not found."
whereis wofi > /dev/null || echoexit "'wofi' not found."

# Call pytohn script
python $HOME/.config/waybar/custom_modules/network-wofi.py --dmenu --location=3 --x="-120"

