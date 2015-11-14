# GG Minimal Development Environment

## Supported Operating Systems

- OSX (tested thoroughly) -- see [setup_OSX.sh](/setup_OSX.sh)
- Ubuntu Linux (tested lightly on 14.04 and 15.10) -- see [setup_Ubuntu.sh](/setup_Ubuntu.sh)

## Installation

To install, run this in a terminal:

```
bash <(curl -fsSL 'https://raw.githubusercontent.com/GoodGuide/mde/master/remote_install.sh')
```

And if you don't have `curl`:
```
bash <(wget -q -O- 'https://raw.githubusercontent.com/GoodGuide/mde/master/remote_install.sh')
```

This script will determine which OS you're using, and if it's supported it will download and run the script needed to provision your machine.

## Further Contributions

If we seek more linux distro support, we should explore some of the linux provisioning tools already built which help to abstract the differences in distro, package managers, init systems, etc., rather that build new shell scripts for each distro.
