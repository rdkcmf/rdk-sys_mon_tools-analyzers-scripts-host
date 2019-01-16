#!/bin/bash

#set -u

#!/bin/bash
#
# If not stated otherwise in this file or this component's Licenses.txt file the
# following copyright and licenses apply:
#
# Copyright 2016 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-rn folder -re elf folder -ppm file -ea exe all file -ed libdl elf all file] | [-h]"
	echo "$name# Dynamically linked/loaded shared object validator"
	echo "$name# -rn  : a mandatory rootFS name"
	echo "$name# -ef  : a mandatory rootFS elf folder"
	echo "$name# -pm  : a mandatory \"/proc/*/maps\" file of all processes, use \"grep r-xp /proc/*/maps\" to collect"
	echo "$name# -ea  : a mandatory file listing all exes"
	echo "$name# -ed  : a mandatory file listing all libdl-api elfs"
	echo "$name# -h   : display this help and exit"
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
path=$0
path=${path%/*}
echo "$cmdline" > "$name".log

if [ ! -e "$path"/errorCommon.sh ]; then
	echo "$name# ERROR : Cannot find errorCommon.sh! Exit with \"object is not found\" error!" | tee -a "$name".log
	exit 3
fi

. "$path"/errorCommon.sh

if [ ! -e "$path"/rootFSElfAnalyzerCommon.sh ]; then
	echo "$name# ERROR : Cannot find rootFSElfAnalyzerCommon.sh! Exit with \"object is not found\" error!" | tee -a "$name".log
	exit $ERR_OBJ_NOT_FOUND
fi

. "$path"/rootFSElfAnalyzerCommon.sh
. "$path"/rootFSCommon.sh

rootFS=
rfsElfFolder=
ppmFile=
exeAllFile=
elfDlapiAllFile=

while [ "$1" != "" ]; do
	case $1 in
		-rn )		shift
				rootFS="$1"
				;;
		-ef )		shift
				rfsElfFolder="$1"
				;;
		-pm)		shift
				ppmFile="$1"
				;;
		-ea)		shift
				exeAllFile="$1"
				;;
		-ed)		shift
				elfDlapiAllFile="$1"
				;;
		-h | --help )	usage
				exit $ERR_NOT_A_ERROR
				;;
		* )		echo "$name# ERROR : unknown parameter  \"$1\" in the command argument list!"
				usage
				exit $ERR_UNKNOWN_PARAM
	esac
	shift
done

if [ -z "$rootFS" ]; then
	echo "$name# ERROR : rootFS name=\"$rootFS\" is not set or found!"
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -z "$rfsElfFolder" ] || [ ! -d "$rfsElfFolder" ]; then
	echo "$name# ERROR : elf folder=\"$rfsElfFolder\" is not set or found!"
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ ! -e "$ppmFile" ]; then
	echo "${name}# ERROR : a mandatory \"/proc/*/maps\" file=\"$ppmFile\" is not set or doesn't exist!"
	usage
	exit
fi

if [ ! -e "$exeAllFile" ]; then
	echo "$name# ERROR : mandatory file=\"$exeAllFile\" listing all exe names is not set or doesn't exist!"
	usage
	exit
fi

if [ ! -e "$elfDlapiAllFile" ]; then
	echo "$name# ERROR : mandatory file=\"$elfDlapiAllFile\" listing all dlapi elf names is not set or doesn't exist!"
	usage
	exit
fi

echo "$name : rootFS name        = $rootFS"          | tee -a "$name".log
echo "$name : elf folder         = $rfsElfFolder"    | tee -a "$name".log
echo "$name : ppmaps file        = $ppmFile"         | tee -a "$name".log
echo "$name : exe all file       = $exeAllFile"      | tee -a "$name".log
echo "$name : elf dlapi all file = $elfDlapiAllFile" | tee -a "$name".log
echo "$name : path               = $path"            | tee -a "$name".log

startTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`

# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps file : $4 - rt validation folder
#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - log name
_rootFSElfAnalyzerValidation "$rootFS" "$rfsElfFolder" "$ppmFile" "$rootFS".rt-validation \
				"$exeAllFile" "$elfDlapiAllFile" "$name".log


endTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

