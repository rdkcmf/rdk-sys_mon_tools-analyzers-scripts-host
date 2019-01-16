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
	echo "$name# Usage : `basename $0 .sh` -r folder [[-e file] | [-l file]] [-od name] | [-h]"
	echo "$name# Target RootFS NSS single ELF object analyzer, requires env PATH set to platform tools with objdump"
	echo "$name# -r    : a mandatory rootFS folder"
	echo "$name# -e    : a mandatory target elf (exe/so) object"
	echo "$name# -cache: \"use cache\" option; default - cache is not used, all file folders are removed"
	echo "$name# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "$name# -h    : display this help and exit"
}


# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
path=$0
path=${path%/*}
echo "$cmdline" > "$name".log
exitCode=

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

rfsFolder=
elf=
cache=

while [ "$1" != "" ]; do
	case $1 in
		-r | --root )	shift
				rfsFolder="$1"
				;;
		-e | --elf )	shift
				elf="$1"
				;;
		-cache )	cache=y
				;;
		-od )		shift
				objdump="$1"
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

if [ -z "$rfsFolder" ] || [ ! -d "$rfsFolder" ]; then
	echo "$name# ERROR : rootFS folder \"$rfsFolder\" is not set or found!"
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -z "$elf" ]; then
	echo "$name# ERROR : elf object name is not set!"
	usage
	exit $ERR_PARAM_NOT_SET
elif [ ! -e "$rfsFolder"/"$elf" ]; then
	echo "$name# ERROR : elf object \"$rfsFolder/$elf\" is not found!"
	usage
	exit $ERR_PARAM_NOT_SET
fi

# Check paltform
platform="$(file -b "$rfsFolder"/"$elf" | grep "^ELF ")"
if [ -z "$platform" ]; then
	echo "$name# ERROR  : object \"$rfsFolder/$elf\" is NOT an ELF file!" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
fi

objdumpDefaultNative=
# Check if the $elf ELF object architechture is supported
elfArch=$(echo "$platform" | cut -d, -f2)
if [ ! -z "$(echo "$elfArch" | grep "MIPS")" ]; then
	objdumpDefaultNative=mipsel-linux-objdump
elif [ ! -z "$(echo "$elfArch" | grep "Intel .*86")" ]; then
	objdumpDefaultNative=i686-cm-linux-objdump
elif [ ! -z "$(echo "$elfArch" | grep "ARM")" ]; then
	objdumpDefaultNative=armeb-rdk-linux-uclibceabi-objdump
else
	echo "$name# ERROR : \"$elf\" object is of unsupported architechture : \"$elfArch\"" | tee -a "$name".log
	echo "$name# ERROR : supported architechtures  = {ARM | MIPS | x86}" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
fi

if [ -z "$objdump" ]; then
	# Check if the PATH to $objdumpDefaultNative is set
	if [ -z "$(which $objdumpDefaultNative)" ]; then
		# Set objectdump default generic
		objdump="/usr/bin/objdump"
	else
		# Set objectdump default native
		objdump=$objdumpDefaultNative
	fi
else
	# Check if the PATH to a user-defined $objdump is set
	if [ -z "$(which $objdump)" ]; then
		echo "$name# ERROR : PATH to $objdump is not set!" | tee -a "$name".log
		usage
		exit $ERR_PARAM_NOT_SET
	fi
fi


if [ ! -e "$rfsFolder"/version.txt ]; then
	echo "$name# Warn  : $rfsFolder/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name"
	rootFS=`basename $rfsFolder`
else
	rootFS=`grep -i "^imagename" $rfsFolder/version.txt |  tr ': =' ':' | cut -d ':' -f2`
fi

echo "$name : rfsFolder = $rfsFolder" | tee -a "$name".log
echo "$name : objdump   = $objdump"   | tee -a "$name".log
echo "$name : path      = $path"      | tee -a "$name".log
echo "$name : rootFS    = $rootFS"    | tee -a "$name".log
[ -z "$cache" ] && echo "$name : cache     = no" | tee -a "$name".log || echo "$name : cache     = yes" | tee -a "$name".log

sub=${rfsFolder%/}

rfsDLinkFolder="$rootFS".dlink
[ -z "$cache" ] && rm -rf "$rfsDLinkFolder"
mkdir -p "$rfsDLinkFolder"

rfsNssFolder="$rootFS".nss
[ -z "$cache" ] && rm -rf "$rfsNssFolder"
mkdir -p "$rfsNssFolder"

odTCDFtextFolder="$rootFS".odTC-DFtext
[ -z "$cache" ] && rm -rf "$odTCDFtextFolder"
mkdir -p "$odTCDFtextFolder"

odTCDFUNDFolder="$rootFS".odTC-DFUND
[ -z "$cache" ] && rm -rf "$odTCDFUNDFolder"
mkdir -p "$odTCDFUNDFolder"

startTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`

outFile=$(echo "$elf" | tr '/' '%')

_rootFSBuildNssCache "$rfsFolder"
_rootFSNssElfAnalyzer "$rfsFolder" "$elf" "$rfsNssFolder/$outFile"

endTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

