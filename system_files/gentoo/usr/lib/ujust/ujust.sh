#!/usr/bin/bash
# Minimal Universal Blue-style helpers for gentoo-ing ujust recipes.
# Provides the subset of /usr/lib/ujust/ujust.sh that custom recipes use.
# Everything is backed by gum (app-shells/gum) installed at build time.

Choose() {
	gum choose "$@"
}

Confirm() {
	gum confirm "$@"
}

# Basic ANSI colors for output niceness
bold="$(printf '\e[1m')"
underline="$(printf '\e[4m')"
normal="$(printf '\e[0m')"
red="$(printf '\e[31m')"
boldred="$(printf '\e[1;31m')"
green="$(printf '\e[32m')"
boldgreen="$(printf '\e[1;32m')"
yellow="$(printf '\e[33m')"
boldyellow="$(printf '\e[1;33m')"
blue="$(printf '\e[34m')"
boldblue="$(printf '\e[1;34m')"
magenta="$(printf '\e[35m')"
boldmagenta="$(printf '\e[1;35m')"
cyan="$(printf '\e[36m')"
boldcyan="$(printf '\e[1;36m')"
green_check="OK"
red_cross="X"