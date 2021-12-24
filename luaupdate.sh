#!/bin/sh

# ===============================================================================
# Title           : luaupdate.sh
# Description     : This script will make a header for a bash script.
# Author		      : Tamas Csore
# Date            : 2021-12-12
# Version         : 1.0    
# Usage           : Run from Cron without parameters
# Notes           : Install jq and curl to use this script.
# ===============================================================================


# -------------------------------------------------------------------------------
# Variable declatarions / initializations
# -------------------------------------------------------------------------------

LOGPATH="/var/log"
LOGFILENAME="luaupdate.log"
EMAIL="tcvf1@protonmail.com"
TOKEN="e46dad5ec97aa1b29f125916d9375688"
DOMAIN="homenetwork.hu"
WANINTERFACE="pppoe1"

# -------------------------------------------------------------------------------
# End of variable declatarions / initializations
# -------------------------------------------------------------------------------



# -------------------------------------------------------------------------------
# Function declatarions
# -------------------------------------------------------------------------------

# Gets the IP address of the specified (WAN) network adapter
GetWanIp() {
  echo "$(ifconfig $1 | grep 'inet ' | awk '{print $2}')"
}

# Retrieves all zones data associated with the specified account
GetZones() {
  local EMAIL="$1"
  local TOKEN="$2"

  echo "$(curl -s -u $EMAIL:$TOKEN -H 'Accept: application/json' https://api.luadns.com/v1/zones)"
}

# Extracts the specified domain's ZoneID from LuaDNS response
GetZoneId() {
  local ZONEIDS="$1"
  local DOMAIN="$2"
 
  echo "$(echo "$ZONEIDS" | jq ".[] | select(.name == \"$DOMAIN\") | .id")"
}

# Gets records of the specified ZoneID 
GetZoneRecords() {
  local ZONERECORDS="$1"

  echo "$(curl -s -u $EMAIL:$TOKEN -H 'Accept: application/json' https://api.luadns.com/v1/zones/$ZONEID)"
}

# Gets the DNS IP address from zone records
GetDnsIp() {
  local ZONERECORDS="$1"

  echo "$(echo "$ZONERECORDS" | jq '.records[] | select(.type == "A").content' -r)"
}

GetARecordId() {
  local ZONERECORDS="$1"

  echo "$(echo "$ZONERECORDS" | jq '.records[] | select(.type == "A").id' -r)"
}

# Sends update request for the specified domain's A record to LuaDNS
UpdateARecord() {
  local EMAIL="$1"
  local TOKEN="$2"
  local DOMAIN="$3"
  local ZONEID="$4"
  local ARECORDID="$5"
  local WANIP="$6"
  local JSON="{\"id\":$ARECORDID,\"name\":\"$DOMAIN.\",\"type\":\"A\",\"content\":\"$WANIP\",\"ttl\":300,\"zone_id\":$ZONEID}"

	echo "$(curl -s -u $EMAIL:$TOKEN -H 'Accept: application/json' -X PUT -d $JSON https://api.luadns.com/v1/zones/$ZONEID/records/$ARecordID)"
}

# Writes messages to log file with timestamp and log level 
WriteToLog() {
  local DATETIME="$(date +"%F %T")"

  local LOGTEXT="$1"
	local LOGLEVEL="["$2"]"

  # If the log level parameter is not specified, sets it to [INFO]
  if [ -z $2 ]; then
    local LOGLEVEL="[INFO]"
  fi

  if [ -f $LOGPATH/$LOGFILENAME ]; then
    echo "${DATETIME} ${LOGLEVEL}: ${LOGTEXT}" >> $LOGPATH/$LOGFILENAME
  else
    echo "${DATETIME} ${LOGLEVEL}: ${LOGTEXT}" > $LOGPATH/$LOGFILENAME
  fi
}

# Validates JSON formatted response sent by LuaDNS
ValidateJson() {
  local JSON="$1"

  if [ $(echo "$JSON" | jq empty > /dev/null 2>&1; echo $?) = 0 ]; then
    return 0
  else
    return 1
  fi
}

# Extracts the error message from LuaDNS response if exists
GetStatusMessage() {
  local JSON="$1"

  if  echo "$JSON" | grep -Eq '.*\"message\"\:.*' ; then
    local MESSAGE="$(echo "${JSON}" | jq '.message' -r)"
  else
    local MESSAGE="OK"
  fi

  echo $MESSAGE 2>&1
}

# Checks the IP validity
ValidateIP()
{
	local IP="$1"

  # 10.xxx.xxx.xxx, 127.xxx.xxx.xxx, 172.16.xxx.xxx -> 172.31.xxx.xxx, 192.168.xxx.xxx, empty string
  if echo "$IP" | grep -Eq '^(10\.|127\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168|10\.|^$)'; then
    return 1
  fi

	# All the rest IP addresses
	return 0
}

# -------------------------------------------------------------------------------
# End of function declatarions
# -------------------------------------------------------------------------------


# -------------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------------



### Getting the WAN interface IP

WANIP="$(GetWanIp $WANINTERFACE)"
if ! ValidateIP "$WANIP"; then
	WriteToLog "WAN adapter (${WANINTERFACE}) IP address (${WANIP}) is not valid. Execution stopped." "WARNING"
  exit $?
fi



### Getting the account's zones

# Getting zones
ZONES="$(GetZones "$EMAIL" "$TOKEN")"
if ! ValidateJson "$ZONES" ; then
  WriteToLog "Failed to get account's Zones for an unknown reason. Execution stopped." "ERROR"
  exit $?
fi
# Validate response from LuaDNS
MESSAGE="$(GetStatusMessage "$ZONES")"
if [ "$MESSAGE" != "OK" ]; then
  WriteToLog "Failed to get account's Zones. Response from LuaDNS: ${MESSAGE}. Execution stopped." "ERROR"
  exit $?
fi
# Getting ZoneID of specified domain
ZONEID="$(GetZoneId $ZONES $DOMAIN)"



### Getting the specified zone's IP address

# Getting zone records
ZONERECORDS="$(GetZoneRecords "$EMAIL" "$TOKEN" "$ZONEID")"
if ! ValidateJson "$ZONERECORDS" ; then
  WriteToLog "Failed to get zone (${DOMAIN}) records for an unknown reason. Execution stopped." "ERROR"
  exit $?
fi

# Validate response from LuaDNS
MESSAGE="$(GetStatusMessage "$ZONERECORDS")"
if [ "$MESSAGE" != "OK" ]; then
  WriteToLog "Failed to get zone (${DOMAIN}) records. Response from LuaDNS: ${MESSAGE}. Execution stopped." "ERROR"
  exit $?
fi

# Extract A record value of zone (DNS IP) from zone records 
DNSIP="$(GetDnsIp "$ZONERECORDS")"

# Validate DNS IP
if ! ValidateIP "$DNSIP"; then
	WriteToLog "LuaDNS A record IP address (${DNSIP}) is not valid. Execution stopped." "WARNING"
  exit $?
fi



### Compare the WAN and DNS IP and update the DNS IP address if necessary

if [ "$WANIP" != "$DNSIP" ]; then

	# Getting specified zone A record ID
  ARECORDID="$(GetARecordId "$ZONERECORDS")"
  
	# Send update request and save LuaDNS response
  UPDATERRESPONSE="$(UpdateARecord "$EMAIL" "$TOKEN" "$DOMAIN" "$ZONEID" "$ARECORDID" "$WANIP")"
  if ! ValidateJson "$UPDATERRESPONSE" ; then
		WriteToLog "Failed to update ${DOMAIN} A record value for an unknown reason. Execution stopped." "ERROR"
  exit $?
  fi

  # Validate update response from LuaDNS
  MESSAGE="$(GetStatusMessage "$UPDATERRESPONSE")"
  if [ "$MESSAGE" != "OK" ]; then
    WriteToLog "Failed to update ${DOMAIN} A record value. Response from LuaDNS: ${MESSAGE}. Execution stopped." "ERROR"
    exit $?
  fi

  WriteToLog "DNS A record for ${DOMAIN} successfully updated! DNS A record value has been changed from ${DNSIP} to ${WANIP}." "INFO"
fi

# -------------------------------------------------------------------------------
# End of main
# -------------------------------------------------------------------------------