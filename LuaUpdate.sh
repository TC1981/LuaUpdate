#!/bin/sh

# Logging variables
LogPath="/opt/var/log/"
LogFileName="LuaUpdate.log"

# -----------------------------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------------------------

# Checks the number of parameters passed and the --help parameter
# If no parameter passed or --help passed then show help.
Help()
{
	if [ \( "$#" -lt "3" \) -o \( "&#" == "1" -a "$1" == "--help" \) ]; then
		echo ""
		echo "Updater script for LuaDNS A record's IP update"
		echo ""
		echo "Usage: LuaUpdate.sh domainname email token [updateinterval]"
		echo ""
		echo "  domainname:     The domain name to update."
		echo "  email:          Email address for LuaDNS registration."
		echo "  token:          The token for the LuaDNS registration."
		echo "                    After logging in to LuaDNS the token can be obtained by clicking"
		echo "                    on the ""Show token"" button in the Account menu's API Token row."
		echo "  updateinterval: The frequency of IP address change checks in seconds."
		echo ""
		echo ""
		echo "Example: LuaUpdate.sh mydomainname.net my@mail.com 150 &"
		echo ""
		exit 1
	fi
}

# Checks that jq JSON processor is installed on the system.
JQInstalledCheck()
{
	if [ $(type -p jq) == "" ]; then
		echo ""
		echo "jq - commandline JSON processor need to be installed for the script to work properly!"
		echo ""
		exit 1
	fi
}

# Stores the script's CLI parameters to named variables.
StoreScriptParameters()
{
	Email="$1"
	Token="$2"
	Domain="$3"

	if [ "$#" == "4" ]; then
		UpdateInterval=$4
	else
		UpdateInterval=150
	fi	
}

# Gets the Zone, Zone A record's ID.
GetLuaDNSIDs()
{
	ZoneID=$( curl -s -u $Email:$Token -H 'Accept: application/json' https://api.luadns.com/v1/zones/ | jq ".[] | select(.name == \"$Domain\") | .id" )
	ARecordID=$( curl -s -u $Email:$Token -H 'Accept: application/json' https://api.luadns.com/v1/zones/$ZoneID | jq ".records[] | select(.type == \"A\") | .id" )
}

# Gets router's current IP and the A record IP stored at DNS
GetIPs()
{
	CurrentWANIP=$( nvram get wan_ipaddr )
	DNSIP=$( curl -s -u $Email:$Token -H 'Accept: application/json' https://api.luadns.com/v1/zones/$ZoneID/records/$ARecordID | jq '.content' -r )
}

# Checks that the external IP address has changed or not?
CheckIPChange()
{
	local IPChanged="false"
	
	if [ "$CurrentWANIP" != "$DNSIP" ]; then
		IPChanged="true"
	fi
	
	echo $IPChanged
}

# Checks the IP validity
ValidateIP()
{
	local IPIsValid="true"

	# 0.0.0.0, 1.1.1.1, etc IPs
	if echo "$CurrentWANIP" | grep -Eq '^\d{1}\.(\d{1}\.){2}\d{1}$'; then
		IPIsValid="false"
	
	# 192.168.x.x
	elif echo "$CurrentWANIP" | grep -Eq '^192\.168\.\d{1,3}\.\d{1,3}$'; then
		IPIsValid="false"

	# localhost
	elif echo "$CurrentWANIP" | grep -Eq '127.0.0.1'; then
		IPIsValid="false"
	fi
	
	echo $IPIsValid
}

# Updates the domains LuaDNS A record.
UpdateARecord() {
	local json="{\"id\":$ARecordID,\"name\":\"$Domain.\",\"type\":\"A\",\"content\":\"$CurrentWANIP\",\"ttl\":300,\"zone_id\":$ZoneID}"
	local UpdateSuccessfull="false";
	
	# Try update A record until it is successfully updated.
	while [ "$UpdateSuccessfull" != "true" ] 
	do
		local ReturnedID=$(curl -s -u $Email:$Token -H 'Accept: application/json' -X PUT -d $json https://api.luadns.com/v1/zones/$ZoneID/records/$ARecordID | jq '.id')
		
		# Successfull update
		if [ "$ReturnedID" == "$ARecordID" ]; then
			WriteToLog IPUpdateSuccess
			UpdateSuccessfull="true";
		# Update failed -> write to log, wait 5 secs
		else
			WriteToLog IPUpdateFailed
			sleep 5
		fi
	done
}

# Write event to log file.
WriteToLog() {
	local DateTime=$(date +"%F %T")
	
	if [ "$1" == "CheckIPChange" ]; then
		sed -i "1i $DateTime - $Domain IP does not changed. No update needed." $LogPath$LogFileName
		
	elif [ "$1" == "IPUpdateSuccess" ]; then
		sed -i "1i $DateTime - Successfull A record update on $Domain. A record IP has changed from $DNSIP to $CurrentWANIP ." $LogPath$LogFileName
	
	elif [ "$1" == "IPUpdateFailed" ]; then
		sed -i "1i $DateTime - Failed A record update on $Domain. A record IP could not be changed from $DNSIP to $CurrentWANIP ." $LogPath$LogFileName

	# IP validity failed
	elif [ "$1" == "IPIsNotValid" ]; then
		sed -i "1i $DateTime - The current external IP ($CurrentWANIP) is not valid. DNS A record update skipped." $LogPath$LogFileName

	# log file exist, insert line to log file's first line
	elif [ "$1" == "Start" ] && [ -f $LogPath$LogFileName ]; then
		sed -i "1i $DateTime - LuaUpdater started" $LogPath$LogFileName
	
	# log file does not exist, echo the log
	elif [ "$1" == "Start" ] && [ ! -f $LogPath$LogFileName ]; then
		echo "$DateTime - LuaUpdater started" > $LogPath$LogFileName
		
	fi
}

# Sending email about events
SendMail() {
	printf "To: csore.tamas@gmail.com\nSubject: IP change notification!\nFrom: nexus@home-net.ml\nContent-Type: text/html; charset=\"utf8\"\n<html><body><H1>IP changed from $DNSIP to $CurrentWANIP!</H1></body></html>" > mail.txt
	curl --url 'smtps://smtp.gmail.com:465' --ssl-reqd --mail-from 'nexus@home-net.ml' --mail-rcpt 'csore.tamas@gmail.com' --user 'csore.tamas@gmail.com:,yH"=^2`So*a=9PD' --upload-file mail.txt -s
}
# -----------------------------------------------------------------------------------------------
# End of functions
# -----------------------------------------------------------------------------------------------


# -----------------------------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------------------------
Help $@
JQInstalledCheck
StoreScriptParameters $@
GetLuaDNSIDs

WriteToLog Start

while sleep $UpdateInterval
do
	GetIPs
	HasIPChanged=$( CheckIPChange )
	
	# Checks the validity of the new IP.
	if [ "$HasIPChanged" == "true" ]; then
		IsIPValid=$( ValidateIP )
		
		# External IP is valid -> email send, update A record.
		if [ "$IsIPValid" == "true" ]; then
			SendMail
			UpdateARecord # Try update A record until it is successfully updated.
		# Log if the new external IP is not valid.
		else
			WriteToLog IPIsNotValid
		fi
	fi
done
## -----------------------------------------------------------------------------------------------
## End of main
## -----------------------------------------------------------------------------------------------