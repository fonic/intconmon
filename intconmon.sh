#!/usr/bin/env bash

# ------------------------------------------------------------------------------
#                                                                              -
#  Internet Connection Monitor (intconmon)                                     -
#                                                                              -
#  Created by Fonic <https://github.com/fonic>                                 -
#  Date: 10/17/22 - 08/09/23                                                   -
#                                                                              -
# ------------------------------------------------------------------------------

# --------------------------------------
#  Early tasks                         -
# --------------------------------------

# Check if running Bash and required version (check does not rely on any
# Bashisms to ensure it works on any POSIX shell)
if [ -z "${BASH_VERSION}" ] || [ "${BASH_VERSION%%.*}" -lt 4 ]; then
	echo "This script requires Bash >= 4.0 to run."
	exit 1
fi

# Determine platform / OS type (normalization here simplifies OS-specific
# checks/branches later on)
case "${OSTYPE,,}" in
	"linux"*)   PLATFORM="linux"; ;; # includes MS-WSL
	"darwin"*)  PLATFORM="macos"; ;;
	"freebsd"*) PLATFORM="freebsd"; ;;
	"msys"*)    PLATFORM="win-msys"; ;;
	"cygwin"*)  PLATFORM="win-cygwin"; ;;
	*)          PLATFORM="${OSTYPE,,}"
esac


# --------------------------------------
#  Globals                             -
# --------------------------------------

# Script paths/files
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")" # used in 'intconmon.conf'
SCRIPT_CONF="${SCRIPT_PATH%.*}.conf"
SCRIPT_LOG="${SCRIPT_PATH%.*}.log"
SCRIPT_VERSION="3.0 (2023-08-10)"

# Log message template (tokens: timestamp, type, message)
LOG_TEMPLATE="[%s] [%-8s] %s"

# Log message timestamp format (see 'man 1 date')
LOG_DATEFMT="%Y-%m-%d %H:%M:%S"

# List of recognized configuration variables (to dump these from config file,
# run the following command: 'grep -Po "^[^#=]+(?==)" intconmon.conf')
CONFIG_VARS=(
	MONITOR_IPV4
	MONITOR_IPV6
	MONITOR_INTERVAL
	HOST_IPV4_PRIMARY
	HOST_IPV4_SECONDARY
	HOST_IPV6_PRIMARY
	HOST_IPV6_SECONDARY
	PING_EXEC
	PING_OPTS_LINUX
	PING_OPTS_FREEBSD
	DNS_IPV4_PRIMARY
	DNS_IPV4_SECONDARY
	DNS_IPV6_PRIMARY
	DNS_IPV6_SECONDARY
	DNS_QUERY_HOST
	DNS_QUERY_TYPE
	DIG_EXEC
	DIG_OPTS
	DIG_QOPTS
	USRCMD_APP_START
	USRCMD_APP_STOP
	USRCMD_STATE_RESET
	USRCMD_ONLINE_IPV4
	USRCMD_OFFLINE_IPV4
	USRCMD_IPADDR_IPV4
	USRCMD_ONLINE_IPV6
	USRCMD_OFFLINE_IPV6
	USRCMD_IPADDR_IPV6
	#USRCMD_ALL_EVENTS # optional and also handled separately
	DEBUG_PING
	DEBUG_DIG
	DEBUG_USRCMD
)


# --------------------------------------
#  Functions                           -
# --------------------------------------

# Print and log message [$1: type, $2: color, $3: message]
function pl_msg() {
	#local type="$1" col="$2" msg="$3" ts="$(date +"${LOG_DATEFMT}")"               # slower as 'date' is an EXTERNAL command ('/bin/date')
	local type="$1" col="$2" msg="$3" ts; printf -v ts "%(${LOG_DATEFMT})T"         # faster as 'printf' is an INTERNAL command
	printf "\e[${col}m${LOG_TEMPLATE}\e[0m\n" "${ts}" "${type^^}" "${msg}" || :     # printing to stdout might fail (e.g. when script is detached from terminal)
	printf "${LOG_TEMPLATE}\n" "${ts}" "${type^^}" "${msg}" >> "${SCRIPT_LOG}" || : # writing to log might fail, but it seems wise to keep going anyway
}

# Print and log debug/info/warning/error/critical message [$*: message]
function pl_debug()    { pl_msg "debug"    "1;30" "$*"; }
function pl_info()     { pl_msg "info"     "0;37" "$*"; }
function pl_warn()     { pl_msg "warning"  "1;33" "$*"; }
function pl_error()    { pl_msg "error"    "1;31" "$*"; }
function pl_crit()     { pl_msg "critical" "1;35" "$*"; }

# Print and log start/stop/reset/exit/usrcmd/online/offline/ipaddr message [$*: message]
function pl_start()    { pl_msg "start"    "1;37" "$*"; }
function pl_stop()     { pl_msg "stop"     "1;37" "$*"; }
function pl_reset()    { pl_msg "reset"    "1;33" "$*"; }
function pl_exit()     { pl_msg "exit"     "1;33" "$*"; }
function pl_online4()  { pl_msg "online4"  "1;32" "$*"; }
function pl_online6()  { pl_msg "online6"  "1;32" "$*"; }
function pl_offline4() { pl_msg "offline4" "1;31" "$*"; }
function pl_offline6() { pl_msg "offline6" "1;31" "$*"; }
function pl_ipaddr4()  { pl_msg "ipaddr4"  "1;34" "$*"; }
function pl_ipaddr6()  { pl_msg "ipaddr6"  "1;34" "$*"; }

# Print and log command line [$1: print and log function, $2: preamble, $3: command, $4..$n: arguments]
function pl_cmdline() {
	local plfunc="$1" output="$2" arg; shift 2
	for arg; do
		if [[ "${arg}" =~ ^(--.+)=(.+)$ ]] && [[ "${BASH_REMATCH[2]}" == *[[:space:]]* || "${BASH_REMATCH[2]}" == *\\* ]]; then
			output+="${output:+ }${BASH_REMATCH[1]}=\"${BASH_REMATCH[2]}\""
		elif [[ "${arg}" == *[[:space:]]* || "${arg}" == *\\* || "${arg}" == "" ]]; then
			output+="${output:+ }\"${arg}\""
		else
			output+="${output:+ }${arg}"
		fi
	done
	"${plfunc}" "${output}"
}

# Check if variable is set [$1: variable name]
function is_set() {
	declare -p "$1" &>/dev/null
	return $?
}

# Check if command is available [$1: command name/path]
function is_cmd_avail() {
	command -v "$1" >/dev/null
	return $?
}

# Convert seconds value to hours-minutes-seconds string [$1: seconds value, $2: target variable]
function secs_to_hms() {
	local v=${1} h=0 m=0 s=0
	h=$((v / 3600)); v=$((v % 3600))
	m=$((v / 60));   v=$((v % 60))
	s=${v}
	printf -v "${2}" "%02d:%02d:%02d" "${h}" "${m}" "${s}"
}

# Run user-defined command [$1: event type, $2: elapsed seconds, $3: public IP address, $4: primary result, $5: secondary result, $6: command, $7..$n: arguments]
function run_usrcmd() {
	(( $# < 6 )) && return # no command to run (happens when configuration item is empty)
	local etype="$1" elaps="$2" pubip="$3" respr="$4" resse="$5" cmd="$6" args=("${@:7}") output retval
	args=("${args[@]/"%{ETYPE}"/"${etype}"}")
	args=("${args[@]/"%{ETIME}"/"${EPOCHSECONDS}"}")
	args=("${args[@]/"%{ELAPS}"/"${elaps}"}")
	args=("${args[@]/"%{HOST}"/"${HOSTNAME}"}")
	args=("${args[@]/"%{PUBIP}"/"${pubip}"}")
	args=("${args[@]/"%{RESPR}"/"${respr}"}")
	args=("${args[@]/"%{RESSE}"/"${resse}"}")
	[[ "${DEBUG_USRCMD}" == "true" ]] && pl_cmdline "pl_debug" "Running user-defined command:" "${cmd}" "${args[@]}"
	output="$("${cmd}" "${args[@]}" 2>&1)" && retval=$? || retval=$?
	if (( ${retval} == 0 )); then
		[[ "${DEBUG_USRCMD}" == "true" ]] && pl_debug "User-defined command result: retval: ${retval}, output: '${output//$'\n'/ }'"
	else
		pl_error "User-defined command failed: retval: ${retval}, output: '${output//$'\n'/ }'"
	fi
	return ${retval}
}

# Ping host [$1: IP version ('-4'/'-6'), $2: host, $3..$n: ping options]
function ping_host() {
	local ipver="$1" host="$2" popts=("${@:3}") output retval
	[[ "${DEBUG_PING}" == "true" ]] && pl_cmdline "pl_debug" "Pinging host '${host}':" "${PING_EXEC}" "${ipver}" "${popts[@]}" -- "${host}"
	output="$("${PING_EXEC}" "${ipver}" "${popts[@]}" -- "${host}" 2>&1)" && retval=$? || retval=$?
	[[ "${DEBUG_PING}" == "true" ]] && pl_debug "Ping result: retval: ${retval}, output: '${output//$'\n'/ }'"
	return ${retval}
}

# Lookup IP address of host via DNS [$1: IP version ('-4'/'-6'), $2: target variable, $3: DNS server, $4: query host, $5: query type, $6: dig options variable, $7: dig query options variable]
#
# DNS lookups using 'dig +short' can have five different outcomes:
# 1) exit code == 0, stdout == query response (obvious success)
# 2) exit code != 0, stdout == error message (obvious failure)
# 3) exit code == 0, stdout == error message [dig v9.16+]
# 4) exit code == 0, stdout == error message + query response [dig v9.18+]
#    (only if retries are allowed using options '+retry' and '+tries' and
#    query failed at first, but succeeded on retry)
# 5) exit code != 0, stdout == error message [dig v9.18+]
#    (only if retries are NOT allowed, i.e. '+retry=0' or '+tries=1', and
#    query failed)
#
# Solution:
# Run dig. If exit code != 0, return exit code. Otherwise unquote output (TXT
# responses might be doube-quoted, e.g. Google servers) and check if output
# resembles IPv4 or IPv6 address (very basic). If so, apply output and return
# 0. Otherwise return 255 (value is not used by dig itself according to man
# page)
#
# For details, refer to:
# https://gitlab.isc.org/isc-projects/bind9/-/issues/3615
#
# NOTE:    the rather peculiar order of dig arguments (server, options, host,
#          type, query options) conforms to what is specified in the man page
#          (see 'man 1 dig'); also, dig does not recognize '--' as terminator
# CAUTION: dig options (configuration item 'DIG_OPTS') and dig query options
#          (configuration item 'DIG_QOPTS') are passed/accessed via NAMEREFs;
#          make sure not to modify those by accident!
# TODO:    case 4) above is currently interpreted/treated as an error (output
#          does not resemble IP address -> retval=255); proper handling would
#          require processing output line by line and eliminating empty lines
#          and lines starting with ';'); fine as-is for now though as config-
#          uration item 'DIG_QOPTS' contains '+tries=1', thus case 4) should
#          not occur atm
function lookup_ipaddr() {
	local ipver="$1" server="$3" qhost="$4" qtype="$5" output retval
	local -n dstvar="$2" dopts="$6" dqopts="$7"
	[[ "${DEBUG_DIG}" == "true" ]] && pl_cmdline "pl_debug" "Querying DNS server '${server}':" "${DIG_EXEC}" "@${server}" "${ipver}" "${dopts[@]}" "${qhost}" "${qtype}" "${dqopts[@]}"
	output="$("${DIG_EXEC}" "@${server}" "${ipver}" "${dopts[@]}" "${qhost}" "${qtype}" "${dqopts[@]}" 2>&1)" && retval=$? || retval=$?
	if (( ${retval} == 0 )); then
		[[ "${output}" == \"*\" || "${output}" == \'*\' ]] && output="${output:1:-1}" # TXT responses might be doube-quoted (e.g. Google servers)
		[[ "${output}" =~ ^[0-9.]+$ || "${output}" =~ ^[0-9a-fA-F:]+$ ]] && dstvar="${output}" || retval=255 # output must resemble IPv4/IPv6 address
	fi
	[[ "${DEBUG_DIG}" == "true" ]] && pl_debug "Query result: retval: ${retval}, output: '${output//$'\n'/ }'"
	return ${retval}
}

# Sleep while allowing signals to interrupt [$1: duration]
# As kill might fail due to bad timing (e.g. when sleep dies/exits right before
# kill call), errors are masked using '&>/dev/null || :'
function int_sleep() {
	local dur="$1" pid sig
	sleep "${dur}" &
	pid=$!
	wait ${pid} && return 0 || { sig=$?; kill ${pid} &>/dev/null || : ; return ${sig}; }
}


# --------------------------------------
#  Main                                -
# --------------------------------------

# Set up error handling, set up temporary handler for important signals (will
# be replaced right before entering monitoring loop)
set -ue; trap "pl_error \"[BUG] An unhandled error occurred on line \${LINENO}\"" ERR
trap ":" INT TERM HUP USR1 USR2

# Check if log file exists, create if it does not, append spacer if it does
# (this also serves as a check if log file is actually creatable/writable;
# must not use 'pl_*()' functions for printing here for obvious reasons!)
if [[ ! -f "${SCRIPT_LOG}" ]]; then
	> "${SCRIPT_LOG}" || { echo -e "\e[1;31mError: failed to create log file, aborting.\e[0m"; exit 1; }
else
	echo "---" >> "${SCRIPT_LOG}" || { echo -e "\e[1;31mError: failed to write to log file, aborting.\e[0m"; exit 1; }
fi

# Print startup message, set up exit handler
pl_start "Internet Connection Monitor started (pid: $$)"
trap "pl_stop \"Internet Connection Monitor stopped (pid: $$)\"" EXIT
pl_info "Version: ${SCRIPT_VERSION}"
pl_info "Platform: ${PLATFORM}"

# Check if detected platform is supported
if [[ "${PLATFORM}" != "linux" && "${PLATFORM}" != "freebsd" ]]; then
	pl_error "Platform '${PLATFORM}' is currently not supported, aborting"
	exit 1
fi

# Source configuration (i.e. load configuration)
if ! source "${SCRIPT_CONF}"; then
	pl_error "Failed to read configuration file '${SCRIPT_CONF}', aborting"
	exit 1
fi

# Check configuration (very basic; checking monitoring interval is important
# in order to prevent a busy monitoring loop), check availability of required
# commands (makes sense to include this here as those are also configurable)
result=0
for cfgvar in "${CONFIG_VARS[@]}"; do
	is_set "${cfgvar}" || { pl_error "Config item '${cfgvar}': item is missing / not set"; result=1; }
done; unset cfgvar
if is_set "MONITOR_IPV4" && is_set "MONITOR_IPV6"; then
	[[ "${MONITOR_IPV4}" != "true" && "${MONITOR_IPV6}" != "true" ]] && { pl_error "Config item 'MONITOR_IPVx': neither IPv4 nor IPv6 is enabled"; result=1; }
fi
if is_set "MONITOR_INTERVAL"; then
	[[ "${MONITOR_INTERVAL}" =~ ^[0-9]+$ ]] && (( ${MONITOR_INTERVAL} > 0 )) || { pl_error "Config item 'MONITOR_INTERVAL': '${MONITOR_INTERVAL}' is not an integer value > 0"; result=1; }
fi
if is_set "PING_EXEC"; then
	is_cmd_avail "${PING_EXEC}" || { pl_error "Config item 'PING_EXEC': command '${PING_EXEC}' is not available"; result=1; }
fi
if is_set "DIG_EXEC"; then
	is_cmd_avail "${DIG_EXEC}" || { pl_error "Config item 'DIG_EXEC': command '${DIG_EXEC}' is not available"; result=1; }
fi
(( ${result} != 0 )) && { pl_error "Invalid configuration, aborting"; exit 1; }
unset result

# If configuration item 'USRCMD_ALL_EVENTS' is set, it overrides all other
# 'USRCMD_*' configuration items (i.e. it serves as 'master handler' for all
# possible events)
if is_set "USRCMD_ALL_EVENTS"; then
	for cfgvar in "${!USRCMD_@}"; do
		declare -n varref="${cfgvar}"
		varref=("${USRCMD_ALL_EVENTS[@]}")
	done; unset cfgvar; unset -n varref
fi

# Select ping options corresponding to detected platform
if [[ "${PLATFORM}" == "linux" ]]; then
	PING_OPTS=("${PING_OPTS_LINUX[@]}")
elif [[ "${PLATFORM}" == "freebsd" ]]; then
	PING_OPTS=("${PING_OPTS_FREEBSD[@]}")
fi

# Print configuration parameters
pl_info "Monitoring interval: ${MONITOR_INTERVAL}s"
pl_info "Ping executable: ${PING_EXEC}"
pl_info "Ping options: ${PING_OPTS[*]:-"(none)"}"
[[ "${MONITOR_IPV4}" == "true" ]] && pl_info "Ping hosts IPv4: ${HOST_IPV4_PRIMARY}, ${HOST_IPV4_SECONDARY}"
[[ "${MONITOR_IPV6}" == "true" ]] && pl_info "Ping hosts IPv6: ${HOST_IPV6_PRIMARY}, ${HOST_IPV6_SECONDARY}"
pl_info "Dig executable: ${DIG_EXEC}"
pl_info "Dig options: ${DIG_OPTS[*]:-"(none)"}"
pl_info "Dig query options: ${DIG_QOPTS[*]:-"(none)"}"
[[ "${MONITOR_IPV4}" == "true" ]] && pl_info "DNS servers IPv4: ${DNS_IPV4_PRIMARY}, ${DNS_IPV4_SECONDARY}"
[[ "${MONITOR_IPV6}" == "true" ]] && pl_info "DNS servers IPv6: ${DNS_IPV6_PRIMARY}, ${DNS_IPV6_SECONDARY}"
pl_info "DNS query host/type: ${DNS_QUERY_HOST}, ${DNS_QUERY_TYPE}"

# Monitoring loop (before entering: initialize state, replace temporary signal
# handler and run user-defined command for event 'start'; signal INT/TERM/HUP:
# exit gracefully by ending loop; signal USR1/USR2: cycle loop + reset state)
status_ipv4="unknown"; stime_ipv4=${SECONDS}
status_ipv6="unknown"; stime_ipv6=${SECONDS}
addr_ipv4="unknown"; atime_ipv4=${SECONDS}
addr_ipv6="unknown"; atime_ipv6=${SECONDS}
keep_looping="true"; reset_state="false"; reset_time=${SECONDS}
trap "pl_exit \"Received signal INT/TERM/HUP, exiting\"; keep_looping=\"false\"" INT TERM HUP
trap "pl_reset \"Received signal USR1/USR2, resetting state\"; reset_state=\"true\"" USR1 USR2
run_usrcmd "start" 0 "" 0 0 "${USRCMD_APP_START[@]}" || :
while ${keep_looping}; do

	# IPv4 Monitoring
	if [[ "${MONITOR_IPV4}" == "true" ]]; then

		# Ping host(s) to determine connection status
		result1=0; result2=0
		ping_host -4 "${HOST_IPV4_PRIMARY}" "${PING_OPTS[@]}" || { result1=$?; ping_host -4 "${HOST_IPV4_SECONDARY}" "${PING_OPTS[@]}" || result2=$?; }
		if (( ${result1} == 0 || ${result2} == 0 )); then
			if [[ "${status_ipv4}" != "online" ]]; then
				elap_secs=$((SECONDS - stime_ipv4)); secs_to_hms ${elap_secs} elap_hms
				status_ipv4="online"; stime_ipv4=${SECONDS}
				pl_online4 "Connection status IPv4: ONLINE (elapsed: ${elap_hms}, results: ${result1},${result2})"
				run_usrcmd "online4" ${elap_secs} "" ${result1} ${result2} "${USRCMD_ONLINE_IPV4[@]}" || :
			fi
		else
			if [[ "${status_ipv4}" != "offline" ]]; then
				elap_secs=$((SECONDS - stime_ipv4)); secs_to_hms ${elap_secs} elap_hms
				status_ipv4="offline"; stime_ipv4=${SECONDS}
				#addr_ipv4="unknown"; atime_ipv4=${SECONDS} # do NOT reset IP address (might be unchanged when back online)
				pl_offline4 "Connection status IPv4: OFFLINE (elapsed: ${elap_hms}, results: ${result1},${result2})"
				run_usrcmd "offline4" ${elap_secs} "" ${result1} ${result2} "${USRCMD_OFFLINE_IPV4[@]}" || :
			fi
		fi

		# Query DNS server(s) to determine public IP address
		if [[ "${status_ipv4}" == "online" ]]; then
			result1=0; result2=0
			lookup_ipaddr -4 new_addr "${DNS_IPV4_PRIMARY}" "${DNS_QUERY_HOST}" "${DNS_QUERY_TYPE}" DIG_OPTS DIG_QOPTS || { result1=$?; lookup_ipaddr -4 new_addr "${DNS_IPV4_SECONDARY}" "${DNS_QUERY_HOST}" "${DNS_QUERY_TYPE}" DIG_OPTS DIG_QOPTS || result2=$?; }
			if (( ${result1} == 0 || ${result2} == 0 )); then
				if [[ "${new_addr}" != "${addr_ipv4}" ]]; then
					elap_secs=$((SECONDS - atime_ipv4)); secs_to_hms ${elap_secs} elap_hms
					addr_ipv4="${new_addr}"; atime_ipv4=${SECONDS}
					pl_ipaddr4 "Public IP address IPv4: ${addr_ipv4} (elapsed: ${elap_hms}, results: ${result1},${result2})"
					run_usrcmd "ipaddr4" ${elap_secs} "${addr_ipv4}" ${result1} ${result2} "${USRCMD_IPADDR_IPV4[@]}" || :
				fi
			else
				elap_secs=$((SECONDS - atime_ipv4)); secs_to_hms ${elap_secs} elap_hms
				addr_ipv4="unknown"; atime_ipv4=${SECONDS}
				pl_error "Public IP address IPv4: DNS lookup failed (elapsed: ${elap_hms}, results: ${result1},${result2})"
				run_usrcmd "ipaddr4" ${elap_secs} "${addr_ipv4}" ${result1} ${result2} "${USRCMD_IPADDR_IPV4[@]}" || :
			fi
		fi

	fi

	# IPv6 Monitoring
	if [[ "${MONITOR_IPV6}" == "true" ]]; then

		# Ping host(s) to determine connection status
		result1=0; result2=0
		ping_host -6 "${HOST_IPV6_PRIMARY}" "${PING_OPTS[@]}" || { result1=$?; ping_host -6 "${HOST_IPV6_SECONDARY}" "${PING_OPTS[@]}" || result2=$?; }
		if (( ${result1} == 0 || ${result2} == 0 )); then
			if [[ "${status_ipv6}" != "online" ]]; then
				elap_secs=$((SECONDS - stime_ipv6)); secs_to_hms ${elap_secs} elap_hms
				status_ipv6="online"; stime_ipv6=${SECONDS}
				pl_online6 "Connection status IPv6: ONLINE (elapsed: ${elap_hms}, results: ${result1},${result2})"
				run_usrcmd "online6" ${elap_secs} "" ${result1} ${result2} "${USRCMD_ONLINE_IPV6[@]}" || :
			fi
		else
			if [[ "${status_ipv6}" != "offline" ]]; then
				elap_secs=$((SECONDS - stime_ipv6)); secs_to_hms ${elap_secs} elap_hms
				status_ipv6="offline"; stime_ipv6=${SECONDS}
				#addr_ipv6="unknown"; atime_ipv6=${SECONDS} # do NOT reset IP address (might be unchanged when back online)
				pl_offline6 "Connection status IPv6: OFFLINE (elapsed: ${elap_hms}, results: ${result1},${result2})"
				run_usrcmd "offline6" ${elap_secs} "" ${result1} ${result2} "${USRCMD_OFFLINE_IPV6[@]}" || :
			fi
		fi

		# Query DNS server(s) to determine public IP address
		if [[ "${status_ipv6}" == "online" ]]; then
			result1=0; result2=0
			lookup_ipaddr -6 new_addr "${DNS_IPV6_PRIMARY}" "${DNS_QUERY_HOST}" "${DNS_QUERY_TYPE}" DIG_OPTS DIG_QOPTS || { result1=$?; lookup_ipaddr -6 new_addr "${DNS_IPV6_SECONDARY}" "${DNS_QUERY_HOST}" "${DNS_QUERY_TYPE}" DIG_OPTS DIG_QOPTS || result2=$?; }
			if (( ${result1} == 0 || ${result2} == 0 )); then
				if [[ "${new_addr}" != "${addr_ipv6}" ]]; then
					elap_secs=$((SECONDS - atime_ipv6)); secs_to_hms ${elap_secs} elap_hms
					addr_ipv6="${new_addr}"; atime_ipv6=${SECONDS}
					pl_ipaddr6 "Public IP address IPv6: ${addr_ipv6} (elapsed: ${elap_hms}, results: ${result1},${result2})"
					run_usrcmd "ipaddr6" ${elap_secs} "${addr_ipv6}" ${result1} ${result2} "${USRCMD_IPADDR_IPV6[@]}" || :
				fi
			else
				elap_secs=$((SECONDS - atime_ipv6)); secs_to_hms ${elap_secs} elap_hms
				addr_ipv6="unknown"; atime_ipv6=${SECONDS}
				pl_error "Public IP address IPv6: DNS lookup failed (elapsed: ${elap_hms}, results: ${result1},${result2})"
				run_usrcmd "ipaddr6" ${elap_secs} "${addr_ipv6}" ${result1} ${result2} "${USRCMD_IPADDR_IPV6[@]}" || :
			fi
		fi

	fi

	# Wait for next iteration, check for clock skew (e.g. due to system having
	# been suspended + resumed during sleep interval), reset state if necessary
	time_before=${SECONDS}
	int_sleep ${MONITOR_INTERVAL} || : # signals are already handled via traps
	time_after=${SECONDS}
	if (( ${time_after} - ${time_before} >= ${MONITOR_INTERVAL} + 60 )); then # '+ 60' to allow for some breathing room
		pl_reset "Clock skew detected ($((${time_after} - ${time_before}))s elapsed during sleep), resetting state"
		reset_state="true"
	fi

	# Reset state if requested (can happen due to clock skew or due to receiving
	# signal USR1/USR2; note that printing using 'pl_reset()' is done elsewhere)
	if ${reset_state}; then
		status_ipv4="unknown"; stime_ipv4=${SECONDS}
		status_ipv6="unknown"; stime_ipv6=${SECONDS}
		addr_ipv4="unknown"; atime_ipv4=${SECONDS}
		addr_ipv6="unknown"; atime_ipv6=${SECONDS}
		elap_secs=$((SECONDS - reset_time))
		reset_time=${SECONDS}; reset_state="false"
		run_usrcmd "reset" ${elap_secs} "" 0 0 "${USRCMD_STATE_RESET[@]}" || :
	fi

done

# Run user-defined command for event 'stop' (elapsed time since 'start' event
# is script runtime in seconds, i.e. ${SECONDS})
run_usrcmd "stop" ${SECONDS} "" 0 0 "${USRCMD_APP_STOP[@]}" || :

# Return home safely
exit 0
