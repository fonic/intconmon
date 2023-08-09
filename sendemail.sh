#!/usr/bin/env bash

# -------------------------------------------------------------------------
#                                                                         -
#  Internet Connection Monitor (intconmon)                                -
#  Helper script to send emails (to be used as user-defined command)      -
#                                                                         -
#  Created by Fonic <https://github.com/fonic>                            -
#  Date: 10/17/22 - 08/09/23                                              -
#                                                                         -
# -------------------------------------------------------------------------

# Process command line
if (( $# != 3 )); then
	echo -e "\e[1mUsage:\e[0m   ${0##*/} ADDRESS SUBJECT MESSAGE"
	echo -e "\e[1mExample:\e[0m ${0##*/} \"email@address.com\" \"Test message\" \"This is a test message.\""
	echo -e "\e[1mNote:\e[0m    Email is sent using the system's 'mail' command (which requires an MTA)"
	exit 2
fi
address="$1"; subject="$2"; message="$3"

# Send email via 'mail'
#mail -s "${subject}" "${address}" <<< "${message}"
echo -e "${message}" | mail -s "${subject}" "${address}"
exit $?
