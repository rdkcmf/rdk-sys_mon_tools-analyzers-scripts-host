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
	echo "$name# Target rootFS ELF object symbol builder, requires env PATH set to platform tools with objdump"
	echo "$name# -r    : a mandatory rootFS folder"
	echo "$name# -rdbg : an optional rootFS dbg folder with ELF symbolic info"
	echo "$name# -e    : a mandatory target elf (exe/so) object - mutually exclusive with -l"
	echo "$name# -el   : a mandatory elf reference file - mutually exclusive with -e"
	echo "$name# -s    : a mandatory d/u (defined/undefined) symbol option"
	echo "$name# -cache: \"use cache\" option; default - cache is not used, all file folders are removed"
	echo "$name# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "$name# -w    : an optional work folder"
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
. "$path"/rootFSCommon.sh

rfsFolder=
rdbgFolder=
wFolder=.
elf=
cache=
elfList=
symbols=

while [ "$1" != "" ]; do
	case $1 in
		-r | --root )	shift
				rfsFolder="$1"
				;;
		-rdbg )		shift
				rdbgFolder="$1"
				;;
		-e | --elf )	shift
				elf="$1"
				;;
		-el )		shift
				elfList="$1"
				;;
		-s )		shift
				symbols="$1"
				;;
		-cache )	cache=y
				;;
		-od )		shift
				objdump="$1"
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

if [ -z "$rfsFolder" ] || [ ! -d "$rfsFolder" ]; then
	echo "$name# ERROR : rootFS folder \"$rfsFolder\" is not set or found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -n "$rdbgFolder" ] && [ ! -d "$rdbgFolder" ]; then
	echo "$name# ERROR : rootFS dbg folder \"$rfsFolder\" is set but not found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -n "$elf" ] && [ -n "$elfList" ]; then
	echo "$name# ERROR : -e and -l options are mutually exclusive!" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
elif [ -n "$elf" ] && [ ! -e "$rfsFolder"/"$elf" ]; then
	echo "$name# ERROR : elf object \"$rfsFolder/$elf\" is not found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
elif [ -n "$elfList" ] && [ ! -e "$elfList" ]; then
	echo "$name# ERROR : elf reference file \"$elfList\" is not found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
elif [ -z "$elf" ] && [ -z "$elfList" ]; then
	echo "$name# ERROR : Either elf object or elf reference file via -e / -l options must be set!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -z "$symbols" ]; then
	echo "$name# ERROR : d/u (defined/undefined) symbol option-s must be set!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

echo "symbols=$symbols"

if [[ $symbols =~ [^ud] ]]; then
	echo "$name# ERROR : invalid option -s = \"$(echo $symbols | sed 's/u//g;s/d//g')\". Exit !" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
fi

[ -n "$elf" ] && platformFile="$elf" || platformFile="/bin/bash"

# Check paltform
platform="$(file -b "$rfsFolder/$platformFile" | grep "^ELF ")"
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
	echo "$name# Warn  : $rfsFolder/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name" | tee -a "$name".log
	rootFS=`basename $rfsFolder`
else
	rootFS=`grep -i "^imagename" $rfsFolder/version.txt |  tr ': =' ':' | cut -d ':' -f2`
fi

echo "$name : rfsFolder = $rfsFolder" | tee -a "$name".log
echo "$name : rdbgFolder= $rdbgFolder" | tee -a "$name".log
if [ -n "$elf" ]; then
	echo "$name : elf       = $elf" | tee -a "$name".log
else
	echo "$name : elfList   = $elfList" | tee -a "$name".log
fi
echo "$name : objdump   = $objdump"   | tee -a "$name".log
echo "$name : path      = $path"      | tee -a "$name".log
echo "$name : rootFS    = $rootFS"    | tee -a "$name".log
if [ -z "$cache" ]; then
	echo "$name : cache     = no" | tee -a "$name".log
else
	echo "$name : cache     = yes" | tee -a "$name".log
fi
if [ -n "$wFolder" ]; then
	echo "$name : work dir  = $wFolder"  | tee -a "$name".log
fi

odTCDFUNDFolder="$rootFS".odTC-DFUND
odTCDFtextFolder="$rootFS".odTC-DFtext

startTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`

outFile=$(echo "$elf" | tr '/' '%')
if [[ $symbols = *[u]* ]]; then
	_wFolderPfx=$(_mkWFolder "$wFolder/$odTCDFUNDFolder")
	echo "$name : wFolderPfx= $_wFolderPfx" | tee -a "$name".log

	if [ -n "$elf" ]; then
		_buildElfDFUNDtTable "$rfsFolder" "$elf" "$_wFolderPfx/$outFile"
	else
		while read entry
		do
			if [ ! -e "$rfsFolder"/"$entry" ]; then
				echo "$name# ERROR : elf object \"$rfsFolder/$entry\" is not found!" | tee -a "$name".log
				usage
				exit $ERR_PARAM_NOT_SET
			else
				_buildElfDFUNDtTable "$rfsFolder" "$entry" "$_wFolderPfx/$(echo "$entry" | tr '/' '%')"
			fi
		done < "$elfList"
	fi
fi

if [[ $symbols = *[d]* ]]; then
	_wFolderPfx=$(_mkWFolder "$wFolder/$odTCDFtextFolder")
	echo "$name : wFolderPfx= $_wFolderPfx" | tee -a "$name".log

	if [ -n "$elf" ]; then
		_buildElfDFtextTable "$rfsFolder" "$elf" "$_wFolderPfx/$outFile"
	else
		while read entry
		do
			if [ ! -e "$rfsFolder"/"$entry" ]; then
				echo "$name# ERROR : elf object \"$rfsFolder/$entry\" is not found!" | tee -a "$name".log
				usage
				exit $ERR_PARAM_NOT_SET
			else
				_buildElfDFtextTable "$rfsFolder" "$entry" "$_wFolderPfx/$(echo "$entry" | tr '/' '%')"
			fi
		done < "$elfList"
	fi
fi

endTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

