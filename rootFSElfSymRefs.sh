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
	echo "$name# Usage : `basename $0 .sh` [-r folder -e elf -l symlist [-od name]] | [-h]"
	echo "$name# Finds source locations of references to symbols; requires env PATH set to platform tools with objdump"
	echo "$name# -r    : a mandatory rootFS folder"
	echo "$name# -e    : a mandatory target elf (exe/so) object - mutually exclusive with -el"
	echo "$name# -el   : a mandatory target elf (exe/so) object list"
	echo "$name# -s    : a mandatory single symbol - mutually exclusive with -sl"
	echo "$name# -sl   : a mandatory elf symbol list file - mutually exclusive with -s"
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
elfList=
sym=
symList=

while [ "$1" != "" ]; do
	case $1 in
		-r | --root )	shift
				rfsFolder="$1"
				;;
		-e | --elf )	shift
				elf="$1"
				;;
		-el )		shift
				elfList="$1"
				;;
		-sl )		shift
				symList="$1"
				;;
		-s )		shift
				sym="$1"
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

if [ -n "$elf" ] && [ -n "$elfList" ]; then
	echo "$name# ERROR : -e and -el options are mutually exclusive!"
	usage
	exit $ERR_OBJ_NOT_VALID
elif [ -n "$elf" ] && [ ! -e "$rfsFolder"/"$elf" ]; then
	echo "$name# ERROR : elf object \"$rfsFolder/$elf\" is not found!"
	usage
	exit $ERR_PARAM_NOT_SET
elif [ -n "$elfList" ] && [ ! -e "$elfList" ]; then
	echo "$name# ERROR : elf reference file \"$elfList\" is not found!"
	usage
	exit $ERR_PARAM_NOT_SET
elif [ -z "$elf" ] && [ -z "$elfList" ]; then
	echo "$name# ERROR : Either an elf object or elf list options \"-e / -el\" must be set!"
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -n "$elfList" ]; then
	while read entry
	do
		if [ ! -e "$rfsFolder/$entry" ]; then
			echo "$name# ERROR : elf object \"$rfsFolder/$entry\" in the \"$elfList\" list is not found!"
			usage
			exit $ERR_OBJ_NOT_VALID
		fi
	done < "$elfList"
fi

if [ -n "$symList" ] && [ -n "$sym" ]; then
	echo "$name# ERROR : -s and -sl options are mutually exclusive!"
	usage
	exit $ERR_OBJ_NOT_VALID
elif [ -n "$symList" ] && [ ! -e "$symList" ]; then
	echo "$name# ERROR : elf symbol list file \"$symList\" is not found!"
	usage
	exit $ERR_PARAM_NOT_SET
elif [ -z "$sym" ] && [ -z "$symList" ]; then
	echo "$name# ERROR : Either symbol or symbol list file options \"-s / -sl\" must be set!"
	usage
	exit $ERR_PARAM_NOT_SET
fi

# Check paltform
[ -n "$elf" ] && platformFile="$elf" || platformFile="/bin/bash"

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
	echo "$name# Warn  : $rfsFolder/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name"
	rootFS=`basename $rfsFolder`
else
	rootFS=`grep -i "^imagename" $rfsFolder/version.txt |  tr ': =' ':' | cut -d ':' -f2`
fi

echo "$name : rfsFolder  = $rfsFolder"    | tee -a "$name".log
if [ -n "$elf" ]; then 
	echo "$name : elf        = $elf"     | tee -a "$name".log
else
	echo "$name : elfList    = $elfList" | tee -a "$name".log
fi
if [ -n "$sym" ]; then 
	echo "$name : sym        = $sym"     | tee -a "$name".log
else
	echo "$name : symList    = $symList" | tee -a "$name".log
fi
echo "$name : objdump    = $objdump"   | tee -a "$name".log
echo "$name : path       = $path"      | tee -a "$name".log
echo "$name : rootFS     = $rootFS"    | tee -a "$name".log

startTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`

odTCDFUNDFolder="$rootFS".odTC-DFUND
mkdir -p "$odTCDFUNDFolder"

rfsLibdlFolder="$rootFS".libdl
mkdir -p $rfsLibdlFolder

if [ -n "$elf" ] && [ -n "$sym" ]; then
	elfBase=$(echo "$elf" | tr -s '/' '%')

	echo "$elf" > "$elfBase".elf
	echo "$sym" > "$elfBase"."$sym".sym

	elfFile="$elfBase".elf
	symFile="$elfBase"."$sym".sym

elif [ -n "$elf" ] && [ -n "$symList" ]; then
	elfBase=$(echo "$elf" | tr -s '/' '%')

	echo "$elf" > "$elfBase".elf

	elfFile="$elfBase".elf
	#symFile="$symList"
	ln -sf "$symList" $symList.link
	symFile="$symList".link

elif [ -n "$elfList" ] && [ -n "$sym" ]; then

	elfBase="$(basename "$elfList")"
	echo "$sym" > "$elfBase"."$sym".sym

	ln -sf "$elfList" "$elfList".link
	elfFile="$elfList".link
	symFile="$elfBase"."$sym".sym

else	#[ -n "$elfList" ] && [ -n "$symList" ]; then

	elfBase="$(basename "$elfList")"

	ln -sf "$elfList" "$elfList".link
	elfFile="$elfList".link
	ln -sf "$symList" $symList.link
	symFile="$symList".link
fi

pfx=""

# _elfSymRefSources "$_rfsFolder" "$_elf" "$symListFile" "locationBase"
#_elfSymRefSources "$rfsFolder" "$elfFile" "$symFile" "$odTCDFUNDFolder/$elfBase"
_elfSymRefSources "$rfsFolder" "$elfFile" "$symFile" "$odTCDFUNDFolder"/ "$pfx"
if [ -n "$sym" ] || [ -n "$elf" ]; then
	cat "$odTCDFUNDFolder/$elfBase$pfx".log | tee -a "$name".log
else
	cat "$odTCDFUNDFolder/$elfBase$pfx".log >> "$name".log
fi

# cleanup
rm -rf "$elfFile" "$symFile"  #"$odTCDFUNDFolder"/

endTime=`cut -d ' ' -f1 /proc/uptime | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

