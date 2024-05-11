#!/bin/sh
#
# WAYBAR CPUTEMP
#

# exit when any command fails
set -T

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis bc > /dev/null || echoexit "'bc' not found."

trim_whitespaces() {
        local text
        text=$1
        if [[ "$text" == "" ]]; then
                read text
        fi
	text="${text#"${text%%[![:space:]]*}"}"
        printf %s "$text"
}

# nordvpn waybar module json format
waybar_json() {
	local temp_1 temp_2 temp_3 temp temp_int level

	# get temperature
	temp_1=$(cat /sys/class/thermal/thermal_zone*/temp)
	sleep 1
	temp_2=$(cat /sys/class/thermal/thermal_zone*/temp)
	sleep 1
	temp_3=$(cat /sys/class/thermal/thermal_zone*/temp)

	# calculate average
	temp=$(printf "%s\n" "scale=2; (($temp_1+$temp_2+$temp_3)/3)/1000" | bc -l)
	
	# get integer
	temp_int=$(printf '%.*f\n' 0 "$temp")

	# get level
	if (( $temp_int < 40 )); then
		level="very-low"
	elif (( $temp_int < 50 )); then
		level="low"
	elif (( $temp_int < 60 )); then
		level="normal"
	elif (( $temp_int < 80 )); then
		level="high"
	elif (( $temp_int >= 80 )); then
		level="very-high"
	fi

	# return result
	printf "%s\n" "{\"text\":\"$temp_int°C\",\"tooltip\":\"$temp°C\",\"class\":\"$level\",\"alt\":\"$level\"}"
}

# main
waybar_json
