#!/bin/sh
#
# WAYBAR NORDVPN
#
# Based on: https://github.com/etrigan63/wofi-nordvpn
#

# exit when any command fails
set -T

echoexit() {
  # Print to stderr and exit
  printf "%s\n" "$@" 1>&2
  exit 1
}

# Checking dependencies:
whereis nordvpn-rc > /dev/null || echoexit "'nordvpn-rc' not found."

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
	local cpus cpus_array freq tooltip
	
	# get cpus
	cpus=$(ls "/sys/devices/system/cpu" | grep "^cpu" | grep -v "cpufreq" | grep -v "cpuidle")
	
	freq="0"
	tooltip=""
	cpus_array=()
	IFS=$'\n' read -rd '' -a cpus_array <<< "$cpus"
	for i in "${cpus_array[@]}"; do
		local cpu freq_iter
		cpu=$i

		# get cpu frequency
		freq_iter=$(sudo cat "/sys/devices/system/cpu/${cpu}/cpufreq/cpuinfo_cur_freq")
		freq_iter=$(( $freq_iter / 1000 ))

		# add info to tooltip
		tooltip+="\n${cpu}: ${freq_iter}MHz"

		# add frequecy to average
		freq=$(( $freq + $freq_iter ))
	done

	# calc average
	freq=$(( $freq / ${#cpus_array[@]} ))

	# add average to tooltip
	tooltip="Total: ${freq}MHz${tooltip}"

	# get level
	if (( $freq > 1800 )); then
		level="high"
	elif (( $freq >= 1400 )); then
		level="medium"
	elif (( $freq < 1400 )); then
		level="low"
	fi

	# change to GHz
	freq=$(printf "%s\n" "scale=1; $freq/1000" | bc -l)

	# return result
	printf "%s\n" "{\"text\":\"${freq}GHz\",\"tooltip\":\"$tooltip\",\"class\":\"$level\",\"alt\":\"$level\"}"
}

# main
waybar_json
