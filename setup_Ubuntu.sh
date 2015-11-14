#!/bin/bash
# vim: set noexpandtab tabstop=4 softtabstop=4 shiftwidth=4 textwidth=0:

{ # this ensures the whole script is downloaded before evaulation

set -e -u

trap 'onoes Interrupt.' INT
trap show_exit_messages EXIT

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

	can_exec(){
		silence command -v $1
	}

	silence() {
		$@ >/dev/null 2>&1
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

	add_to_profile() {
		cat >> "$tmp_profile_file"
		echo >> "$tmp_profile_file"
	}

	append_profile_lines_to_real_shell_profile() {
		echo -e '\n# The GoodGuide Onboarding MDE setup script added these lines:' >> "$1"
		cat "$tmp_profile_file" >> "$1"
	}

	mktmpdir() {
		mktemp --tmpdir -d gg-mde.XXXXX
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

### END FUNCTIONS

### START RUN
printf "\x1b[0m"

export fails_file="$(mktemp -u --tmpdir ggmde.XXXXX)"
export tmp_profile_file="$(mktemp -u --tmpdir ggmde.profile.XXXXX)"
export SUDO_PROMPT='Enter your user password for sudo: '
export PREFIX="${PREFIX:-/usr/local}"

# Make sure this PREFIX makes it into the PATH later
echo 'export PATH="'${PREFIX}'/bin:${PATH}"' | add_to_profile

echo_section "GoodGuide Minimal Development Environment OSX Installer"

echo -e "This script will require sudo access more than once, and your attention throughout.\n"

# Ask for the administrator password upfront
sudo -v

echo_section 'Install apt packages'
sudo aptitude update

sudo aptitude --assume-yes --without-recommends install \
	build-essential \
	imagemagick \
	libfontconfig \
	libfreetype6 \
	libmysqlclient-dev \
	libssl-dev \
	libxml2 \
	pv \
	jq \
	git \
	curl \
	coreutils \
	automake \
	autoconf \
	golang-go \
	libxslt-dev \
	libxml2-dev \
	maven2 \
	python \
	python3 \
	tree \
	htop \
	vim \
	tmux \
	zsh \
	ack-grep \
	cloc \
	ctags \
	findutils \
	sed \
	gawk \
	gnupg \
	innotop \
	mosh \
	parallel \
	socat \
	procps \
	zsh \
	python-dev

# TODO: install awscli,

sudo aptitude -y clean

# TODO: check for existence of Java 8 here and check for security policy installation before skipping this section
if ! can_exec 'java'; then
	echo_section 'Setup Oracle Java 8'
	sudo apt-add-repository -y ppa:webupd8team/java
	sudo apt-get update
	echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | \
		sudo debconf-set-selections
	sudo apt-get install -y oracle-java8-installer

	export JAVA_HOME=$(readlink -f $(which java) | sed "s:jre/bin/java::")
	echo "export JAVA_HOME='${JAVA_HOME}'" | sudo tee /etc/profile.d/java-8-oracle.sh > /dev/null

	# Grab the fully-open security policy
	sudo mkdir -p "${JAVA_HOME}/jre/lib/security/"
	curl -fsSL 'https://s3.amazonaws.com/code.goodguide.com/unlimited_jce_policy.tar.gz' | \
		sudo tar -C "${JAVA_HOME}/jre/lib/security/" -xvzf -
fi

if ! can_exec 'direnv'; then
	echo_section 'Install direnv'
	if ! sudo aptitude install direnv; then
		silence pushd "$(mktmpdir)"
		curl -fsSL -o ./direnv 'https://github.com/direnv/direnv/releases/download/v2.6.0/direnv.linux-amd64'
		sudo install -o root -g root ./direnv "$PREFIX/bin/direnv"
		silence popd
	fi
	echo 'eval "$(direnv hook $(basename $SHELL))"' | add_to_profile
fi

if ! can_exec 'phantomjs'; then
	echo_section 'Install PhantomJS'
	silence pushd /opt
	curl -fsSL 'https://s3.amazonaws.com/downloads.goodguide.com/phantomjs-1.9.8-linux-x86_64.tar.bz2' | \
		sudo tar xjf -
	sudo ln -s /opt/phantomjs-1.9.8-linux-x86_64/bin/phantomjs /usr/local/bin/phantomjs
	silence popd
fi

if ! can_exec 'rbenv'; then
	echo_section 'Install rbenv'
	rbenv_dir="$HOME/.rbenv"
	export PATH="$rbenv_dir/bin:$PATH"
	if can_exec 'rbenv'; then
		echo 'rbenv available at standard path. Assuming already installed.'
	else
		git clone https://github.com/sstephenson/rbenv.git "$rbenv_dir"
		git clone https://github.com/sstephenson/ruby-build.git "$rbenv_dir/plugins/ruby-build"
	fi
	# load rbenv now for use in this script
	eval "$(rbenv init -)"

	cat <<-EOF | add_to_profile
	# load rbenv
	export PATH="\$HOME/.rbenv/bin:\${PATH}"
	eval "\$(rbenv init -)"
	EOF
fi

echo_section 'Install Docker and tools'
if ! can_exec 'docker'; then
	# install docker's key
	sudo apt-key adv --keyserver 'hkp://p80.pool.sks-keyservers.net:80' --recv-keys '58118E89F3A912897C070ADBF76221572C52609D'

	ubuntu_version=$(lsb_release -sc)
	cat <<EOF | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
deb https://apt.dockerproject.org/repo ubuntu-${ubuntu_version} main
EOF

	sudo aptitude update
	sudo aptitude install docker-engine "linux-image-extra-$(uname -r)"
fi

if ! can_exec 'docker-compose'; then
	echo_section 'Install docker-compose'
	silence pushd $(mktmpdir)
	curl -fsSL -o ./docker-compose "https://github.com/docker/compose/releases/download/1.4.2/docker-compose-`uname -s`-`uname -m`"
	sudo install -o root -g root ./docker-compose "$PREFIX/bin/docker-compose"
	silence popd
fi

echo_section 'Test docker setup is working'
sudo docker run --rm busybox sh -c 'echo I AM ALIVE'

cat <<-EOF | add_to_profile
# this line is only necessary to satisfy checks in some init scripts which check
# the existence of this variable for OSX users
export DOCKER_HOST='unix:///var/run/docker.sock'
EOF

echo_section "Installing NodeJS Version Manager (nvm)"
# install NVM at ~/.nvm
export nvm_version='v0.29.0'
export NVM_DIR="$PREFIX/nvm"
bash <(curl -fsSL "https://raw.githubusercontent.com/creationix/nvm/${nvm_version}/install.sh")
# use a subshell to load NVM and install Node and packages. (NVM isn't compatible with the -u bash runtime option.)
(
	set +u
	unset PREFIX
	[ -s "$NVM_DIR/nvm.sh" ] \
		&& source "$NVM_DIR/nvm.sh" \
		&& [ $(type -t nvm) = 'function' ] \
		|| onoes 'NVM installation seems to have failed'

	nvm install node # install latest NodeJS stable release
	nvm use node # set PATH to use that NodeJS installation
	nvm alias default node # set up NVM to load this node as the default for any subsequent shells

	# echo_section "Installing phantomjs as NPM package"
	# npm install -g phantomjs
	cat <<-EOF | add_to_profile
	# load NVM
	export NVM_DIR="${PREFIX}/nvm"
	[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
	EOF
)

# many GG scripts have this hostname hard-coded in example configs, as it's used frequently in non-linux environments to refer to the docker VM. To make things easy, let's add it to this box as well, even though it's its own docker host and this name refers to localhost here.
echo_section "Adding docker.dev hostname to /etc/hosts"
if grep -Eq '\sdocker.dev\b' /etc/hosts; then
	echo "Already present"
else
	echo -ne "Adding new host:\n\n	"
	printf '127.0.0.1\tdocker.dev\n' | sudo tee -a /etc/hosts
fi

if [[ ! -d $HOME/.dotfiles ]]; then
	echo_section "Dotfiles"
	if ask_to_install 'goodguide/dotfiles'; then
		bash <(curl -fsSL https://raw.githubusercontent.com/GoodGuide/dotfiles/master/install.sh)
	fi
fi

# only set this *after* dotfiles may have been installed, to avoid writing to a profile which gets clobbered by dotfiles installation
export profile_file="$HOME/.bashrc"

echo_section "Change shell to ZSH"
if ask 'Would you like to use ZSH as your default shell?'; then
	chsh -s "$(which zsh)" $USER
	echo "Shell set to $(which zsh)"
	export profile_file="$HOME/.zshrc"
fi

echo_section "Altering shell RC: $profile_file"
append_profile_lines_to_real_shell_profile "$profile_file"

} # this ensures the whole script is downloaded before evaulation
