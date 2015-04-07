#!/bin/bash

path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echoerr() { cat <<< "$@" 1>&2; }

# Settings
bluenetDir=$HOME/bluenet
bluenetConfigsDir=$path/bluenet_configs
logDir=logs
defaultEmail="bart@dobots.nl"


logFullDir="${path}/logs"
lastCommitEmail=$defaultEmail
function checkForError {
	echo "$2 result: $1"
	if [ "$1" != "0" ]; then
		tar -C "$path" -cf "${path}/log.tar" "$logDir" >> /dev/null
		p7zip "${path}/log.tar" >> /dev/null
		mail -A "${path}/log.tar.7z" -s "crownstone build failed" $lastCommitEmail <<< "Failed: $2"
		echo "Sent an e-mail to $lastCommitEmail"
		return 1
	fi
	return 0
}

mkdir -p "logFullDir"

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
		exit 0
	fi
fi
echo "lastCommitHash=${newCommitHash}" > "$path/lastCommit.sh"
echo "New commit found!"

for d in ${bluenetConfigsDir}/* ; do
	# Set config dir
	export BLUENET_CONFIG_DIR="$d"
	
	# Remove build dir to be sure we start with a clean build
	rm -r "$bluenetDir/build"
	rm -r "$d/build"
	
	# Clean the logs
	rm "$logFullDir/softdevice\*"
	rm "$logFullDir/firmware\*"
	
	# Build the code
	cd "$bluenetDir/scripts"
	./softdevice.sh build > "$logFullDir/softdevice_make.log" 2> "$logFullDir/softdevice_make_err.log"
	res=$?
	checkForError $? "softdevice build"
	if [ "$?" != "0" ]; then exit 1; fi
	
	./firmware.sh build crownstone > "$logFullDir/firmware_make.log" 2> "$logFullDir/firmware_make_err.log"
	res=$?
	checkForError $res "firmware build"
	if [ "$?" != "0" ]; then exit 1; fi
	
	# Upload the code
	cd "$bluenetDir/scripts"
	./softdevice.sh upload > "$logFullDir/softdevice_upload.log" 2> "$logFullDir/softdevice_upload_err.log"
	res=$?
	checkForError $? "softdevice upload"
	if [ "$?" != "0" ]; then exit 1; fi
	
	./firmware.sh upload crownstone > "$logFullDir/firmware_upload.log" 2> "$logFullDir/firmware_upload_err.log"
	res=$?
	checkForError $res "firmware upload"
	if [ "$?" != "0" ]; then exit 1; fi
done

exit 0
