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

# If external IP as changed, updates the last IP address stored in router's NVRAM.
UpdateNVRAMLastIP() {
	nvram set wan_ipaddr_last=$CurrentWANIP
	nvram commit
}

# Checks that the external IP address has changed or not?
CheckIPChange()
{
	CurrentWANIP=`nvram get wan_ipaddr`
	PreviousWANIP=`nvram get wan_ipaddr_last`
	local IPChanged="false"
	
	if [ $CurrentWANIP != $PreviousWANIP ]; then
		IPChanged="true"
		UpdateARecord
	fi
	
	return "$IPChanged"
}

# Updates the domains LuaDNS A record.
UpdateARecord() {
	json='{"id":$ARecordID,"name":"$Domain.","type":"A","content":"$CurrentWANIP","ttl":3600,"zone_id":$ZoneID}'
	local ReturnedID=$(curl -s -u $Email:$Token -H 'Accept: application/json' -X PUT -d '$json' https://api.luadns.com/v1/zones/$ZoneID/records/$ARecordID) | jq '.id'
	
	if [ "$ReturnedID" == "$ARecordID" ]; then
		WriteToLog IPUpdateSuccess
		SendMail OK
	else
		WriteToLog IPUpdateFailed
		SendMail
	fi
}

# Write event to log file.
WriteToLog() {
	local DateTime=$(date +"%F %T")
	
	if [ "$1" == "CheckIPChange" ]; then
		sed -i "1i $DateTime - $Domain IP does not changed. No update needed." $LogPath$LogFileName
		
	elif [ "$1" == "IPUpdateSuccess" ]; then
		sed -i "1i $DateTime - Successfull A record update on $Domain. A record IP has changed from $PreviousWANIP to $CurrentWANIP ." $LogPath$LogFileName
	
	elif [ "$1" == "IPUpdateFailed" ]; then
		sed -i "1i $DateTime - Failed A record update on $Domain. A record IP could not be changed from $PreviousWANIP to $CurrentWANIP ." $LogPath$LogFileName

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

	if [ "$1" == "OK" ]; then
		printf "To: csore.tamas@gmail.com\nSubject: IP change notification!\nFrom: nexus@home-net.ml\nContent-Type: text/html; charset=\"utf8\"\n<html><body><H1>IP changed <font color=\"green\">successfully</font> from $PreviousWANIP to $CurrentWANIP!</H1></body></html>" > mail.txt
	else
		printf "To: csore.tamas@gmail.com\nSubject: IP change notification!\nFrom: nexus@home-net.ml\nContent-Type: text/html; charset=\"utf8\"\n<html><body><H1>IP change from $PreviousWANIP to $CurrentWANIP <font color=\"red\">failed</font>!</H1></body></html>" > mail.txt
	fi
	
	curl --url 'smtps://smtp.gmail.com:465' --ssl-reqd --mail-from 'nexus@home-net.ml' --mail-rcpt 'csore.tamas@gmail.com' --user 'csore.tamas@gmail.com:,yH"=^2`So*a=9PD' --upload-file mail.txt -s
}
# -----------------------------------------------------------------------------------------------
# End of functions
# -----------------------------------------------------------------------------------------------


# -----------------------------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------------------------
Help $@
StoreScriptParameters $@
JQInstalledCheck
GetLuaDNSIDs

WriteToLog Start

while sleep $UpdateInterval
do
	CheckIPChange
	local IPChanged=$?
	
	

	if [ $IPChanged == "true" ]; then
		UpdateNVRAMLastIP
		UpdateARecord
	fi
done
## -----------------------------------------------------------------------------------------------
## End of main
## -----------------------------------------------------------------------------------------------