# /etc/skel/.bash_profile

# This file is sourced by bash for login shells.  The following line
# runs your .bashrc and is recommended by the bash info pages.
if [[ -f ~/.bashrc ]] ; then
	. ~/.bashrc
fi

# set xdg_runtime_dir for sway without systemd
if test -z "${XDG_RUNTIME_DIR}"; then
	_uid="$(id -u)"
	export XDG_RUNTIME_DIR="/tmp/${_uid}-runtime-dir"
	if ! test -d "${XDG_RUNTIME_DIR}"; then
		mkdir "${XDG_RUNTIME_DIR}"
		chmod 0700 "${XDG_RUNTIME_DIR}"
	fi
fi

# Set XDG_CONFIG_HOME
export XDG_CONFIG_HOME="${HOME}/.config"
