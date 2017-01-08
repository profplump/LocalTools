#!/bin/bash

HZ=250
FILE="${1}"
FORMAT="${2}"
if [ -z "${FORMAT}" ]; then
	FORMAT='+%Y-%m-%d %H:%M'
fi

CURRENT="`date '+%s'`"
JIFFIES="`cat /proc/timer_list | grep -E -m 1 '^jiffies' | cut -d " " -f2`"
declare -A PREFIX
for LINK in `ip link list | grep '^[0-9]*: ' | grep -v 'POINTOPOINT' | \
  cut -d ':' -f 2 | cut -d ' ' -f 2 | cut -d '@' -f 1`; do
	ADDR="`ip -6 addr list dev "${LINK}" | grep 'inet6 .* global' | awk '{print $2}'`"
	if [ -n "${ADDR}" ]; then
		SHORT="`echo "${ADDR}" | cut -d '/' -f 1 | sed 's%::[0-9]*$%%'`"
		LONG=""
		if [ -n "${SHORT}" ] && [ "${SHORT}" != "${ADDR}" ]; then
			for PART in `echo "${SHORT}" | sed 's%:%\n%g'`; do
				while [ ${#PART} -lt 4 ]; do
					PART="0${PART}"
				done
				if [ -n "${LONG}" ]; then
					LONG="${LONG}:"
				fi
				LONG="${LONG}${PART}"
			done
			PREFIX["${LONG}"]="${LINK}"
		fi
	fi
done

TEMP="`mktemp -t xt_recent.XXXXXXXX`"
cat "${FILE}" | while read LINE
do
	IP="`echo "${LINE}" | awk '{print $1}' | awk -F = {'print $2'}`"
	PACKET="`echo "${LINE}" | awk '{print $5}'`"
	echo "${IP}|${PACKET}" >> "${TEMP}"
done

OUTPUT="`mktemp -t xt_recent.XXXXXXXX`"
cat "${TEMP}" | while read LINE
do
	IP="`echo "${LINE}" | cut -d '|' -f 1`"
	PACKET="`echo "${LINE}" | cut -d '|' -f 2`"
	DIFF=$(( ( $JIFFIES - $PACKET ) / $HZ ))
	EPOCH=$(( $CURRENT - $DIFF ))
	DATE="`date -d "@${EPOCH}" "${FORMAT}"`"

	DNS="`dnsname "${IP}"`"
	if [ -z "${DNS}" ] && echo "${IP}" | grep -q ':'; then
		for i in "${!PREFIX[@]}"; do
			if echo "${IP}" | grep -q "^${i}"; then
				DNS="Interface: ${PREFIX[$i]}"
			fi
		done
	fi
	if [ -n "${DNS}" ]; then
		IP="${IP} (${DNS})"
	fi
	echo -e "${DATE}\t${IP}" >> "${OUTPUT}"
done
rm -f "${TEMP}"

cat "${OUTPUT}" | sort -r
rm -f "${OUTPUT}"
