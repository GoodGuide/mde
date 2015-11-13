#!/bin/bash
# vim: set noexpandtab tabstop=4 shiftwidth=0:

set -e -u

{

trap 'onoes Interrupt.' INT
trap show_exit_messages EXIT

### Hot-executing script checksums for security
# These need to be multihashes (e.g. as created by the multihash CLI tool -- https://github.com/jbenet/go-multihash/tree/master/multihash)
# They probably need exported, as typically they are used by subshell commands
export chk_docker_vagrant_installer='QmdY2DQs2wvux2jbVUQ87bC5TPJt49UxEQ86RVWRVRfjuX'
export chk_nvm_installer='QmP3jCV4fxsRRyXLG39N9xSQtfPaqvkeTVvMNtnYCRAyrx'
export chk_goodguide_dotfiles_installer='QmeB57n7Cmj4eib4Lm4JJSfACs76y9RFVyWfxEFprT7PvJ'

export nvm_version='v0.29.0'

### BEGIN FUNCTIONS
	show_exit_messages() {
		local exit_status=$?
		# show which fallible tasks failed
		if [[ -f $fails_file ]]; then
			echo_section 'Failed Components'
			printf "\x1b[31m"
			echo "Some things failed. These aren't critical components, but you may"
			echo "wish to retry this script to attempt these failed items again."
			echo
			cat $fails_file | (while read failure; do echo "  - ${failure}"; done)
		fi
		if [[ $exit_status != 0 ]]; then
			echo_section "Failure"
			printf "\x1b[31m"
			echo "Exit status $exit_status"
		else
			echo_section "Success"
		fi
		echo
		echo "Take a look back at the output for any notices or warnings!"
		printf "\n\x1b[0m\n"
		exit $exit_status
	}

	onoes() {
		printf "\n\x1b[31m%b\x1b[0m\n" "$1" >&2
		exit 1
	}

	echo_section() {
		local width=`tput cols`
		printf "\n\x1b[0;7;1m %-$((width - 2))b \x1b[0m\n\n" "$1"
	}

	pause() {
		printf "\n\x1b[31m%b\x1b[0m\n" 'paused. press enter to continue'
		read
	}

	ask() {
		[[ ${ASSUME_YES:-false} == 'true' ]] && return 0
		printf "\x1b[32m%b (y/N)\x1b[0m " "$1"
		read -r -e -n 1
		[ "$(echo $REPLY | tr Y y)" = 'y' ]
	}

	ask_to_install() {
		ask "Would you like to install $1?"
	}

	brew_install_or_upgrade() {
		if brew_is_installed "$1"; then
			if brew_is_upgradable "$1"; then
				brew upgrade "$@"
			fi
		else
			brew install "$@"
		fi
	}

	brew_is_installed() {
		local name="$(brew_expand_alias "$1")"

		brew list -1 | grep -Fqx "$name"
	}

	brew_is_upgradable() {
		local name="$(brew_expand_alias "$1")"

		brew outdated --quiet | grep -Fqx "$name"
	}

	brew_expand_alias() {
		brew info --json=v1 "$1" | jq -r '.[].name'
	}

	brew_cask_is_installed() {
		brew cask list -1 | grep -Fqx "$1"
	}

	brew_cask_install() {
		if ! brew_cask_is_installed $1; then
			brew cask install $1
		fi
	}

	brew_tap() {
		if brew tap | grep -Fqx "$1"; then
			echo "Already tapped $1"
		else
			brew tap "$1"
		fi
	}

	add_to_profile() {
		for profile_file in bashrc zshrc; do
			local file="$HOME/.${profile_file}"
			[ -f "${file}" ] || touch "$file"
			echo "  $1"
			grep -Fqx "$1" "$file" && return
			echo "$1" >> "$file"
		done
	}

	mktmpdir() {
		mktemp -d ${TMPDIR}gg-mde.XXXXX
	}

	xcode_tools_are_installed() {
		'/usr/bin/xcode-select' --print-path >/dev/null 2>&1
	}

	wait_for() {
		local cmd="$2"
		local timeout="$1"
		local time_to_stop=$(( `date +'%s'` + $timeout ))
		eval "$cmd" && return 0
		while [[ $(date '+%s') -lt $time_to_stop ]]; do
			printf '.'
			sleep 3
			eval "$cmd" && return 0
		done
		return 1
	}

	record_failure() {
		echo $1 >>! $fails_file
	}

	InstallFormula() {
		local formula="$1"
		echo_section "Homebrew formula: $formula"
		if brew_is_installed "$formula"; then
			echo "Already installed"
			return 0
		else
			if brew_install_or_upgrade "$@"; then
				return 0
			else
				if [ ${fallible:-0} == '1' ]; then
					record_failure "brew install $formula"
					return 0
				else
					return 1
				fi
			fi
		fi
	}

	InstallCask() {
		local cask="$1"
		echo_section "Homebrew cask: $cask"
		if brew_cask_is_installed "$cask"; then
			echo "Already installed"
			return 0
		else
			if brew_cask_install "$@"; then
				return 0
			else
				if [ ${fallible:-0} == '1' ]; then
					record_failure "brew cask install $cask"
					return 0
				else
					return 1
				fi
			fi
		fi
	}

	OptionallyInstallCask() {
		local cask="$1"
		echo_section "Homebrew cask: $cask"
		if brew_cask_is_installed "$cask"; then
			echo "Already installed"
			return 0
		else
			ask_to_install "$cask" || return 0
			if brew_cask_install "$@"; then
				return 0
			else
				if [ ${fallible:-0} == '1' ]; then
					record_failure "brew cask install $cask"
					return 0
				else
					return 1
				fi
			fi
		fi
	}

	install_temp_jq() {
		if command -v jq >/dev/null; then
			printf "(already available)\n"
		else
			local tmp_bin_dir="$(mktmpdir)/bin"
			mkdir -p "${tmp_bin_dir}"
			curl -fsSL https://github.com/stedolan/jq/releases/download/jq-1.5/jq-osx-amd64 > "${tmp_bin_dir}/jq"
			chmod +x "${tmp_bin_dir}/jq"
			PATH="${tmp_bin_dir}:${PATH}"
			printf "(installed to ${tmp_bin_dir})\n"
		fi
	}

	install_temp_hashpipe() {
		if command -v hashpipe >/dev/null; then
			printf "(already available)\n"
		else
			local tmp_dir="$(mktmpdir)"
			local tmp_bin_dir="${tmp_dir}/bin"
			mkdir -p "${tmp_bin_dir}"
			curl -fsSL https://gobuilder.me/get/github.com/jbenet/hashpipe/hashpipe_master_darwin-amd64.zip > "${tmp_dir}/download.zip"
			unzip -d "${tmp_dir}" "${tmp_dir}/download.zip"
			cp -a "${tmp_dir}/hashpipe/hashpipe" "${tmp_bin_dir}/hashpipe"
			chmod +x "${tmp_bin_dir}/hashpipe"
			PATH="${tmp_bin_dir}:${PATH}"
			printf "(installed to ${tmp_bin_dir})\n"
		fi
	}
### END FUNCTIONS

printf "\x1b[0m"

export fails_file="$(mktemp -ut ggmde)"
export SUDO_PROMPT='Enter your user password for sudo: '

echo_section "GoodGuide Minimal Development Environment OSX Installer"

# Ensure running correctly
[[ ${EUID} == 0 ]] && onoes "Don't run as root!"
groups | grep -q admin || onoes 'Run this script as a user in the `admin` group'

echo -e "This script will require sudo access more than once, and your attention throughout.\n"

# Ask for the administrator password upfront
sudo -v

echo_section "Verifying FileVault is enabled"
fv_status="$(sudo fdesetup status)"
echo "$fv_status"
if ! echo "$fv_status" | grep -qE '^FileVault is On.' ; then
	onoes "Please enable it before running this again."
fi

echo_section "Installing OSX updates..."
log_file=$(mktemp -t ggmde)
sudo softwareupdate -iva | tee $log_file
if tail -n 3 $log_file | grep -q 'restart'; then
	echo
	echo "Reboot is required."
	echo
	echo "Please open Terminal.app and re-run this script after rebooting."
	exit 0
fi

echo_section "Installing XCode Command Line Tools"
if xcode_tools_are_installed; then
	echo 'Already installed.'
else
	echo "Installing the Command Line Tools (expect a GUI popup which requires your accepting an EULA):"
	'/usr/bin/xcode-select' --install
	echo -e "\nWill wait up to 30 minutes for installer to complete"
	if wait_for 1800 xcode_tools_are_installed; then
		sleep 5 # detection sometimes succeeds before it's totally ready :-/
	else
		onoes "Timeout waiting for XCode tools installer to complete"
	fi
fi

[[ ${HOMEBREW_PREFIX:-unset} != 'unset' ]] || export HOMEBREW_PREFIX="/usr/local"
if [[ ! -d ${HOMEBREW_PREFIX}/.git/ ]]; then
	echo_section "Homebrew: install"
	sudo /bin/mkdir -p "${HOMEBREW_PREFIX}"
	sudo /bin/chmod g+rwx "${HOMEBREW_PREFIX}"
	sudo /usr/bin/chgrp admin "${HOMEBREW_PREFIX}"
	sudo /bin/mkdir -p /Library/Caches/Homebrew
	sudo /bin/chmod g+rwx /Library/Caches/Homebrew
	(
		cd "${HOMEBREW_PREFIX}"
		git init -q
		git config remote.origin.url 'https://github.com/Homebrew/homebrew.git'
		git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
		git fetch origin master:refs/remotes/origin/master -n
		git reset --hard origin/master
	) || onoes "Homebrew failed to install. Try removing $HOMEBREW_PREFIX before trying again"
	# curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install | ruby
else
	echo_section 'Homebrew: update'
	brew update
fi

echo_section "getting temporary dependencies"
# We'll install jq using homebrew later, but we need it available to work with `brew info` output
printf -- "- jq "
install_temp_jq
printf -- "- hashpipe "
install_temp_hashpipe

echo_section "brew doctor"
brew doctor || ask "brew doctor shows warnings. Continue anyway?" || exit 0

echo_section "brew tap homebrew/boneyard"
brew_tap homebrew/boneyard

echo_section "brew tap goodguide/tap"
brew_tap goodguide/tap

echo_section "brew tap caskroom/cask"
brew_tap caskroom/cask

echo_section "Install Homebrew Cask"
brew_install_or_upgrade caskroom/cask/brew-cask

InstallCask java
export JAVA_HOME="$(/usr/libexec/java_home)"

echo_section "Install Oracle Java JCE Unlimited Strength Policy"
(
	set +e
	cd $JAVA_HOME/jre/lib/security/
	cat <<-EOSHA | shasum -sc -
		f6fb2af1e87fc622cda194a7d6b5f5f069653ff1  US_export_policy.jar
		517368ab2cbaf6b42ea0b963f98eeedd996e83e3  local_policy.jar
	EOSHA
	if [[ $? != 0 ]]; then
		set -e
		cd $(mktmpdir)
		curl -fsSOjLH 'Cookie: oraclelicense=accept-securebackup-cookie' \
			'http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip'
		unzip jce_policy-8.zip
		sudo cp -fv UnlimitedJCEPolicyJDK8/*.jar $JAVA_HOME/jre/lib/security/
	else
		echo "Already installed"
	fi
)

# Please keep these lists sorted to avoid git diff noise
#
# Necessary pkgs. If any of these fail, abort the script
fallible=0
InstallFormula autoconf
InstallFormula automake
InstallFormula awscli
InstallFormula cmake
InstallFormula coreutils
InstallFormula curl
InstallFormula direnv
InstallFormula docker
InstallFormula docker-compose
InstallFormula gcc
InstallFormula git
InstallFormula glib
InstallFormula go
InstallFormula goodguide-git-hooks
InstallFormula imagemagick
InstallFormula jq
InstallFormula libxml2
InstallFormula libxslt
InstallFormula maven
InstallFormula mysql
InstallFormula openssl
InstallFormula osx-remap-keyboard-modifiers
InstallFormula pv
InstallFormula python
InstallFormula python3
InstallFormula rbenv
InstallFormula reattach-to-user-namespace
InstallFormula ruby-build
InstallFormula tmux
InstallFormula tree
InstallFormula vim
InstallFormula wget --with-iri
InstallFormula zsh

# less essential packages:
fallible=1
InstallFormula ack
InstallFormula cloc
InstallFormula ctags
InstallFormula findutils
InstallFormula gawk
InstallFormula gnu-sed
InstallFormula gnu-tar
InstallFormula gnutls
InstallFormula htop
InstallFormula innotop
InstallFormula leiningen
InstallFormula markdown
InstallFormula mosh
InstallFormula pandoc
InstallFormula parallel
InstallFormula pcre
InstallFormula rlwrap
InstallFormula selecta
InstallFormula socat
InstallFormula sqlite
InstallFormula the_silver_searcher
InstallFormula watch

echo_section "Installing NodeJS Version Manager (nvm)"
# install NVM at ~/.nvm
export NVM_DIR="$HOME/.nvm"
bash <(curl -s "https://raw.githubusercontent.com/creationix/nvm/${nvm_version}/install.sh" | hashpipe $chk_nvm_installer)
# use a subshell to load NVM and install Node and packages. (NVM isn't compatible with the -u bash runtime option.)
(
	set +u
	[ -s "$NVM_DIR/nvm.sh" ] \
		&& source "$NVM_DIR/nvm.sh" \
		&& [ $(type -t nvm) = 'function' ] \
		|| onoes 'NVM installation seems to have failed'

	nvm install node # install latest NodeJS stable release
	nvm use node # set PATH to use that NodeJS installation
	nvm alias default node # set up NVM to load this node as the default for any subsequent shells

	echo_section "Installing phantomjs as NPM package"
	npm install -g phantomjs

	echo_section "Installing ietcrl as NPM package"
	npm install -g iectrl
)

echo_section "Testing /etc/sudoers for Vagrant NFS sharing NOPASSWD exceptions"
if sudo grep -Fq 'VAGRANT_' /etc/sudoers; then
	echo "Already present in /etc/sudoers"
else
	cat <<-EOF
		Vagrant supports NFS-based shared folders, which docker-vagrant relies on by
		default for improved performance. This requires giving Vagrant root access so it
		can alter /etc/exports on your Mac, which means typing your password anytime you
		bring up docker-vagrant. There is a small set of commands that Vagrant needs to
		run, which means it's easy to craft sudoers exceptions to allow these changes
		without requiring your password.

		See more here: https://docs.vagrantup.com/v2/synced-folders/nfs.html

		This script can add these exceptions for you, if you'd like.
	EOF

	if ask "\nWould you like to set these NOPASSWD exceptions up now?"; then
		sudo cp -na /etc/sudoers /etc/sudoers.tmp || \
			onoes "Sudoers lockfile /etc/sudoers.tmp already exists!!!"

		cat <<-EOF | sudo tee -a /etc/sudoers.tmp

			# Vagrant NFS exceptions
			Cmnd_Alias VAGRANT_EXPORTS_ADD = /usr/bin/tee -a /etc/exports
			Cmnd_Alias VAGRANT_NFSD = /sbin/nfsd restart
			Cmnd_Alias VAGRANT_EXPORTS_REMOVE = /usr/bin/sed -E -e /*/ d -ibak /etc/exports
			%admin ALL=(root) NOPASSWD: VAGRANT_EXPORTS_ADD, VAGRANT_NFSD, VAGRANT_EXPORTS_REMOVE
		EOF

		sudo visudo -csf /etc/sudoers.tmp || onoes "ERROR: something weird happened..."
		sudo cp -a /etc/sudoers.tmp /etc/sudoers
		sudo chmod 0440 /etc/sudoers
		sudo chown root:wheel /etc/sudoers
		# just in case
		sudo visudo -cs
		sudo rm -f /etc/sudoers.tmp
		echo "Added successfully."
	fi
fi

echo_section "Installing docker-vagrant"
[ "${PREFIX:-unset}" = 'unset' ] && export PREFIX="$HOME/.local"
bash <(curl -fsSL https://raw.githubusercontent.com/GoodGuide/docker-vagrant/master/install.sh | hashpipe $chk_docker_vagrant_installer)
export PATH="${PREFIX}/bin:${PATH}"

echo_section 'Vagrant and VirtualBox'
echo 'Would you like this script to install VirtualBox & Vagrant via Homebrew Cask? If not, you will need to manually download these two packages from their respective websites and install yourself, as they are required for GG development on OSX.'
if ask_to_install 'vagrant and virtualbox'; then
	InstallCask vagrant
	InstallCask virtualbox

	echo_section "docker-vagrant provisioning"
	if ask 'Would you like to set up the docker-vagrant VM now? You can always do it later via `docker-vagrant up`.'; then
		docker-vagrant up
		docker-vagrant halt
	fi
fi

echo_section "Adding docker.dev hostname to /etc/hosts"
if grep -Eq '\sdocker.dev\b' /etc/hosts; then
	echo "Already present"
else
	echo -ne "Adding new host:\n\n	"
	printf '192.168.33.42\tdocker.dev\n' | sudo tee -a /etc/hosts
fi

echo_section "Dotfiles"
if ask_to_install 'goodguide/dotfiles'; then
	bash <(curl -fsSL https://raw.githubusercontent.com/GoodGuide/dotfiles/master/install.sh | hashpipe $chk_goodguide_dotfiles_installer)
fi

echo_section "Change shell to ZSH"
zsh_path="$(brew --prefix)/bin/zsh"
grep -Fqx "$zsh_path" /etc/shells || echo $zsh_path | sudo tee -a /etc/shells > /dev/null
if ask 'Would you like to use ZSH as your default shell?'; then
	chsh -s "$(brew --prefix)/bin/zsh" $USER
fi

echo_section "Altering shell RC"

add_to_profile '# The GoodGuide Onboarding MDE setup script added these lines:'
add_to_profile 'export PATH="'${PREFIX}'/bin:${PATH}"'
add_to_profile 'eval "$(rbenv init -)"'
add_to_profile '# Set up docker-vagrant'
add_to_profile "export DOCKER_HOST='tcp://docker.dev:2375'"
add_to_profile 'export NVM_DIR="$HOME/.nvm"'
add_to_profile '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm'
add_to_profile 'eval "$(direnv hook zsh)"'

}
