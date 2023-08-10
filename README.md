# Internet Connection Monitor (intconmon)
Monitors and logs Internet connection status and public IP address changes (IPv4/IPv6). Suitable to run as a [system service](#set-up-as-system-service) on always-on devices (e.g. NAS, Raspberry Pi).

## Donations
I'm striving to become a full-time developer of [Free and open-source software (FOSS)](https://en.wikipedia.org/wiki/Free_and_open-source_software). Donations help me achieve that goal and are highly appreciated.

<a href="https://www.buymeacoffee.com/fonic"><img src="https://raw.githubusercontent.com/fonic/donate-buttons/main/buymeacoffee-button.png" alt="Buy Me A Coffee" height="35"></a>&nbsp;&nbsp;&nbsp;<a href="https://paypal.me/fonicmaxxim"><img src="https://raw.githubusercontent.com/fonic/donate-buttons/main/paypal-button.png" alt="Donate via PayPal" height="35"></a>

## Requirements
**Operating System:**<br/>
_Linux_, _FreeBSD_, _Windows (WSL)_

**Dependencies:**<br/>
_Bash (>=v4.0)_, _ping_, _dig_

## Download & Installation
Refer to the [releases](https://github.com/fonic/intconmon/releases) section for downloads links. There is no installation required. Simply extract the downloaded archive to a folder of your choice. Optionally, _intconmon_ may be set up as a [system service](#set-up-as-system-service).

## Configuration
Open `intconmon.conf` in your favorite text editor and adjust the settings to your liking. Refer to embedded comments for details. Note that before changing any settings, it is recommended to run the script with *default settings* first to make sure it works as expected. Refer to [this section](#configuration-options--defaults) for a listing of all configuration options and current defaults.

## Usage
There are no command line options. Simply run the script from within a console:
```
$ cd intconmon-vX.Y
$ ./intconmon.sh
```

Alternatively, set up _intconmon_ to run as a [system service](#set-up-as-system-service) (recommended for long-term use).

## Set up as system service

To set up _intconmon_ as an isolated system service, run the following commands in a console (Linux with systemd only):

```
$ sudo bash
# useradd -d /var/lib/intconmon -s /sbin/nologin -c "User for Internet Connection Monitor" intconmon
# mkdir /var/lib/intconmon
# chown intconmon:intconmon /var/lib/intconmon
# chmod 700 /var/lib/intconmon
# cd intconmon-vX.Y
# cp intconmon.sh intconmon.conf README.md /var/lib/intconmon
# chown intconmon:intconmon /var/lib/intconmon/*
# cp intconmon.service /etc/systemd/system
# sed -i -e 's|%{USER}|intconmon|g' -e 's|%{GROUP}|intconmon|g' -e 's|%{HOME}|/var/lib/intconmon|g' /etc/systemd/system/intconmon.service
# systemctl daemon-reload
# systemctl enable intconmon.service
# systemctl start intconmon.service
# exit
```

**NOTE:**<br/>
This creates user/group `intconmon` with home directory `/var/lib/intconmon`.

<br/>To fully clean up an existing system service setup, run the following commands:

```
$ sudo bash
# systemctl stop intconmon.service
# systemctl disable intconmon.service
# rm /etc/systemd/system/intconmon.service
# systemctl daemon-reload
# userdel -r intconmon
# exit
```

**NOTE:**<br/>
You might want to back up log file `intconmon.log` first to preserve its contents.

## Output & Logging

Output is sent to both console and log file `intconmon.log`:

![Screenshot](https://raw.githubusercontent.com/fonic/intconmon/main/SCREENSHOT.png)

## Configuration Options & Defaults

Configuration options and current defaults:
```sh
# intconmon.conf

# ------------------------------------------------------------------------------
#                                                                              -
#  Internet Connection Monitor (intconmon)                                     -
#                                                                              -
#  Created by Fonic <https://github.com/fonic>                                 -
#  Date: 10/17/22 - 08/09/23                                                   -
#                                                                              -
# ------------------------------------------------------------------------------

# --------------------------------------
#  General Settings                    -
# --------------------------------------

# Switches to enable/disable monitoring for IPv4/IPv6 ('true'/'false')
MONITOR_IPV4="true"
MONITOR_IPV6="true"

# Monitoring interval in seconds (i.e. delay/duration in between two connection
# status / public IP address checks; minimum: 1, recommended: 60)
# CAUTION: refrain from hammering public servers by setting this too low!
MONITOR_INTERVAL="60"


# --------------------------------------
#  Connection Status Monitoring        -
# --------------------------------------

# Hosts to ping to determine connection status. It is recommended to use well-
# known hosts with as little downtime as possible for this (e.g. public DNS
# servers). Although it is possible to specify hostnames here, it is HIGHLY
# recommended to use IP addresses instead so DNS lookups do not factor in when
# performing connection status checks

# Google DNS servers
#HOST_IPV4_PRIMARY="8.8.8.8"
#HOST_IPV4_SECONDARY="8.8.4.4"
#HOST_IPV6_PRIMARY="2001:4860:4860::8888"
#HOST_IPV6_SECONDARY="2001:4860:4860::8844"

# Cloudflare DNS servers
#HOST_IPV4_PRIMARY="1.1.1.1"
#HOST_IPV4_SECONDARY="1.0.0.1"
#HOST_IPV6_PRIMARY="2606:4700:4700::1111"
#HOST_IPV6_SECONDARY="2606:4700:4700::1001"

# Mix of Google and Cloudflare primary DNS servers
# NOTE: best approach to rule out issues with one single provider
HOST_IPV4_PRIMARY="8.8.8.8"
HOST_IPV4_SECONDARY="1.1.1.1"
HOST_IPV6_PRIMARY="2001:4860:4860::8888"
HOST_IPV6_SECONDARY="2606:4700:4700::1111"

# Path to 'ping' command used to determine connection status
# NOTE: set to just 'ping' to locate executable via PATH
PING_EXEC="ping"

# Options passed to 'ping' command (Linux only):
# Send one ping, time out and exit after 3s
# CAUTION: only change these options if you know what you are doing!
#          do NOT add options '-4'/'-6' as those will be added automatically!
PING_OPTS_LINUX=("-c" "1" "-w" "3")

# Options passed to 'ping' command (FreeBSD only):
# Send one ping, time out and exit after 3s
# CAUTION: only change these options if you know what you are doing!
#          do NOT add options '-4'/'-6' as those will be added automatically!
PING_OPTS_FREEBSD=("-c" "1" "-t" "3")


# --------------------------------------
#  Public IP Address Lookup            -
# --------------------------------------

# DNS servers to query to determine public IP address, special hostname to
# query and query type to use. Although it is possible to specify hostnames
# here, it is HIGHLY recommended to use IP addresses instead so DNS lookups of
# the server being queried do not factor in when performing public IP address
# lookups

# Google (servers 'ns*.google.com' are different from '8.8.8.8'/'8.8.4.4',
# public IP lookup will NOT work as expected with the latter; responses are
# double-quoted, e.g. '"1.2.3.4"')
#DNS_IPV4_PRIMARY="ns1.google.com"
#DNS_IPV4_SECONDARY="ns2.google.com"
#DNS_IPV6_PRIMARY="ns1.google.com"
#DNS_IPV6_SECONDARY="ns2.google.com"
#DNS_QUERY_HOST="o-o.myaddr.l.google.com"
#DNS_QUERY_TYPE="TXT"

# OpenDNS (preferable choice, official DNS provider, no known issues/hazards)
DNS_IPV4_PRIMARY="208.67.222.222"
DNS_IPV4_SECONDARY="208.67.220.220"
DNS_IPV6_PRIMARY="2620:119:35::35"
DNS_IPV6_SECONDARY="2620:119:53::53"
DNS_QUERY_HOST="myip.opendns.com"
DNS_QUERY_TYPE="ANY"

# Path to 'dig' command used to determine public IP address via DNS lookup
# NOTE: set to just 'dig' to locate executable via PATH
DIG_EXEC="dig"

# Options passed to 'dig' command:
# (none)
# CAUTION: only change these options if you know what you are doing!
#          do NOT add options '-4'/'-6' as those will be added automatically!
DIG_OPTS=()

# Query options passed to 'dig' command:
# Try to query DNS server only once, time out after 3s
# CAUTION: only change these options if you know what you are doing!
#          do NOT remove option '+short' (for non-verbose output)!
DIG_QOPTS=("+tries=1" "+timeout=3" "+short")


# --------------------------------------
#  User-Defined Commands               -
# --------------------------------------

# User-defined commands to run for events 'start', 'stop', 'reset', 'online4',
# 'offline4', 'ipaddr4', 'online6', 'offline6' and 'ipaddr6'
#
# Syntax: USRCMD_EVENT_IPVER=("<path-to-executable>" "<arg-1>" "<arg-2>" ...)
#
# Tokens: %{ETYPE} -> replaced with type of event (2nd part of log file lines
#                     converted to lowercase, e.g. '[ONLINE4 ]' -> 'online4')
#         %{ETIME} -> replaced with time event occurred (seconds since epoch)
#         %{ELAPS} -> replaced with time elapsed since last occurrence of the
#                     same or opposite event (in seconds)
#         %{HOST}  -> replaced with hostname of machine running 'intconmon.sh'
#                     (i.e. THIS machine)
#         %{PUBIP} -> replaced with current public IP address or 'unknown' if
#                     last lookup of public IP address failed (only valid for
#                     events of type 'ipaddr4' and 'ipaddr6')
#         %{RESPR} -> result of primary/secondary ping/query (return value of
#         %{RESSE}    'ping' command for events of type 'online4', 'offline4',
#                     'online6' and 'offline6'; return value of 'dig' command
#                     for events of type 'ipaddr4' and 'ipaddr6'; invalid for
#                     other event types)
#
# Examples:
#
# Desktop notifications:
# USRCMD_ONLINE_IPV4=("notify-send" "--urgency=normal" "--app-name=Internet Connection Monitor" "IPv4 Connection" "IPv4 connection is <b>ONLINE</b>")
# USRCMD_OFFLINE_IPV4=("notify-send" "--urgency=critical" "--app-name=Internet Connection Monitor" "IPv4 Connection" "IPv4 connection is <b>OFFLINE</b>")
# USRCMD_IPADDR_IPV4=("notify-send" "--urgency=normal" "--app-name=Internet Connection Monitor" "IPv4 Address" "IPv4 public IP address is <b>%{PUBIP}</b>")
# USRCMD_ONLINE_IPV6=("notify-send" "--urgency=normal" "--app-name=Internet Connection Monitor" "IPv6 Connection" "IPv6 connection is <b>ONLINE</b>")
# USRCMD_OFFLINE_IPV6=("notify-send" "--urgency=critical" "--app-name=Internet Connection Monitor" "IPv6 Connection" "IPv6 connection is <b>OFFLINE</b>")
# USRCMD_IPADDR_IPV6=("notify-send" "--urgency=normal" "--app-name=Internet Connection Monitor" "IPv6 Address" "IPv6 public IP address is <b>%{PUBIP}</b>")
#
# Email notifications:
# USRCMD_ONLINE_IPV4=("${SCRIPT_DIR}/sendemail.sh" "email@address.tld" "Host %{HOST} IPv4 Connection" "IPv4 connection of host %{HOST} is ONLINE (@%{ETIME})")
# USRCMD_OFFLINE_IPV4=("${SCRIPT_DIR}/sendemail.sh" "email@address.tld" "Host %{HOST} IPv4 Connection" "IPv4 connection of host %{HOST} is OFFLINE (@%{ETIME})")
# USRCMD_IPADDR_IPV4=("${SCRIPT_DIR}/sendemail.sh" "email@address.tld" "Host %{HOST} IPv4 Address" "IPv4 public IP address of host %{HOST} is %{PUBIP} (@%{ETIME})")
# USRCMD_ONLINE_IPV6=("${SCRIPT_DIR}/sendemail.sh" "email@address.tld" "Host %{HOST} IPv6 Connection" "IPv6 connection of host %{HOST} is ONLINE (@%{ETIME})")
# USRCMD_OFFLINE_IPV6=("${SCRIPT_DIR}/sendemail.sh" "email@address.tld" "Host %{HOST} IPv6 Connection" "IPv6 connection of host %{HOST} is OFFLINE (@%{ETIME})")
# USRCMD_IPADDR_IPV6=("${SCRIPT_DIR}/sendemail.sh" "email@address.tld" "Host %{HOST} IPv6 Address" "IPv6 public IP address of host %{HOST} is %{PUBIP} (@%{ETIME})")
#
# Custom event handler:
# USRCMD_ALL_EVENTS=("/path/to/myscript.sh" "%{ETYPE}" "%{ETIME}" "%{ELAPS}" "%{HOST}" "%{PUBIP}" "%{RESPR}" "%{RESSE}")
#
# CAUTION: make sure commands specified here return in a timely fashion!
USRCMD_APP_START=()
USRCMD_APP_STOP=()
USRCMD_STATE_RESET=()
USRCMD_ONLINE_IPV4=()
USRCMD_OFFLINE_IPV4=()
USRCMD_IPADDR_IPV4=()
USRCMD_ONLINE_IPV6=()
USRCMD_OFFLINE_IPV6=()
USRCMD_IPADDR_IPV6=()
# NOTE: if set, this overrides all other user-defined commands above
#USRCMD_ALL_EVENTS=()


# --------------------------------------
#  Debugging Settings                  -
# --------------------------------------

# Switches to enable debug output for 'ping' command calls, 'dig' command calls
# and user-defined command calls ('true'/'false')
DEBUG_PING="false"
DEBUG_DIG="false"
DEBUG_USRCMD="false"
```

##

_Last updated: 08/10/23_
