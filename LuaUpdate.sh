#!/bin/sh

# -----------------------------------------------------------------------------------------------
# Variable declatarions / initializations
# -----------------------------------------------------------------------------------------------
TmpPath="/tmp"
LogPath="/var/log"
LogFileName="LuaUpdate.log"
Email="tcvf1@protonmail.com"
Token="e46dad5ec97aa1b29f125916d9375688"
Domain="homenetwork.hu"

# -----------------------------------------------------------------------------------------------
# Function declatarions
# -----------------------------------------------------------------------------------------------

# Gets specific record of the domain
GetDNSIds()
{
	if [ "$1" == "ZoneID" ]; then
		local retVal=$( curl -s -u $Email:$Token -H 'Accept: application/json' https://api.luadns.com/v1/zones/ | jq ".[] | select(.name == \"$Domain\") | .id" )
	elif [ "$1" == "ARecordID" ]; then
		local retVal=$( curl -s -u $Email:$Token -H 'Accept: application/json' https://api.luadns.com/v1/zones/$ZoneID | jq ".records[] | select(.type == \"A\") | .id" )
	fi

	echo $retVal
}

# Gets current IP and the A record IP stored at DNS
GetIPs()
{
	if [ "$1" == "WANIP" ]; then
		local retVal=$(curl -s ifconfig.me/ip)
	elif [ "$1" == "DNSIP" ]; then
		local retVal=$( curl -s -u $Email:$Token -H 'Accept: application/json' https://api.luadns.com/v1/zones/$ZoneID/records/$ARecordID | jq '.content' -r )
	fi

	echo $retVal
}

# Checks the IP validity
ValidateIP()
{
	local ipIsValid=""

	# 10.x.x.x
	if echo "$WANIP" | grep -Eq '^10\.((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){3}$'; then
		ipIsValid="false"

	# 172.16.x.x -> 172.31.x.x
	elif echo "$WANIP" | grep -Eq '^172\.(1[6-9]|2[0-9]]|3[0-2])\.(((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$))){2}$'; then
		ipIsValid="false"

	# 192.168.x.x
	elif echo "$WANIP" | grep -Eq '^192\.168\.(((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$))){2}$'; then
		ipIsValid="false"

	# localhost
	elif echo "$WANIP" | grep -Eq '^127\.(((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$))){3}$'; then
		ipIsValid="false"

	# public IP addresses
	elif echo "$WANIP" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$'; then
		ipIsValid="true"

	fi

	echo $ipIsValid
}

# Checks that the external IP address has changed or not?
CheckIPChange()
{
	local IPChanged="false"

	if [ "$WANIP" != "$DNSIP" ]; then
		IPChanged="true"
	fi

	echo $IPChanged
}

# Updates the domains LuaDNS A record.
UpdateARecord() {
	local json="{\"id\":$ARecordID,\"name\":\"$Domain.\",\"type\":\"A\",\"content\":\"$WANIP\",\"ttl\":300,\"zone_id\":$ZoneID}"
	local UpdateSuccessfull="false"

	local ReturnedID=$(curl -s -u $Email:$Token -H 'Accept: application/json' -X PUT -d $json https://api.luadns.com/v1/zones/$ZoneID/records/$ARecordID | jq '.id' )

	# Successfull update
	if [ "$ReturnedID" == "$ARecordID" ]; then
		WriteToLog IPUpdateSuccess
		UpdateSuccessfull="true";
	# Update failed
	else
		WriteToLog IPUpdateFailed
	fi
}

# Write event to log file.
WriteToLog() {
	local DateTime=$(date +"%F %T")

	if [ -f $LogPath/$LogFileName ]; then
		echo "${DateTime}: $1" > $LogPath/$LogFileName
	else
		echo "${DateTime}: $1" >> $LogPath/$LogFileName
	fi
}

CheckInternetConnection() {
	curl -s https://8.8.8.8 > /dev/null
	echo $?
}

# -----------------------------------------------------------------------------------------------
# End function declatarions
# -----------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------------------------

ZoneID=$(GetDNSIds ZoneID)
ARecordID=$(GetDNSIds ARecordID)
WANIP=$(GetIPs WANIP)
DNSIP=$(GetIPs DNSIP)

if [ "$DNSIP" == "" ]; then
	WriteToLog NoDNSIP

elif [ "$WANIP" == "" ]; then
	WriteToLog WANIP

elif [ $( ValidateIP ) != "true" ]; then
	WriteToLog IPIsNotValid

elif [ "$WANIP" != "$DNSIP" ]; then
	UpdateARecord

#else
#	WriteToLog NoIPChange

fi
# -----------------------------------------------------------------------------------------------
# End of main
# -----------------------------------------------------------------------------------------------
