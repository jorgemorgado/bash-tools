#!/bin/bash
#
# Compare two files in remote hosts line by line.
#
# Usage:
#
#   sshdiff [<user>@]<host1>:/path/to/file [<user>@]host2:/path/to/file
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
# v1.0, 20121227 Initial release (Jorge Morgado <jorge (at) morgado (dot) ch>)
#

# Where to create temporary storage for the files
TMPDIR=/var/tmp

# Commands
SCP=`which scp`
SCPOPTS=""
DIFF=`which colordiff || which diff`
DIFFOPTS=""

# -----------------------------------------------------------------------------
# -- DON'T CHANGE ANYTHING BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING --

MYNAME="sshdiff"
MYVER="1.0"

function _fatal()
{
    echo "${MYNAME}: ${1}" 1>&2
    exit ${2}
}

function _usage()
{
    cat << EOF
Usage: ${MYNAME} [options] [user@]host1:/path/to/file [user@]host2:/path/to/file
Compare two files in remote hosts line by line.

Options:
  -h                         Print this help
  -v                         Print version information
  -r, --recursive            Recursively compare any subdirectories found
  <sshargs>                  Any scp arguments for both hosts

Diff options:
  --unified[=NUM]            Output NUM (default 3) lines of copied context
  --context[=NUM]            Output NUM (default 3) lines of unified context
  --ignore-case              Ignore case differences in file contents
  --ignore-file-name-case    Ignore case when comparing file names
  --no-ignore-file-name-case Consider case when comparing file names
  --ignore-tab-expansion     Ignore changes due to tab expansion
  --ignore-all-space         Ignore all white space
  --ignore-blank-lines       Ignore changes whose lines are all blank
  --strip-trailing-cr        Strip trailing carriage return on input
  --text                     Treat all files as text
  --brief                    Output only whether files differ
  --ed                       Output an ed script
  --normal                   Output a normal diff
  --rcs                      Output an RCS format diff
  --side-by-side             Output in two columns
  --left-column              Output only the left column of common lines
  --suppress-common-lines    Do not output common lines
  --paginate                 Pass the output through \`pr' to paginate it
  --expand-tabs              Expand tabs to spaces in output
  --initial-tab              Make tabs line up by prepending a tab
  --minimal                  Try hard to find a smaller set of changes
  --speed-large-files        Assume large files and many scattered small changes

If you use \`-r', locations will be compared recursively - the argument will
be given to scp and diff. Just like a local diff, an exit status of 0 means no
differences were found, 1 means differences were found and 2 means some problem.

EOF

    exit ${1}
}

function _version()
{
    echo "${MYNAME}, version ${MYVER}"
    echo "Copyright(c) 2013"
    exit 2
}

# Check if you have scp installed
[[ -x "${SCP}" ]] || \
  _fatal "scp command not found: Please check your \$PATH" 2
[[ -x "${DIFF}" ]] || \
  _fatal "diff (or colordiff) commands not found: Please check your \$PATH" 2

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

# Ensure we have at least host1:file and host2:file
[[ $# -lt 2 ]] && _usage 2

# Get all arguments into an array
declare -a ARGS=("$@")
declare -i LEN=${#ARGS[@]}

# Files to compare are the two last arguments to sshdiff
FILE1=${ARGS[(( LEN - 2 ))]}
FILE2=${ARGS[(( LEN - 1 ))]}

# Ensure host1:file and host2:file don't start with '-' (like plain scp args)
[ "${FILE1:0:1}" == "-" ] || [ "${FILE2:0:1}" == "-" ] && _usage 2

# Cycles over the list and looks for "well-known" arguments to diff command
# Other "not so well-known" arguments will be passed to the scp command
# set brace expansion for the pattern matching below
for (( n=0; n<${LEN} - 2; n++ )); do
    case "${ARGS[${n}]}" in
      -r|--recursive)
        DIFFOPTS="${DIFFOPTS} --recursive"
        SCPOPTS="${SCPOPTS} -r"
        ;;
      --unified=*)
        declare -i UNIFIED=${ARGS[${n}]#*=}
        DIFFOPTS="${DIFFOPTS} -U${UNIFIED}" ;;
      --context=*)
        declare -i CONTEXT=${ARGS[${n}]#*=}
        DIFFOPTS="${DIFFOPTS} -C${CONTEXT}" ;;
      --context|--unified|--ignore-case|--ignore-file-name-case|--no-ignore-file-name-case|--ignore-tab-expansion|--ignore-all-space|--ignore-blank-lines|--strip-trailing-cr|--brief|--ed|--normal|--rcs|--side-by-side|--left-column|--suppress-common-lines|--text|--paginate|--expand-tabs|initial-tab|--minimal|speed-large-files)
        DIFFOPTS="${DIFFOPTS} ${ARGS[${n}]}" ;;
      *)
        # Any other options will be given to scp
        SCPOPTS="${SCPOPTS} ${ARGS[${n}]}" ;;
    esac
done

# Return TRUE if a file/directory is local; or FALSE if not
function _is_local()
{
    if [[ -e "${1}" ]]; then
        return 0
    else
        return 1
    fi
}

# Copy a remote file to local file system
# Returns TRUE/FALSE on success/error and echos the path to local file system
function _copy_to_local()
{
    local -i RET=0
    local TMP="${1}"

    # Create temporary folder
    TMP=$( mktemp -d ${TMPDIR:-.}/${MYNAME}-XXXX )
    RET=${?}

    # Copy file to local
    if [[ ${RET} -eq 0 ]]; then
        ${SCP} ${SCPOPTS} ${1} ${TMP} 1>/dev/null
        RET=${?}
    fi

    echo "${TMP}"
    return ${RET}
}


# NOTE: this script also works for local files! Although, there is no clear way
# to determine if a file is local or remote. E.g., if the argument "host:file"
# is given, that could both represent a local or a remote file. So, we try a
# different approach: the script always checks if the given argument exists
# as a local file or directory. On true, it assumes a local diff. The only
# (rare?) case where this will fail is when "host:file" represents both a local
# and a remote file and the user actually means the remote one. Still, even in
# this case, there should be possible to find an alternative name for the
# remote file (e.g. by giving the FQDN or IP address of the host).

if _is_local "${FILE1}"; then
    TMP1="${FILE1}"
else
    TMP1=$( _copy_to_local "${FILE1}" )
fi

if [[ ${?} == 0 ]]; then
    if _is_local "${FILE2}"; then
        TMP2="${FILE2}"
    else
        TMP2=$( _copy_to_local "${FILE2}" )
    fi

    if [[ ${?} == 0 ]]; then
        ${DIFF} ${DIFFOPTS} ${TMP1} ${TMP2}
    else
        RET=2
    fi

    # Cleanup FILE2 before exiting
    ! _is_local "${FILE2}" && [[ -n "${TMP2}" ]] && \
      rm -rf "${TMP2}" >/dev/null 2>&1
else
    RET=2
fi

# Cleanup FILE1 before exiting
! _is_local "${FILE1}" && [[ -n "${TMP1}" ]] && \
  rm -rf "${TMP1}" >/dev/null 2>&1

exit ${RET}
