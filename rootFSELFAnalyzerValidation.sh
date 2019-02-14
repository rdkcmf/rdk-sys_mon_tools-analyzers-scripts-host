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
	echo "$name# -e   : an optional executable file list to analyze instead of default - \"all executables\" analysis"
	echo "$name# -pm  : a mandatory \"/proc/*/maps\" file of all processes, use \"grep r-xp /proc/*/maps\" to collect, mutually exclusive w/ -pml"
	echo "$name# -pml : a mandatory list of \"/proc/*/maps\" files of all processes, use \"grep r-xp /proc/*/maps\" to collect an instance, mutually exclusive w/ -pm"
	echo "$name# -pmlo: an optional multi- instance \"/proc/*/maps\" files (t) total, (c) common, (s) specific metrics analysis, default -(tc)"
	echo "$name# -ea  : a mandatory file listing all exes"
	echo "$name# -ed  : a mandatory file listing all libdl-api elfs"
	echo "$name# -w   : an optional work folder"
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
exeList=
ppmFile=
exeAllFile=
elfDlapiAllFile=
wFolder=
ppmList=
ppmlOpts=tc

while [ "$1" != "" ]; do
	case $1 in
		-rn )		shift
				rootFS="$1"
				;;
		-ef )		shift
				rfsElfFolder="$1"
				;;
		-e)		shift
				exeList="$1"
				;;
		-pm)		shift
				ppmFile="$1"
				;;
		-pml)		shift
				ppmList="$1"
				;;
		-pmlo)		shift
				ppmlOpts="$1"
				;;
		-ea)		shift
				exeAllFile="$1"
				;;
		-ed)		shift
				elfDlapiAllFile="$1"
				;;
		-w )		shift
				wFolder="$1"
				;;
		-h | --help )	usage
				exit $ERR_NOT_A_ERROR
				;;
		* )		echo "$name# ERROR : unknown parameter  \"$1\" in the command argument list!" | tee -a "$name".log
				usage
				exit $ERR_UNKNOWN_PARAM
	esac
	shift
done

if [ -z "$rootFS" ]; then
	echo "$name# ERROR : rootFS name=\"$rootFS\" is not set or found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -z "$rfsElfFolder" ] || [ ! -d "$rfsElfFolder" ]; then
	echo "$name# ERROR : elf folder=\"$rfsElfFolder\" is not set or found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -n "$ppmFile" ] && [ -n "$ppmList" ]; then
	echo "$name# ERROR : -pm and -pmi options are mutually exclusive!" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
elif [ -n "$ppmFile" ] && [ ! -e "$ppmFile" ]; then
	echo "${name}# ERROR : a mandatory \"/proc/*/maps\" file = \"$ppmFile\" is not set or doesn't exist!" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
elif [ -n "$ppmList" ] && [ ! -e "$ppmList" ]; then
	echo "${name}# ERROR : a mandatory \"/proc/*/maps\" files list = \"$ppmList\" is not set or doesn't exist!" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
elif [ -z "$ppmFile" ] && [ -z "$ppmList" ]; then
	echo "$name# ERROR : either /proc/*/maps file or /proc/*/maps files list set via -pm / -pmi options must be present!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -n "$ppmList" ]; then
	if [ -n "$ppmlOpts" ] && [[ $ppmlOpts =~ [^tcs] ]]; then
		echo "$name# ERROR : invalid option -pmlo = \"$(echo $ppmlOpts | sed 's/t//g;s/c//g;s/s//g')\". Exit !" | tee -a "$name".log
		usage
		exit $ERR_OBJ_NOT_VALID
	fi

	while read entry
	do
		if [ ! -e "$entry" ]; then
			echo "$name# ERROR : ppmaps file \"$entry\" in the \"$ppmList\" list is not found!" | tee -a "$name".log
			usage
			exit $ERR_OBJ_NOT_VALID
		fi
	done < "$ppmList"

	ln -sf "$ppmList" "$rootFS".maps.list
else
	echo "$ppmFile" > "$rootFS".maps.list
fi

if [ ! -e "$exeAllFile" ]; then
	echo "$name# ERROR : mandatory file=\"$exeAllFile\" listing all exe names is not set or doesn't exist!" | tee -a "$name".log
	usage
	exit
fi

if [ -n "$exeList" ]; then
	if [ ! -s "$exeList" ]; then
		echo "$name# Error : executable file list \"$exeList\" is empty or not found!" | tee -a "$name".log
		usage
		exit
	fi
	cat /dev/null > "$exeList".short
	comm "$exeAllFile" <(sort -u "$exeList") | awk -F$'\t' -v file="$exeList" '{\
		if (NF == 2) {\
			printf("%s\n", $2) > file".notFound"
		} else if (NF == 3) {\
			printf("%s\n", $3) > file".short"
		}\
		}'
	if [ -s "$exeList".notFound ]; then
		echo "$name# Warn  : executable file list \"$exeList\" contains not found files!" | tee -a "$name".log
	fi
	if [ ! -s "$exeList".short ]; then
		echo "$name# Error : executable file list \"$exeList\" doesn't contain valid executables! Exit." | tee -a "$name".log
		exit $ERR_OBJ_NOT_VALID
	fi
fi

if [ ! -e "$elfDlapiAllFile" ]; then
	echo "$name# ERROR : mandatory file=\"$elfDlapiAllFile\" listing all dlapi elf names is not set or doesn't exist!" | tee -a "$name".log
	usage
	exit
fi

wFolderPfx=$(_mkWFolder "$wFolder")

echo "$name : rootFS name        = $rootFS"          | tee -a "$name".log
echo "$name : elf folder         = $rfsElfFolder"    | tee -a "$name".log
if [ -n "$exeList" ]; then
	echo "$name : exeList            = $exeList" | tee -a "$name".log
fi
if [ -n "$ppmFile" ]; then
	echo "$name : ppmaps file        = $ppmFile" | tee -a "$name".log
else
	echo "$name : ppmaps files list  = $ppmList" | tee -a "$name".log
	echo "$name : options            = $ppmlOpts" | tee -a "$name".log
fi
echo "$name : exe all file       = $exeAllFile"      | tee -a "$name".log
echo "$name : elf dlapi all file = $elfDlapiAllFile" | tee -a "$name".log
echo "$name : path               = $path"            | tee -a "$name".log
if [ -n "$wFolder" ]; then
	echo "$name : work folder        = $wFolder" | tee -a "$name".log
fi
echo "$name : wFolderPfx         = $wFolderPfx"      | tee -a "$name".log

startTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`

if [ -n "$ppmList" ]; then
	# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps files list : $4 - rt validation folder
	#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - procs to analyze : $8 - log name : $9 - work folder :  $10 - mrtv analysis ops
	_rootFSElfAnalyzerMValidation "$rootFS" "$rfsElfFolder" "$ppmList" "$rootFS".rt-validation \
					"$exeAllFile" "$elfDlapiAllFile" "$exeList" "$name".log "$wFolder" "$ppmlOpts"
else
	# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps file : $4 - rt validation folder
	#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - procs to analyze : $8 - log name : $9 - work folder
	_rootFSElfAnalyzerValidation "$rootFS" "$rfsElfFolder" "$ppmFile" "$rootFS".rt-validation \
					"$exeAllFile" "$elfDlapiAllFile" "$exeList" "$name".log "$wFolderPfx"
#					"$exeAllFile" "$elfDlapiAllFile" "" "$wFolderPfx/$valFolder/$name".log "$wFolderPfx"/$valFolder
#	echo "$(cat "$name".log "$wFolderPfx/$valFolder/$name".log)" > "$wFolderPfx/$valFolder/$name".log
fi

[ "$(readlink -e "$wFolder")" != "$PWD" ] && mv "$name".log "$wFolderPfx"

find "$wFolderPfx" -maxdepth 2 -size 0 -exec rm {} \;
rm -f "$rootFS".maps.list
endTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

