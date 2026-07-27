#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202607271318-git
# @@Author           :  CasjaysDev
# @@Contact          :  CasjaysDev <docker-admin@casjaysdev.pro>
# @@License          :  WTFPL
# @@Copyright        :  Copyright 2026 CasjaysDev
# @@Created          :  Mon Jul 27 01:18:35 PM EDT 2026
# @@File             :  00-init.sh
# @@Description      :  script to run init
# @@Changelog        :  newScript
# @@TODO             :  Refactor code
# @@Other            :  N/A
# @@Resource         :  N/A
# @@Terminal App     :  yes
# @@sudo/root        :  yes
# @@Template         :  templates/dockerfiles/init_scripts/00-init.sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set bash options
set -eo pipefail
[ "$DEBUGGER" = "on" ] && echo "Enabling debugging" && set -x$DEBUGGER_OPTIONS
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set env variables
exitCode=0

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Predefined actions

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Main script

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the exit code
exitCode=$?
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit $exitCode
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
# - - - - - - - - - - - - - - - - - - - - - - - - -

