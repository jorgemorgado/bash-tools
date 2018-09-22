#!/bin/bash
#
# A secure way to copy files between two different hosts that don't have
# connectivity between each other. This is mostly useful if you need to
# transfer files between two hosts in different networks but that share
# a common jump-host.
#
# Usage:
#
#   skp [<user>@]<src-host>:/src/path [<user>@]<dst-host>:/dst/path
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
# v1.0, 20121214 Initial release (Jorge Morgado <jorge (at) morgado (dot) ch>)
#

# Where to create temporary storage for the copy
TMPDIR=/var/tmp

# Commands
SCP=`which scp`

# -----------------------------------------------------------------------------
# -- DON'T CHANGE ANYTHING BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING --

MYNAME="skp"
MYVER="1.0"

function _fatal()
{
    echo "${MYNAME}: ${1}" 1>&2
    exit ${2}
}

function _usage()
{
cat << EOF
Usage: ${MYNAME} [options] [user@]src-host:/src/path [user@]dst-host:/dst/path

Options:
  -h         Print this help
  -v         Print version information
  <sshargs>  Any scp arguments for both <src> and <dst> hosts

EOF

    exit ${1}
}

function _version()
{
    echo "${MYNAME}, version ${MYVER}"
    echo "Copyright(c) 2013"
    exit 0
}

# Check if you have scp installed
[[ -x "${SCP}" ]] || \
  _fatal "scp command not found. Please check your \$PATH." 1

# Check for specific arguments (all other args will be passed to scp command)
while getopts ":hv" OPT; do
    case ${OPT} in
      h)
        # show usage information if -h or --help
        _usage 0;;
      v)
        # show version information if -v or --version
        _version;;
    esac
done

# Ensure we have at least src and dst hosts
[[ $# -lt 2 ]] && _usage 2
 
# Get all arguments into an array
declare -a ARRAY=("$@")

# Source and destination hosts are the two last arguments to skp
SRC=${ARRAY[(( ${#ARRAY[@]} - 2 ))]}
DST=${ARRAY[(( ${#ARRAY[@]} - 1 ))]}

# Ensure src and dst hosts don't start with '-' (like plain scp arguments)
[[ "${SRC:0:1}" == "-" ]] || [[ "${DST:0:1}" == "-" ]] && _usage 3

# Everything else are arguments to scp on both hosts
declare -i LEN=${#ARRAY[@]}
ARGS=${ARRAY[@]:0:(( ${LEN} - 2 ))}

# Create temporary folder
TMP=$( mktemp -d ${TMPDIR:-.}/${MYNAME}-XXXX )
RET=${?}

if [[ ${RET} -eq 0 ]]; then
    # Copy from src host to local
    ${SCP} ${ARGS} ${SRC} ${TMP}
    RET=${?}

    if [[ ${RET} -eq 0 ]]; then
        # Copy from local to dst host
        TARGET="${SRC#*:}"
        ${SCP} ${ARGS} ${TMP}/${TARGET##*/} ${DST}
        RET=${?}
    fi

    rm -rf "${TMP}" >/dev/null 2>&1
fi

exit ${RET}
