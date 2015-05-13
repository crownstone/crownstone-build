#!/bin/bash

path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echoerr() { cat <<< "$@" 1>&2; }

# Settings
bluenetDir=$HOME/bluenet
bluenetConfigsDir=$path/bluenet_configs
logDir=logs
defaultEmail="bart@dobots.nl"
bleAutomatorDir=$HOME/ble-automator
crownstoneAddress="C0:D1:8D:33:4E:29"
bluetoothInterface="hci0"

force=0
if [ $# -gt 0 ]; then
	if [ "$1" == "-f" ]; then
		force=1
	fi
fi

logFullDir="${path}/logs"
lastCommitEmail=$defaultEmail
function checkForError {
	echo "$2 result: $1"
	if [ "$1" != "0" -a $force == 0 ]; then
		tar -C "$path" -zcf "${path}/log.tar.gz" "$logDir" >> /dev/null
		mail -A "${path}/log.tar.gz" -s "crownstone build failed" $lastCommitEmail <<< "Failed: $2"
		echo "Sent an e-mail to $lastCommitEmail"
		return 1
	fi
	return 0
}

mkdir -p "$logFullDir"

cd "$bluenetDir"
git pull
res=$?
checkForError $res "Git pull"
if [ "$?" != "0" ]; then exit 1; fi

lastCommitEmail="$( git log | grep -P '^Author:\s' | head -n1 | grep -oP '<[^>]+>' | sed -re 's/[<>]//g')"
newCommitHash="$(git log | grep -P '^commit\s' | head -n1 | cut -d ' ' -f2)"
if [ -e "$path/lastCommit.sh" ]; then
	source "$path/lastCommit.sh"
	if [ "$lastCommitHash" == "$newCommitHash" ]; then
		echo "No new commit found!"
		if [ $force == 0 ]; then
			exit 0
		fi
	else
		echo "lastCommitHash=${newCommitHash}" > "$path/lastCommit.sh"
		echo "New commit found!"
	fi
fi

mkdir -p "$bluenetConfigsDir/default"
cp "$bluenetDir/CMakeBuild.config.default" "$bluenetConfigsDir/default/CMakeBuild.config"
for d in ${bluenetConfigsDir}/* ; do
	# Set config dir
	echo "Using "$d" as config dir"
	export BLUENET_CONFIG_DIR="$d"
	
	# Remove build dir to be sure we start with a clean build
	rm -r "$bluenetDir/build"
	rm -r "$d/build"
	
	# Clean the logs
	cd "$logFullDir"
	rm softdevice*
	rm firmware*
	
	# Build the code
	cd "$bluenetDir/scripts"
	./softdevice.sh build > "$logFullDir/softdevice_make.log" 2> "$logFullDir/softdevice_make_err.log"
	checkForError $? "softdevice build"
	if [ "$?" != "0" ]; then exit 1; fi
	
	./firmware.sh build crownstone > "$logFullDir/firmware_make.log" 2> "$logFullDir/firmware_make_err.log"
	checkForError $? "firmware build"
	if [ "$?" != "0" ]; then exit 1; fi
	
	# Upload the code
	cd "$bluenetDir/scripts"
	./softdevice.sh upload > "$logFullDir/softdevice_upload.log" 2> "$logFullDir/softdevice_upload_err.log"
	echo "softdevice upload result: $?"
#	checkForError $? "softdevice upload"
#	if [ "$?" != "0" ]; then exit 1; fi
	
	./firmware.sh upload crownstone > "$logFullDir/firmware_upload.log" 2> "$logFullDir/firmware_upload_err.log"
	checkForError $? "firmware upload"
	if [ "$?" != "0" ]; then exit 1; fi
	
	# Give crownstone some time to boot
	sleep 3
	
	# Read temperature
	cd "$bleAutomatorDir"
	./getTemperature.py -i $bluetoothInterface -a $crownstoneAddress > "$logFullDir/read_temperature.log" 2> "$logFullDir/read_temperature_err.log"
	checkForError $? "read temperature"
	if [ "$?" != "0" ]; then exit 1; fi
	
	
	
	# Write some config
	cd "$bleAutomatorDir"
	./writeConfig.py -i $bluetoothInterface -a $crownstoneAddress -t 3 -d 5 -n > "$logFullDir/readwrite_config.log" 2> "$logFullDir/readwrite_config_err.log"
	checkForError $? "write config"
	if [ "$?" != "0" ]; then exit 1; fi
	
	# Reset crownstone
	./reset.py -i $bluetoothInterface -a $crownstoneAddress >> "$logFullDir/readwrite_config.log" 2>> "$logFullDir/readwrite_config_err.log"
#	echo "reset crownstoneresult: $?"
	checkForError $? "reset crownstone"
	if [ "$?" != "0" ]; then exit 1; fi
	sleep 5
	
	# Read config
	./readConfig.py -i $bluetoothInterface -a $crownstoneAddress -t 3 -n >> "$logFullDir/readwrite_config.log" 2>> "$logFullDir/readwrite_config_err.log"
	checkForError $? "read config"
	if [ "$?" != "0" ]; then exit 1; fi
	
	# Compare written with read config
	res=0
	if [ $(grep -c "Value: 5" $logFullDir/readwrite_config.log) -ne 1 ]; then
		res=1
	fi
	checkForError $res "compare written with read config"
	if [ "$?" != "0" ]; then exit 1; fi
done

exit 0
