#!/bin/sh

# Variable declatarions / initializations
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
	local ipIsValid="true"

	# 10.x.x.x
	if echo "$WANIP" | grep -Eq '^10(\.\d{1,3}){3}$'; then
		ipIsValid="false"

	# 172.16.x.x -> 172.31.x.x
	elif echo "$WANIP" | grep -Eq '^172\.(16|17|18|19|21|22|23|24|25|26|27|28|29|30|31|32)(\.\d{1-3}){2}$'; then
		ipIsValid="false"

	# 192.168.x.x
	elif echo "$WANIP" | grep -Eq '^192\.168(\.\d{1,3}){2}$'; then
		ipIsValid="false"

	# localhost
	elif echo "$WANIP" | grep -Eq '127(\.\d{1,3}){3}$'; then
		ipIsValid="false"

	# empty DNS IP
	elif [ -z "$DNSIP" ]; then
		ipIsValid="false"
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
	local tryCount=0

	# Try update A record for 10 times.
	while [ "$UpdateSuccessfull" != "true" ] && [ $tryCount -lt 10 ]
	do
		local ReturnedID=$(curl -s -u $Email:$Token -H 'Accept: application/json' -X PUT -d $json https://api.luadns.com/v1/zones/$ZoneID/records/$ARecordID | jq '.id' )

		# Successfull update
		if [ "$ReturnedID" == "$ARecordID" ]; then
			WriteToLog IPUpdateSuccess
			UpdateSuccessfull="true";
		# Update failed -> wait 5 secs
		else
			WriteToLog IPUpdateFailed
			tryCount=$((tryCount+1))
			sleep 5
		fi
	done
}

# Write event to log file.
WriteToLog() {
	local DateTime=$(date +"%F %T")
	
	if [ "$1" == "CheckIPChange" ]; then
		sed -i '' "1i\\
$DateTime - $Domain IP does not changed. No update needed.
" $LogPath/$LogFileName
		
	elif [ "$1" == "IPUpdateSuccess" ]; then
		sed -i '' "1i\\
$DateTime - Successfull A record update on $Domain. A record IP has changed from $DNSIP to $WANIP
" $LogPath/$LogFileName
	
	elif [ "$1" == "IPUpdateFailed" ]; then
		sed -i '' "1i\\
$DateTime - Failed A record update on $Domain. A record IP could not be changed from $DNSIP to $WANIP
" $LogPath/$LogFileName

	# IP validity failed
	elif [ "$1" == "IPIsNotValid" ]; then
		sed -i '' "1i\\
$DateTime - The current external IP ($WANIP) is not valid. DNS A record update skipped
" $LogPath/$LogFileName

	# log file exist, insert line to log file's first line
	elif [ "$1" == "Start" ]; then
		sed -i '' "1i\\
$DateTime - LuaUpdater started
" $LogPath/$LogFileName
	
	fi
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

if [ "$WANIP" != "$DNSIP" ]; then

	if [ $( ValidateIP ) == "true"]; then
		UpdateARecord
	else
		WriteToLog IPIsNotValid
	fi

fi
# -----------------------------------------------------------------------------------------------
# End of main
# -----------------------------------------------------------------------------------------------
