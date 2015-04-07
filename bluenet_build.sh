#!/bin/bash

path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echoerr() { cat <<< "$@" 1>&2; }

# Settings
bluenetdir=/home/crownstone/bluenet
configsdir=/home/crownstone/bluenet_configs
logdir=$path/logs
defaultEmail="bart@dobots.nl"

lastCommitEmail=$defaultEmail
function checkForError {
#	echo $lastCommitEmail
	if [ "$1" != "0" ]; then
		tar -cf "${path}/log.tar" "$logdir"
		p7zip "${path}/log.tar"
		mail -A "${path}/log.tar.7z" -s "crownstone build failed" $lastCommitEmail <<< "Failed: $2"
		exit 1
	fi
}

mkdir -p "$logdir"

cd "$bluenetdir"
#cd /home
git pull
res=$?
checkForError $res "Git pull"
#if [ "$res" != "0" ]; then
#	echoerr "Git pull failed!"
#	exit 1
#fi

lastCommitEmail="$( git log | grep Author | head -n1 | grep -oP "<[^>]+>" | sed -re 's/[<>]//g')"

for d in ${configsdir}/* ; do
	# Set config dir
	export BLUENET_CONFIG_DIR="$d"

	# Remove build dir to be sure we start with a clean build
	rm -r "$bluenetdir/build"

	# Build the code
	cd "$bluenetdir/scripts"
	./softdevice.sh build > "$logdir/make.log" 2> "$logdir/make_err.log"
	res=$?
	checkForError $? "softdevice build"
	echo "Softdevice build result: $res"

	./firmware.sh build crownstone > "$logdir/make.log" 2> "$logdir/make_err.log"
	res=$?
	checkForError $res "firmware build"
	echo "Firmware build result: $res"

done

exit 0
