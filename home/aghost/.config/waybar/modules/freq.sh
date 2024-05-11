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
	local cpus cpus_array freq freq_c freq_d tooltip
	
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
		freq_iter=$(doas /bin/cat "/sys/devices/system/cpu/${cpu}/cpufreq/cpuinfo_cur_freq")
		freq_iter=$(printf "%s\n" "scale=1; $freq_iter/1000000" | bc -l)

		# add info to tooltip
		tooltip+="\n${cpu}: ${freq_iter}GHz"

		# add frequecy to average
		freq=$(printf "%s\n" "scale=1; $freq + $freq_iter" | bc -l)
	done

	# calc average
	freq=$(printf "%s\n" "scale=1; $freq / ${#cpus_array[@]}" | bc -l)

	# add average to tooltip
	tooltip="Avg: ${freq}GHz${tooltip}"

	# get level
	freq_c=$(printf "%s\n" "scale=1; $freq * 1000" | bc -l | cut -d "." -f 1)
	if (( $freq_c > 1800 )); then
		level="high"
	elif (( $freq_c >= 1400 )); then
		level="medium"
	elif (( $freq_c < 1400 )); then
		level="low"
	fi

	# round to 1
	freq_d=$(printf '%.*f\n' 1 "$freq")

	# return result
	printf "%s\n" "{\"text\":\"${freq_d}GHz\",\"tooltip\":\"$tooltip\",\"class\":\"$level\",\"alt\":\"$level\"}"
}

# main
waybar_json
