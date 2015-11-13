#!/bin/bash
# vim: set noexpandtab tabstop=4 softtabstop=4 shiftwidth=4 textwidth=0:

# This script is meant to be run on an unprovisioned environment via the familiar `curl | bash` (hack) style invocation. This is useful for systems before any of even the most basic tools are available, such as git.

{ # this ensures the whole script is downloaded before evaulation

set -e -u

red(){
	echo -e "\n\x1b[31m$1\x1b[0m" >&2
}

onoes() {
	red "$1"
	exit 1
}

can_exec(){
	silence command -v $1
}

silence() {
	$@ >/dev/null 2>&1
}

download_from_URL() {
	if can_exec curl; then
		curl -fsSL "$1"
	else
		wget -q -O- "$1"
	fi
}

exec_script_from_URL() {
	exec bash <(download_from_URL "$1")
}

case "$(uname -s)" in
	Darwin)
		exec_script_from_URL 'https://raw.githubusercontent.com/GoodGuide/mde/master/setup_OSX.sh'
	;;
	Linux)
		case "$(lsb_release -is)" in
			Ubuntu)
				exec_script_from_URL 'https://raw.githubusercontent.com/GoodGuide/mde/master/setup_Ubuntu.sh'
			;;
			*)
				onoes "There is no automated setup script for your Linux distribution!"
			;;
		esac
	;;
	*)
		onoes "There is no automated setup script for your OS!"
	;;
esac

} # this ensures the whole script is downloaded before evaulation
