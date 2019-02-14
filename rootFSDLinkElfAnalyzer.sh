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
# $0 : rootFSsELFAnalyzer.sh is a Linux Host based script that analyzes a single ELF file dynamically linked shared library dependencies.


# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` -r folder {[-e file] | [-l file]} [-od name] [-dl file] [-il] [-w folder] | [-h]"
	echo "$name# Target RootFS dynamically linked single ELF object analyzer, requires env PATH set to platform tools with objdump"
	echo "$name# -r    : a mandatory rootFS folder"
	echo "$name# -rdbg : an optional rootFS dbg folder with ELF symbolic info"
	echo "$name# -e    : a mandatory target elf (exe/so) object - mutually exclusive with -l"
	echo "$name# -l    : a mandatory elf reference file - mutually exclusive with -e"
	echo "$name# -dl   : an optional libdl api to verify; default is \"$libdlDefault\" all"
	echo "$name# -cache: \"use cache\" option; default - cache is not used, all file folders are removed"
	echo "$name# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "$name# -w    : an optional work folder"
	echo "$name# -il   : an optional iteration log flag"
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
rdbgFolder=
wFolder=
elf=
elfRefs=
libdlApi=
iterLog=
cache=

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
		-l )		shift
				elfRefs="$1"
				;;
		-dl )		shift
				libdlApi="$1"
				;;
		-cache )	cache=y
				;;
		-od )		shift
				objdump="$1"
				;;
		-w )		shift
				wFolder="$1"
				;;
		-il )		iterLog=y
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

if [ -n "$elf" ] && [ -n "$elfRefs" ]; then
	echo "$name# ERROR : -e and -l options are mutually exclusive!" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
elif [ -n "$elf" ] && [ ! -e "$rfsFolder"/"$elf" ]; then
	echo "$name# ERROR : elf object \"$rfsFolder/$elf\" is not found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
elif [ -n "$elfRefs" ] && [ ! -e "$elfRefs" ]; then
	echo "$name# ERROR : elf reference file \"$elfRefs\" is not found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
elif [ -z "$elf" ] && [ -z "$elfRefs" ]; then
	echo "$name# ERROR : Either elf object or elf reference file via -e / -l options must be set!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -n "$libdlApi" ] && [ ! -e "$libdlApi" ]; then
	echo "$name# ERROR : libdlApi file \"$libdlApi\" is not found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
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
echo "$name : objdump   = $objdump"   | tee -a "$name".log
echo "$name : path      = $path"      | tee -a "$name".log
echo "$name : rootFS    = $rootFS"    | tee -a "$name".log
[ -z "$cache" ] && echo "$name : cache     = no" | tee -a "$name".log || echo "$name : cache     = yes" | tee -a "$name".log
if [ -n "$wFolder" ]; then
	echo "$name : work dir  = $wFolder"  | tee -a "$name".log
fi

wFolderPfx=.
if [ -n "$wFolder" ]; then
	wFolderPfx=$(echo "$wFolder" | tr -s '/')
	if [ "$wFolderPfx" != "." ] && [ "$wFolderPfx" != "./" ] ; then
		rm -rf "$wFolderPfx"
		echo "mkdir -p $wFolderPfx"
		mkdir -p "$wFolderPfx"
	fi
fi

rfsDLinkFolder="$rootFS".dlink
[ -z "$cache" ] && rm -rf "$rfsDLinkFolder"
mkdir -p "$rfsDLinkFolder"

rfsDLinkUnrefedSoFolder="$rootFS".dlink.unrefed-so
[ -z "$cache" ] && rm -rf "$rfsDLinkUnrefedSoFolder"
mkdir -p "$rfsDLinkUnrefedSoFolder"

odTCDFtextFolder="$rootFS".odTC-DFtext
[ -z "$cache" ] && rm -rf "$odTCDFtextFolder"
mkdir -p "$odTCDFtextFolder"

odTCDFUNDFolder="$rootFS".odTC-DFUND
[ -z "$cache" ] && rm -rf "$odTCDFUNDFolder"
mkdir -p "$odTCDFUNDFolder"

rfsLibdlFolder="$rootFS".libdl
[ -z "$cache" ] && rm -rf "$rfsLibdlFolder"
mkdir -p "$rfsLibdlFolder"

if [ ! -s "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext ]; then
	_buildElfDFtextTable $rfsFolder "$libdlDefault" "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext
fi

if [ -n "$libdlApi" ]; then
	#validate requested libdlApi
	comm -12 <(cut -f2- "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext) <(sort -u "$libdlApi") > "$odTCDFtextFolder"/libdlApi
	if [ ! -s "$odTCDFtextFolder"/libdlApi ]; then
		echo "$name# ERROR : libdlApi file \"$libdlApi\" is not valid!" | tee -a "$name".log
		usage
		exit $ERR_OBJ_NOT_VALID
	fi
else
	cut -f2- "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext | sort -u -o "$odTCDFtextFolder"/libdlApi
fi

echo "$name : dlapi   = $(cat "$odTCDFtextFolder"/libdlApi | tr '\n' ' ')" | tee -a "$name".log

startTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`

if [ -n "$elf" ]; then 
	outFile=$(echo "$elf" | tr '/' '%').dlink
else
	outFile=$elfRefs.dlink
fi

if [ -n "$iterLog" ]; then
	iterLog="$outFile".log
	echo "$name : iterLog   = $iterLog" | tee -a "$name".log
else
	iterLog=""
fi

#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name
#: $5 - work folder : $6 - libdl deps : $7 - rdbg folder : $8 - iter log
_rootFSDLinkElfAnalyzer "$rfsFolder" "$elf" "$elfRefs" "$rfsDLinkFolder/$outFile" "$wFolderPfx" "libdl" "$rdbgFolder" "$iterLog"

if [ -s "$outFile".error ]; then
	echo "$name # Warn      : Unresolved reference present! See $outFile.error" | tee -a "$name".log
fi

endTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

