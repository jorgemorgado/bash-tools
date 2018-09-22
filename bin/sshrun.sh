#!/bin/bash
#
# Runs a command on a remote servers list via SSH (using sudo if needed).
#
# Usage:
#
#   cat <servers_list> | ./sshrun "<remote command>"
#
# Type sshrun --help for some examples.
#
###########################################################################
# Author: Jorge Morgado <jorge (at) morgado (dot) ch>
# Copyright (c) 2013
# All Rights Reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
###########################################################################
#
# History:
#
# v1.0, 20121221 Initial release (Jorge Morgado <jorge (at) morgado (dot) ch>)
#

# Commands
SSH=`which ssh`
SSHOPTS=

# -----------------------------------------------------------------------------
# -- DON'T CHANGE ANYTHING BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING --

MYNAME="sshrun"
MYVER="1.0"

# Set some defaults
VERBOSE=
FLIST=
LIST=
SUDO=
SUDOPASS=

function _fatal()
{
    echo "${MYNAME}: ${1}" 1>&2
    exit ${2}
}

function _usage()
{
    cat << EOF
Usage: cat <servers_list> | ${MYNAME} [options] "<remote command(s)>"
Runs a command on a list of servers (as a regular user or using sudo).

Options:
  -h              Print this help
  -v              Print version information
  --verbose       Show hostname where running command(s)
  --flist <file>  A file with list of servers (one per line) to run command(s)
  --list <list>   Comma separated list of servers list to run command(s)
  --sudo          Run command using sudo (requires --flist or --list)
                  Make sure \`sudo' is in your \$PATH or it will fail silently.
  <sshargs>       Any ssh arguments

If input is provided from stdin (e.g. cat <servers_list> | ...), the list must
contain one server per line (same as with --flist). The command(s) should always
be quoted, otherwise there is no guarantee they won't be executed locally.

Examples:
   cat servers.txt | ${MYNAME} uptime
   cat servers.txt | ${MYNAME} --verbose "df -h"
   cat servers.txt | ${MYNAME} --verbose -l someuser -i /path/to/key "ps aux"
   ${MYNAME} --list "host1, host2, hostN" --verbose "cat /proc/version; uptime"
   ${MYNAME} --list "host1, host2, hostN" --sudo "apt-get install pckname"
   ${MYNAME} --list "\`cat servers.csv\`" --verbose --sudo "lsof -i :443"
   ${MYNAME} --flist servers.txt --verbose --sudo "lsof -i :443"

EOF

    exit ${1}
}

function _version()
{
    echo "${MYNAME}, version ${MYVER}"
    echo "Copyright(c) 2013"
    exit 0
}

# The arguments list
declare -a ARGS=("$@")

# Cycles over the list and looks for "well-known" arguments to this script 
# Other "not so well-known" arguments will be passed to the ssh command
FTOKEN=
LTOKEN=
for (( n=0; n<${#ARGS[@]}; n++ )); do
    if [[ -n "${FTOKEN}" ]]; then
        FLIST="${ARGS[${n}]}"
        FTOKEN=
        ARGS[${n}]=            # remove the argument of --flist from ARGS
    elif [[ -n "${LTOKEN}" ]]; then
        LIST="${ARGS[${n}]}"
        LTOKEN=
        ARGS[${n}]=            # remove the argument of --list from ARGS
    else
        case "${ARGS[${n}]}" in
          --flist)
            FTOKEN=1
            ARGS[${n}]= ;;     # remove --flist from ARGS
          --list)
            LTOKEN=1
            ARGS[${n}]= ;;     # remove --list from ARGS
          --sudo)
            # Make sure that sudo is in your path or it will fail silently
            SUDO="sudo -S"
            SSHOPTS="-tt"
            ARGS[${n}]= ;;     # remove --sudo from ARGS
          --verbose)
            VERBOSE=1
            ARGS[${n}]= ;;     # remove --verbose from ARGS
          -h|--help) _usage 0;;
          -v|--version) _version;;
        esac
    fi
done

# Check if you have ssh installed
[[ -x "${SSH}" ]] || \
  _fatal "ssh command not found: Please check your \$PATH" 2

# Test if we have more than one list and if flist can be red
if [[ -n "${FLIST}" ]]; then
    [[ -n "${LIST}" ]] && \
      _fatal "you can specify only one list using --flist or --list" 3

    [[ -f "${FLIST}" ]] || \
      _fatal "servers list not found (${FLIST}): File not found" 4
    [[ -r "${FLIST}" ]] || \
      _fatal "can't read servers list (${FLIST}): Permission denied" 4
fi

# The position of the last argument, i.e., the command to run
declare -i LAST=$(( ${#ARGS[@]} - 1 ))

# If sudo without a servers list in a real file
if [[ -n "${SUDO}" ]]; then
    [[ -z "${FLIST}" ]] && [[ -z "${LIST}" ]] && \
      _fatal "sudo requires a servers list (--flist or --list)" 5

    printf "Please enter your sudo password: "
    stty -echo
    read SUDOPASS
    stty echo
    printf '\n'

    ARGS[${LAST}]="echo '${SUDOPASS}' | ${SUDO} ${ARGS[${LAST}]} 2>/dev/null"
fi

# Server's list
declare -a SERVER
declare -i IDX=0

OLDIFS=${IFS}
# If the servers list has been provided as an argument
if [[ -n "${FLIST}" ]]; then
    while IFS= read -r LINE; do
        SERVER[(( IDX++ ))]=${LINE}
    done < ${FLIST}
elif [[ -n "${LIST}" ]]; then
    IFS=$',' ; for LINE in ${LIST}; do
        SERVER[(( IDX++ ))]=${LINE}
    done
# Else, reads the list from stdin
else
    while IFS= read -r LINE; do
        SERVER[(( IDX++ ))]=${LINE}
    done
fi
IFS=${OLDIFS}

# Now, it's time to work on those servers
for HOST in "${SERVER[@]}"; do
    # Be verbose?
    [[ -n "${VERBOSE}" ]] && echo "# ${MYNAME} on ${HOST//[[:space:]]/}"

    ${SSH} ${SSHOPTS} ${ARGS[@]:0:${LAST}} ${HOST} "${ARGS[${LAST}]}"
done

exit 0
