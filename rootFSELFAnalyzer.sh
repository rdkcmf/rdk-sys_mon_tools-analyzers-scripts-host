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
# $0 : rootFSELFAnalyzer.sh is a Linux Host based script that analyzes ELF files.

#set -x
#trap read debug

# Variables:
EXE_FILE_PATTERN="ELF .* executable"
EXE_FILE_PATTERN_SUP="ELF 32-bit LSB executable"
SO_FILE_PATTERN="ELF .* shared object"
SO_FILE_PATTERN_SUP="ELF 32-bit LSB shared object"

defaultSkippedSystemLibs="/lib/ld-2.19.so /lib/libc-2.19.so $libdlDefault /lib/libgcc_s.so.1 /lib/libm-2.19.so /lib/libpthread-2.19.so /lib/libresolv-2.19.so \
			/lib/librt-2.19.so /lib/libsystemd.so.0.4.0 /lib/libz.so.1.2.8 /usr/lib/liblzma.so.5.0.99 /lib/libuuid.so.1.3.0 /usr/lib/libbcc.so"

PPMFILESIZEVALIDATE=100		#set to empty "" if needed to validate an entire file

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` -r folder [-e file] [-od name] [-V -psefw file -ppm file] [-o {a|d}] | [-h]"
	echo "$name# Target RootFS ELF objects analyzer, requires env PATH set to platform tools with objdump"
	echo "$name# -r    : a mandatory rootFS folder"
	echo "$name# -rdbg : an optional rootFS dbg folder with ELF symbolic info"
	echo "$name# -ul   : an optional \"used\" file list to analyze instead of default \"all executables\" list"
	echo "$name# -e    : an optional executable file list (in \"ls\" format) to analyze instead of default \"all executables\" list"
	echo "$name# -dlapi: an optional libdl api to verify; default is all \"$libdlDefault\" exposed api"
	echo "$name# -dlink: an optional dynamically linked exe file analysis"
	echo "$name# -dload: an optional dynamically loaded \"libdl dependent\" exe file analysis"
	echo "$name# -nss  : an optional \"name service switch\" exe file analysis"
	echo "$name# -cache: \"use cache\" option; default - cache is not used, all file folders are removed"
	echo "$name# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "$name# -V    : an optional validation mode to verify all shared objs properly dynamically linked to procs: requires -ppm option set"
	echo "$name# -uv   : an optional user validation mode to add/remove/set a list of dloaded lib(s) not ided by the script: requires <folder>/<path%file>.{add|remove|set>"
	echo "$name# -pm   : an optional \"/proc/*/maps\" file of all processes, use \"grep r-xp /proc/*/maps\" to collect it: mandatory when -V is set"
	echo "$name# -pml : a mandatory list of \"/proc/*/maps\" files of all processes, use \"grep r-xp /proc/*/maps\" to collect an instance, mutually exclusive w/ -pm"
	echo "$name# -pmlo: an optional multi- instance \"/proc/*/maps\" files (t) total, (c) common, (s) specific metrics analysis, default -(tc)"
	echo "$name# -skl  : an optional file of shared libraries to skip from dynamic load analysis"
	echo "$name# -o    : an optional output control : a - all | d - default/minimal"
	echo "$name# -h    : display this help and exit"
}

# Function: logFile
# $1: filename	-a file in "ls -la" format
# $2: filedescr	-a file descriptor
# $3: logname	-a log file
function logFile()
{
	if [ -s "$1" ]; then
		awk -v filename="$1" -v filedescr="$2" '{total += $5} END { printf "%-36s : %5d : %10d B / %9.2f KB / %6.2f MB : %s\n", filedescr, NR, total, total/1024, total/(1024*1024), filename}' "$1" | tee -a "$3"
	else
		printf "%-36s : %5d : %10d B / %9.2f KB / %6.2f MB : %s\n" "$2" 0 0 0 0 "$1" | tee -a "$3"
	fi
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
usedFiles=
ignoredFiles=
options=
outputCtr="default/minimal"
findType="-type f"
exeList=
exeExtAnalysis=y
objdump="/usr/bin/objdump"
rtValidation=
ppmFile=
skippedLibsFile=
libdlApi=
dlink=
dload=
nss=
cache=
uvFolder=
usedFiles=
ppmList=
ppmlOpts=tc

while [ "$1" != "" ]; do
	case $1 in
		-r | --root )	shift
				rfsFolder="$1"
				;;
		-rdbg )		shift
				rdbgFolder="$1"
				;;
		-ul )		shift
				usedFiles="$1"
				;;
		-e)		shift
				exeList="$1"
				;;
		-od )		shift
				objdump="$1"
				;;
		-V )		rtValidation=y
				;;
		-uv )		shift
				uvFolder="${1%/}"
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
		-skl)		shift
				skippedLibsFile="$1"
				;;
		-dlink )	dlink=y
				;;
		-dload )	dload=y
				;;
		-nss )		nss=y
				;;
		-dlapi )	shift
				libdlApi="$1"
				;;
		-cache )	cache=y
				;;
		-o )		shift
				options="$1"
				[ "${options#*a}" != "$options" ] && outputCtr="all"
				#[ "${options#*E}" != "$options" ] && exeExtAnalysis=y
				;;
		-h | --help )	usage
				exit
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
	exit $ERR_OBJ_NOT_VALID
fi

if [ -n "$uvFolder" ] && [ ! -d "$uvFolder" ]; then
	echo "$name# ERROR : user validation folder \"$uvFolder\" is set but not found!" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
fi

if [ -n "$usedFiles" ] && [ ! -s "$usedFiles" ]; then
	echo "$name# ERROR : \"used\" file list \"$usedFiles\" is empty or not found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -n "$exeList" ]; then
	if [ ! -s "$exeList" ]; then
		echo "$name# ERROR : executable file list \"$exeList\" is empty or not found!" | tee -a "$name".log
		usage
		exit $ERR_OBJ_NOT_VALID
	fi

	if [ "$(fileFormat "$exeList")" -ne 1 ]; then
		echo "$name# ERROR : executable file list \"$exeList\" is in wrong format!" | tee -a "$name".log
		usage
		exit $ERR_OBJ_NOT_VALID
	fi
fi

if [ -n "$libdlApi" ] && [ ! -e "$libdlApi" ]; then
	echo "$name# ERROR : libdlApi file \"$libdlApi\" is not found!" | tee -a "$name".log
	usage
	exit $ERR_PARAM_NOT_SET
fi

platformFile="/bin/bash"

# Check paltform
platform="$(file -b "$rfsFolder"/"$platformFile" | grep "^ELF ")"
if [ -z "$platform" ]; then
	echo "$name# ERROR  : object \"$rfsFolder/$platformFile\" is NOT an ELF file!" | tee -a "$name".log
	usage
	exit $ERR_OBJ_NOT_VALID
fi

objdumpDefaultNative=
# Check if the $platformFile ELF object architechture is supported
elfArch=$(echo "$platform" | cut -d, -f2)
if [ ! -z "$(echo "$elfArch" | grep "MIPS")" ]; then
	objdumpDefaultNative=mipsel-linux-objdump
elif [ ! -z "$(echo "$elfArch" | grep "Intel .*86")" ]; then
	objdumpDefaultNative=i686-cm-linux-objdump
elif [ ! -z "$(echo "$elfArch" | grep "ARM")" ]; then
	objdumpDefaultNative=armeb-rdk-linux-uclibceabi-objdump
else
	echo "$name# ERROR : \"$platformFile\" object is of unsupported architechture : \"$elfArch\"" | tee -a "$name".log
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
	rootFS=`basename "$rfsFolder"`
else
	rootFS=`grep -i "^imagename" "$rfsFolder"/version.txt |  tr ': =' ':' | cut -d ':' -f2`
fi

if [ -n "$skippedLibsFile" ] && [ ! -e "$skippedLibsFile" ]; then
	echo "$name# ERROR : Skipped Libs File=\"$skippedLibsFile\" doesn't exist!" | tee -a "$name".log
	usage
	exit
fi

if [ -n "$rtValidation" ]; then
	if [ -n "$ppmFile" ] && [ -n "$ppmList" ]; then
		echo "$name# ERROR : -pm and -pmi options are mutually exclusive!" | tee -a "$name".log
		usage
		exit $ERR_OBJ_NOT_VALID
	elif [ -n "$ppmFile" ] && [ ! -e "$ppmFile" ]; then
		echo "$name# ERROR : a mandatory \"/proc/*/maps\" file = \"$ppmFile\" is not set or doesn't exist!" | tee -a "$name".log
		usage
		exit $ERR_OBJ_NOT_VALID
	elif [ -n "$ppmList" ] && [ ! -e "$ppmList" ]; then
		echo "$name# ERROR : a mandatory \"/proc/*/maps\" files list = \"$ppmList\" is not set or doesn't exist!" | tee -a "$name".log
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
			elif [ "$(_ppmFileValid "$entry" "$PPMFILESIZEVALIDATE")" -eq 0 ]; then
				echo error=$?
				echo "$name# ERROR : ppmaps file \"$entry\" in the \"$ppmList\" list is not valid!" | tee -a "$name".log
				usage
				exit $ERR_OBJ_NOT_VALID
			fi
		done < "$ppmList"

		ln -sf "$ppmList" "$rootFS".maps.list
	else
		if [ "$(_ppmFileValid "$ppmFile" "$PPMFILESIZEVALIDATE")" -eq 0 ]; then
			echo "$name# ERROR : ppmaps file \"$ppmFile\" is not valid!" | tee -a "$name".log
			usage
			exit $ERR_OBJ_NOT_VALID
		fi
		echo "$ppmFile" > "$rootFS".maps.list
	fi
fi

echo "$name: rfsFolder   = $rfsFolder" | tee -a "$name".log
echo "$name: rdbgFolder  = $rdbgFolder" | tee -a "$name".log
echo "$name: rootFS      = $rootFS" | tee -a "$name".log
if [ -n "$exeList" ]; then
	echo "$name: exeList     = $exeList" | tee -a "$name".log
fi
echo "$name: objdump     = $objdump" | tee -a "$name".log
if [ -n "$rtValidation" ]; then
	if [ -n "$ppmFile" ]; then
		echo "$name: ppmaps      = $ppmFile" | tee -a "$name".log
	else
		echo "$name: ppmaps list = $ppmList" | tee -a "$name".log
		echo "$name: options     = $ppmlOpts" | tee -a "$name".log
	fi
fi
if [ -n "$uvFolder" ]; then
	echo "$name: uvFolder    = $uvFolder" | tee -a "$name".log
fi
if [ -n "$usedFiles" ]; then
	echo "$name: usedFiles   = $usedFiles" | tee -a "$name".log
fi

echo "$name: path        = $path" | tee -a "$name".log
[ -z "$cache" ] && echo "$name: cache       = no" | tee -a "$name".log || echo "$name: cache       = yes" | tee -a "$name".log
[ -z "$skippedLibsFile" ] && echo "$name: skl         = default" | tee -a "$name".log || echo "$name: skl         = $skippedLibsFile" | tee -a "$name".log

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

if [ -n "$dlink" ] || [ -n "$nss" ] || [ -n "$dload" ]; then
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

	if [ -n "$dload" ]; then
		rfsDLoadFolder="$rootFS".dload
		[ -z "$cache" ] && rm -rf "$rfsDLoadFolder"
		mkdir -p "$rfsDLoadFolder"
	fi

	if [ ! -s "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext ]; then
		_buildElfDFtextTable "$rfsFolder" "$libdlDefault" "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext
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

	echo "$name: libdl       = $libdlDefault" | tee -a "$name".log
	echo "$name: dlapi       = $(cat "$odTCDFtextFolder"/libdlApi | tr '\n' ' ')" | tee -a "$name".log
fi

# create listing of target rootFS on the host
echo "RootFS file list construction:"
sub=${rfsFolder%/}
find "$rfsFolder" \( $findType \) -exec ls -la {} \; | grep -v "\.debug" | tr -s ' ' | sed "s:$sub::" | sort -k9,9 -o "$rootFS".files.all
logFile "$rootFS".files.all "All regular files" "$name".log
find "$rfsFolder" \( $findType \) -exec file {} \; | grep -v "\.debug" | grep "$EXE_FILE_PATTERN\|$SO_FILE_PATTERN" | cut -d ',' -f1 | sed "s:$sub::" > "$rootFS".files.elf.descr
cut -d ':' -f1 "$rootFS".files.elf.descr | sort -o "$rootFS".files.elf.all.short
flsh2lo "$rootFS".files.elf.all.short "$rootFS".files.all "$rootFS".files.elf.all
logFile "$rootFS".files.elf.all "All ELF files" "$name".log

echo "ELF object analysis:" | tee -a "$name".log
phase3StartTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

# find all executable files
grep "$EXE_FILE_PATTERN" "$rootFS".files.elf.descr | cut -d ':' -f1 | sort -o "$rootFS".files.exe.all.short

# find all shared library libraries
grep "$SO_FILE_PATTERN" "$rootFS".files.elf.descr | cut -d ':' -f1 | sort -o "$rootFS".files.so.all.short

if [ -n "$exeExtAnalysis" ]; then
	cat /dev/null > "$rootFS".files.exe-as-so.all.short
	while read filename
	do
		filenameP=$(echo $filename | tr '/' '%')
		if [ ! -s "$odTCDFtextFolder/$filenameP".odTC-DFtext ]; then
			_buildElfDFtextTable "$rfsFolder" "$filename" "$odTCDFtextFolder/$filenameP".odTC-DFtext
			if [ "$?" -ne "0" ]; then
				echo "$name: Error=$? executing \"$objdump -TC $rfsFolder/$filename\". Exit." | tee -a "$name".log
				exit 
			fi
		fi

		main=$(grep "^[[:xdigit:]]\{8\}"$'\t'"main$\|^[[:xdigit:]]\{8\}"$'\t'"\.hidden main$" "$odTCDFtextFolder/$filenameP".odTC-DFtext)

		[ -n "$main" ] && echo "$filename" >> "$rootFS".files.exe-as-so.all.short
	done < "$rootFS".files.so.all.short
	if [ -s "$rootFS".files.exe-as-so.all.short ]; then
		sort "$rootFS".files.exe-as-so.all.short -o "$rootFS".files.exe-as-so.all.short

		# Remove shared objects from the "$rootFS".files.exe-as-so.all.short list
		grep "\.so" "$rootFS".files.exe-as-so.all.short > "$rootFS".files.so.with-main.short
		if [ -s "$rootFS".files.so.with-main.short ]; then
			comm -23 "$rootFS".files.exe-as-so.all.short "$rootFS".files.so.with-main.short > "$rootFS".files.exe-as-so.all.short.tmp
			flsh2lo "$rootFS".files.so.with-main.short "$rootFS".files.all "$rootFS".files.so.with-main

			mv "$rootFS".files.exe-as-so.all.short.tmp "$rootFS".files.exe-as-so.all.short
		fi
		rm "$rootFS".files.so.with-main.short

		# Add "$rootFS".files.exe-as-so.all.short to "$rootFS".files.exe.all.short
		cat "$rootFS".files.exe-as-so.all.short >> "$rootFS".files.exe.all.short
		sort "$rootFS".files.exe.all.short -o "$rootFS".files.exe.all.short
		# Remove "$rootFS".files.exe-as-so.all.short from "$rootFS".files.so.all.short
		comm -23 "$rootFS".files.so.all.short "$rootFS".files.exe-as-so.all.short > "$rootFS".files.so.all.short.tmp
		mv "$rootFS".files.so.all.short.tmp "$rootFS".files.so.all.short

		flsh2lo "$rootFS".files.exe-as-so.all.short "$rootFS".files.all "$rootFS".files.exe-as-so.all

		logFile "$rootFS".files.exe-as-so.all "Executables as shared libraries" "$name".log
		if [ -s "$rootFS".files.so.with-main ]; then
			logFile "$rootFS".files.so.with-main "Shared object with main() files" "$name".log
		fi
	fi
	# Cleanup
	rm "$rootFS".files.exe-as-so.all.short
fi

flsh2lo "$rootFS".files.exe.all.short "$rootFS".files.all "$rootFS".files.exe.all
flsh2lo "$rootFS".files.so.all.short "$rootFS".files.all "$rootFS".files.so.all

# all/used/unused executables
logFile "$rootFS".files.exe.all "All executable files" "$name".log
logFile "$rootFS".files.so.all "All shared libraries" "$name".log

if [ -n "$usedFiles" ]; then
	echo "User used files analysis:" | tee -a "$name".log

	usedFiles=$(flslfilter "$usedFiles")
	nf2=$(fileFormat $usedFiles)
	if [ "$nf2" -ne 1 ]; then
		cat "$usedFiles" | tr -s ' ' | cut -d ' ' -f${nf2}- | sort -u -o "$usedFiles".short
	else
		sort -u "$usedFiles" -o "$usedFiles".short
	fi

	# find missing files within the used
	fllo2sh "$rootFS".files.all "$rootFS".files.all.short
	comm -23 "$usedFiles".short "$rootFS".files.all.short > "$usedFiles".missing.short

	# find used elf files
	comm -12 "$usedFiles".short "$rootFS".files.elf.all.short > "$usedFiles".files.elf.used.short
	flsh2lo "$usedFiles".files.elf.used.short "$rootFS".files.elf.all "$usedFiles".files.elf.used

	# find unused elf files
	comm -13 "$usedFiles".files.elf.used.short "$rootFS".files.elf.all.short > "$usedFiles".files.elf.unused.short
	flsh2lo "$usedFiles".files.elf.unused.short "$rootFS".files.elf.all "$usedFiles".files.elf.unused

	# find used executable files
	comm -12 "$usedFiles".short "$rootFS".files.exe.all.short > "$rootFS".files.exe.used.short
	flsh2lo "$rootFS".files.exe.used.short "$rootFS".files.exe.all "$rootFS".files.exe.used

	# find unused executable files
	comm -13 "$rootFS".files.exe.used.short "$rootFS".files.exe.all.short > "$rootFS".files.exe.unused.short
	flsh2lo "$rootFS".files.exe.unused.short "$rootFS".files.exe.all "$rootFS".files.exe.unused

	# find used shared libraries
	comm -12 "$usedFiles".short "$rootFS".files.so.all.short > "$rootFS".files.so.used.short
	flsh2lo "$rootFS".files.so.used.short "$rootFS".files.so.all "$rootFS".files.so.used

	# find unused shared libraries
	comm -13 "$rootFS".files.so.used.short "$rootFS".files.so.all.short > "$rootFS".files.so.unused.short
	flsh2lo "$rootFS".files.so.unused.short "$rootFS".files.so.all "$rootFS".files.so.unused

	# missing used files if any
	if [ -n "$usedFiles" ]; then
		#[ -s "$usedFiles".missing.short ] && echo "$name# Warn  : There are missing files in \"$usedFiles\" : $usedFiles.missing.short" | tee -a "$name".log
		[ -s "$usedFiles".missing.short ] && _logFileShort "$usedFiles".missing.short "$name# Warn  : Missing files" "$name".log

	fi

	[ -s "$rootFS".files.exe.used ] && logFile "$rootFS".files.exe.used "Used executable files" "$name".log
	[ -s "$rootFS".files.exe.unused ] && logFile "$rootFS".files.exe.unused "Unused executable files" "$name".log
	[ -s "$rootFS".files.so.used ] && logFile "$rootFS".files.so.used "Used shared libraries" "$name".log
	[ -s "$rootFS".files.so.unused ] && logFile "$rootFS".files.so.unused "Unused shared libraries" "$name".log

fi

if [ -n "$exeList" ]; then
	cat /dev/null > "$exeList".short
	comm "$rootFS".files.exe.all.short <(sort -u "$exeList") | awk -F$'\t' -v file="$exeList" '{\
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
	ln -sf "$exeList".short "$rootFS".files.elf.analyze.short
else
	ln -sf "$rootFS".files.exe.all.short "$rootFS".files.elf.analyze.short
fi

if [ -n "$dlink" ] || [ -n "$nss" ] || [ -n "$dload" ]; then
	echo "Dynamically linked shared object analysis:" | tee -a "$name".log

	# ELF dlapi identification
	cat /dev/null > "$rootFS".files.elf.dlapi.all.short
	cat /dev/null > "$rootFS".files.elf.dlapi.table
	while read filename
	do
		outFile=$(echo "$filename" | tr '/' '%').odTC-DFUND
		_buildElfDFUNDtTable "$rfsFolder" "$filename" "$odTCDFUNDFolder/$outFile"
		dlapi=$(comm -12 "$odTCDFtextFolder"/libdlApi "$odTCDFUNDFolder/$outFile" | tr '\n' ' ')
		if [ -n "$dlapi" ]; then
			echo $filename >> "$rootFS".files.elf.dlapi.all.short
			printf "%s\t%s\n" "$filename" "$dlapi" >> "$rootFS".files.elf.dlapi.table
		fi
	done < "$rootFS".files.elf.all.short
	sort "$rootFS".files.elf.dlapi.all.short -o "$rootFS".files.elf.dlapi.all.short
	sort -t$'\t' -k1,1 "$rootFS".files.elf.dlapi.table -o "$rootFS".files.elf.dlapi.table

	# Find all elf (exe/so) files containing libdl api calls
	flsh2lo "$rootFS".files.elf.dlapi.all.short "$rootFS".files.elf.all "$rootFS".files.elf.dlapi.all

	# Find all exe files containing libdl api calls
	comm -12 "$rootFS".files.elf.dlapi.all.short "$rootFS".files.exe.all.short > "$rootFS".files.exe.dlapi.all.short
	flsh2lo "$rootFS".files.exe.dlapi.all.short "$rootFS".files.exe.all "$rootFS".files.exe.dlapi.all

	# Find all so files containing libdl api calls
	comm -12 "$rootFS".files.elf.dlapi.all.short "$rootFS".files.so.all.short > "$rootFS".files.so.dlapi.all.short
	flsh2lo "$rootFS".files.so.dlapi.all.short "$rootFS".files.so.all "$rootFS".files.so.dlapi.all

	# Dynamically linked shared libraries analysis
	while read filename
	do
		outFile=$(echo "$filename" | tr '/' '%').dlink
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name 
		# : $5 - work folder : $6 - libdl deps : $7 - rootFS dbg folder : $8 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "$filename" "" "$rfsDLinkFolder/$outFile" "" "libdl" "$rdbgFolder" ""
	done < "$rootFS".files.elf.analyze.short

	sort -u "$rfsDLinkFolder"/*.dlink -o "$rootFS".files.so.dlink.short

	#_soRefedByApp $_folder $_elfFileList $_log $_ext
	_soRefedByApp "$rfsDLinkFolder" "$rootFS".files.so.dlapi.all.short "$rootFS".files.so.dlapi.all.log ".dlink"

	#_soRefedByApp $_folder $_elfFileList $_log $_ext
	_soRefedByApp "$rfsDLinkFolder" "$rootFS".files.so.dlink.short "$rootFS".files.so.dlink.log ".dlink"

	# Find exe files dynamically linked with libdl directly/indirectly
	find "$rfsDLinkFolder" -name "*.dlink.libdl" -size +0 | sed "s:^$rfsDLinkFolder/::;s:%:/:g;s:\.dlink.libdl::" | sort -o "$rootFS".files.exe.dlink-libdl.short
	flsh2lo "$rootFS".files.exe.dlink-libdl.short "$rootFS".files.exe.all "$rootFS".files.exe.dlink-libdl

	# Find elf (exe/so) files dynamically linked with libdl directly
	find "$rfsDLinkFolder" -name "*.dlink.libdl" -size +0 -exec cat {} \; | sort -u -o "$rootFS".files.elf.dlink-libdld.short
	flsh2lo "$rootFS".files.elf.dlink-libdld.short "$rootFS".files.elf.all "$rootFS".files.elf.dlink-libdld

	# Find elf (exe/so) files dynamically linked with libdl directly, but do not contain libdl api calls
	grep "^/.*:"$'\t'"none" "$rfsLibdlFolder"/*.dlink.libdl.log | cut -d ':' -f2 | sed 's/ *$//' | sort -u -o "$rootFS".files.elf.dlink-libdld.no-dlapi.short
	flsh2lo "$rootFS".files.elf.dlink-libdld.no-dlapi.short "$rootFS".files.elf.all "$rootFS".files.elf.dlink-libdld.no-dlapi

	#Find elf (exe/so) files dynamically linked with libdl directly and contain libdl api calls
	comm -23 "$rootFS".files.elf.dlink-libdld.short "$rootFS".files.elf.dlink-libdld.no-dlapi.short > "$rootFS".files.elf.dlink-libdld.dlapi.short
	flsh2lo "$rootFS".files.elf.dlink-libdld.dlapi.short "$rootFS".files.elf.all "$rootFS".files.elf.dlink-libdld.dlapi

	#Split "$rootFS".files.elf.dlink-libdld.dlapi.short on exe and so
	cat /dev/null > "$rootFS".files.exe.dlink-libdld.dlapi.short
	cat /dev/null > "$rootFS".files.so.dlink-libdld.dlapi.short
	comm -1 "$rootFS".files.exe.all.short "$rootFS".files.elf.dlink-libdld.dlapi.short | awk -F$'\t' -v file="$rootFS".files '{\
		if (NF == 2) {\
			printf("%s\n", $2) > file".exe.dlink-libdld.dlapi.short"
		} else if (NF == 1) {\
			printf("%s\n", $1) > file".so.dlink-libdld.dlapi.short"
		}\
		}'
	flsh2lo "$rootFS".files.exe.dlink-libdld.dlapi.short "$rootFS".files.elf.all "$rootFS".files.exe.dlink-libdld.dlapi
	flsh2lo "$rootFS".files.so.dlink-libdld.dlapi.short "$rootFS".files.elf.all "$rootFS".files.so.dlink-libdld.dlapi

	# Find exe files dynamically linked with libdl and containing libdl api calls
	cat /dev/null > "$rootFS".files.exe.dlink-libdl.dlapi.short
	while read filename
	do
		outFile=$(echo "$filename" | tr '/' '%').dlink
		if [ -n "$(comm -12 "$rootFS".files.so.dlapi.all.short "$rfsDLinkFolder/$outFile")" ]; then
			echo "$filename" >> "$rootFS".files.exe.dlink-libdl.dlapi.short
		fi
	done < "$rootFS".files.exe.dlink-libdl.short
	sort -u "$rootFS".files.exe.dlink-libdld.dlapi.short "$rootFS".files.exe.dlink-libdl.dlapi.short -o "$rootFS".files.exe.dlink-libdl.dlapi.short.tmp
	mv "$rootFS".files.exe.dlink-libdl.dlapi.short.tmp "$rootFS".files.exe.dlink-libdl.dlapi.short
	flsh2lo "$rootFS".files.exe.dlink-libdl.dlapi.short "$rootFS".files.exe.all "$rootFS".files.exe.dlink-libdl.dlapi

	#_soRefedByApp $_folder $_elfFileList $_log $_ext
	_soRefedByApp "$rfsDLinkFolder" "$rootFS".files.so.dlink-libdld.dlapi.short "$rootFS".files.so.dlink-libdld.dlapi.log ".dlink"

	flsh2lo "$rootFS".files.so.dlink.short "$rootFS".files.so.all "$rootFS".files.so.dlink

	cat /dev/null > "$rootFS".files.so.unrefed.dlink-libdld.dlapi
	cat /dev/null > "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short
	if [ -z "$exeList" ]; then
		# Dynamically linked unreferenced shared libraries analysis
		# build "$rootFS".files.so.unrefed
		comm -13 "$rootFS".files.so.dlink.short "$rootFS".files.so.all.short > "$rootFS".files.so.unrefed.short
		flsh2lo "$rootFS".files.so.unrefed.short "$rootFS".files.so.all "$rootFS".files.so.unrefed

		while read filename
		do
			outFile=$(echo "$filename" | tr '/' '%').dlink
			#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name
			# : $5 - work folder : $6 - libdl deps : $7 - rootFS dbg folder : $8 - iter log
			_rootFSDLinkElfAnalyzer "$rfsFolder" "$filename" "" "$rfsDLinkUnrefedSoFolder/$outFile" "" "libdl" "$rdbgFolder" ""
		done < "$rootFS".files.so.unrefed.short

		# Find unrefed shared libraries dynamically linked with libdl directly/indirectly
		find "$rfsDLinkUnrefedSoFolder" -name "*.dlink.libdl" -size +0 | sed "s:^$rfsDLinkUnrefedSoFolder/::;s:%:/:g;s:\.dlink.libdl::" | sort -o "$rootFS".files.so.unrefed.dlink-libdl.short
		flsh2lo "$rootFS".files.so.unrefed.dlink-libdl.short "$rootFS".files.so.all "$rootFS".files.so.unrefed.dlink-libdl

		# Find unrefed shared libraries dynamically linked with libdl directly
		# (remove exe referenced shared libs)
		comm -13 "$rootFS".files.so.dlink.short <(find "$rfsDLinkUnrefedSoFolder" -name "*.dlink.libdl" -size +0 -exec cat {} \; | sort -u) > "$rootFS".files.so.unrefed.dlink-libdld.short
		flsh2lo "$rootFS".files.so.unrefed.dlink-libdld.short "$rootFS".files.so.all "$rootFS".files.so.unrefed.dlink-libdld

		# Find all refed/unrefed exe/so dlink libdld no-dlapi elfs (dlinked with libdl not containing any dlapi calls)
		grep "^/.*:"$'\t'"none" "$rfsLibdlFolder"/*.dlink.libdl.log | cut -d ':' -f2 | sed 's/ *$//' | sort -u -o "$rootFS".files.elf.dlink-libdld.no-dlapi.all.short
		flsh2lo "$rootFS".files.elf.dlink-libdld.no-dlapi.all.short "$rootFS".files.elf.all "$rootFS".files.elf.dlink-libdld.no-dlapi.all

		# Find unrefed (exe/so) dlink libdld no-dlapi elfs
		comm -23 "$rootFS".files.elf.dlink-libdld.no-dlapi.all.short "$rootFS".files.elf.dlink-libdld.no-dlapi.short > "$rootFS".files.so.unrefed.dlink-libdld.no-dlapi.short
		flsh2lo "$rootFS".files.so.unrefed.dlink-libdld.no-dlapi.short "$rootFS".files.elf.all "$rootFS".files.so.unrefed.dlink-libdld.no-dlapi

		#Find unrefed shared libraries dynamically linked with libdl directly and contain libdl api calls
		comm -23 "$rootFS".files.so.unrefed.dlink-libdld.short "$rootFS".files.so.unrefed.dlink-libdld.no-dlapi.short > "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short
		flsh2lo "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short "$rootFS".files.so.all "$rootFS".files.so.unrefed.dlink-libdld.dlapi

		# cleanup
		rm -f "$rootFS".files.elf.dlink-libdld.no-dlapi.all.short
	fi

	# Cleanup
	find $rfsDLinkFolder -maxdepth 1 -size 0 -exec rm {} \;
	find $rfsDLinkUnrefedSoFolder -maxdepth 1 -size 0 -exec rm {} \;
	find $odTCDFUNDFolder -maxdepth 1 -size 0 -exec rm {} \;
fi

if [ -n "$dlink" ] || [ -n "$nss" ] || [ -n "$dload" ]; then
	### Dynamically linked shared libraries analysis
	# refed/unrefed shared library objects
	[ -s "$rootFS".files.so.dlink ] && logFile "$rootFS".files.so.dlink "Dynamically linked shared libraries" "$name".log
	printf "%-86s : %s\n" "Dynamically linked shared libraries referenced by applications" "$rootFS".files.so.dlink.log | tee -a $name.log

	# exe files dynamically linked with libdl directly/indirectly
	[ -s "$rootFS".files.exe.dlink-libdl ] && logFile "$rootFS".files.exe.dlink-libdl "exes dlinked with libdl" "$name".log

	# elf (exe/so) files dynamically linked with libdl directly
	[ -s "$rootFS".files.elf.dlink-libdld ] && logFile "$rootFS".files.elf.dlink-libdld "elfs dlinked with libdl directly" "$name".log

	# elf (exe/so) files dynamically linked with libdl directly and not containing libdl api calls
	[ -s "$rootFS".files.elf.dlink-libdld.no-dlapi ] && logFile "$rootFS".files.elf.dlink-libdld.no-dlapi "elfs dlinked with libdld, no dlapi" "$name".log

	# elf (exe/so) files dynamically linked with libdl directly and containing libdl api calls
	[ -s "$rootFS".files.elf.dlink-libdld.dlapi ] && logFile "$rootFS".files.elf.dlink-libdld.dlapi "elfs dlinked with libdld, dlapi" "$name".log

	# exe files dynamically linked with libdl directly and containing libdl api calls
	[ -s "$rootFS".files.exe.dlink-libdld.dlapi ] && logFile "$rootFS".files.exe.dlink-libdld.dlapi "exes dlinked with libdld, dlapi" "$name".log

	# so files dynamically linked with libdl directly and containing libdl api calls
	[ -s "$rootFS".files.so.dlink-libdld.dlapi ] && logFile "$rootFS".files.so.dlink-libdld.dlapi "libs dlinked with libdld, dlapi" "$name".log

	# exe files dynamically linked with libdl and containing libdl api calls
	[ -s "$rootFS".files.exe.dlink-libdl.dlapi ] && logFile "$rootFS".files.exe.dlink-libdl.dlapi "exes dlinked with libdl, dlapi" "$name".log

	printf "%-86s : %s\n" "libs dlinked with libdl, dlapi - referenced by applications" "$rootFS".files.so.dlink-libdld.dlapi.log | tee -a $name.log

	if [ -z "$exeList" ]; then
		### Dynamically linked unreferenced shared libraries analysis
		[ -s "$rootFS".files.so.unrefed ] && logFile "$rootFS".files.so.unrefed "Unreferenced shared libraries" "$name".log

		# unrefed shared libraries dynamically linked with libdl directly/indirectly
		[ -s "$rootFS".files.so.unrefed.dlink-libdl ] && logFile "$rootFS".files.so.unrefed.dlink-libdl "unrefed libs libdl dlinked" "$name".log

		# unrefed shared libraries dynamically linked with libdl directly
		[ -s "$rootFS".files.so.unrefed.dlink-libdld ] && logFile "$rootFS".files.so.unrefed.dlink-libdld "unrefed libs libdl dlinked directly" "$name".log

		# unrefed shared libraries dynamically linked with libdl directly and not containing libdl api calls
		[ -s "$rootFS".files.so.unrefed.dlink-libdld.no-dlapi ] && logFile "$rootFS".files.so.unrefed.dlink-libdld.no-dlapi "unrefed libs libdl dlinked, no dlapi" "$name".log

		# unrefed shared libraries dynamically linked with libdl directly and containing libdl api calls
		[ -s "$rootFS".files.so.unrefed.dlink-libdld.dlapi ] && logFile "$rootFS".files.so.unrefed.dlink-libdld.dlapi "unrefed libs libdl dlinked, dlapi" "$name".log

		# all elf (exe/so) files dynamically linked with libdl directly and not containing libdl api calls
		[ -s "$rootFS".files.elf.dlink-libdld.no-dlapi.all ] && logFile "$rootFS".files.elf.dlink-libdld.no-dlapi.all "All elfs libdl dlinked, no dlapi" "$name".log

		# all elf (exe/so) files containing libdl api calls
		[ -s "$rootFS".files.elf.dlapi.all ] && logFile "$rootFS".files.elf.dlapi.all "All elfs, dlapi" "$name".log

		# all exe files containing libdl api calls
		[ -s "$rootFS".files.exe.dlapi.all ] && logFile "$rootFS".files.exe.dlapi.all "All execs, dlapi" "$name".log

		# all libs files containing libdl api calls
		[ -s "$rootFS".files.so.dlapi.all ] && logFile "$rootFS".files.so.dlapi.all "All libs, dlapi" "$name".log
	fi

	printf "%-86s : %s\n" "dlapi libs - referenced by applications" "$rootFS".files.so.dlapi.all.log | tee -a $name.log
fi

if [ -n "$dload" ]; then
	### Dynamically loaded shared libraries analysis
	echo "Dynamically loaded shared object analysis:" | tee -a "$name".log

	rfsSymsFolder="$rootFS".symbs
	[ -z "$cache" ] && rm -rf $rfsSymsFolder
	mkdir -p $rfsSymsFolder

	wFolderPfx=.
	if [ -n "$wFolder" ]; then
		wFolderPfx=$(echo "$wFolder" | tr -s '/')
		if [ "$wFolderPfx" != "." ] && [ "$wFolderPfx" != "./" ] ; then
			rm -rf "$wFolderPfx"
			mkdir -p "$wFolderPfx"
		fi
	fi

	[ ! -e "$rootFS".files.exe.dlink-libdl.dlapi.short ] && fllo2sh "$rootFS".files.exe.dlink-libdl.dlapi "$rootFS".files.exe.dlink-libdl.dlapi.short

	ln -sf "$rootFS".files.exe.dlink-libdl.dlapi.short "$rootFS".files.exe.dlapi.link
	if [ -n "$uvFolder" ]; then
		# User validation
		ls "$uvFolder"/*.uv.set 2>/dev/null | sed "s:$uvFolder/::;s:.uv.set::;s:%:/:g" | sort -o "$uvFolder".set	#set
		ls "$uvFolder"/*.uv.add 2>/dev/null | sed "s:$uvFolder/::;s:.uv.add::;s:%:/:g" | sort -o "$uvFolder".add	#add
		ls "$uvFolder"/*.uv.del 2>/dev/null | sed "s:$uvFolder/::;s:.uv.del::;s:%:/:g" | sort -o "$uvFolder".del	#delete
		ls "$uvFolder"/*.uv.ldp 2>/dev/null | sed "s:$uvFolder/::;s:.uv.ldp::;s:%:/:g" | sort -o "$uvFolder".ldp	#ld_preload
		if [ -s "$uvFolder".set ]; then
			# "$uvFolder"/*.uv.set uv settings completely override those identified by the script:
			# Remove non libdl api dependent execs from the "$uvFolder".set execs
			comm -12 "$rootFS".files.exe.dlink-libdl.dlapi.short "$uvFolder".set > "$uvFolder".exe.set
			# Extract libdl api libs from "$uvFolder".set
			comm -12 "$rootFS".files.so.dlapi.all.short "$uvFolder".set > "$uvFolder".so.set

			# validate user input
			comm -13 <(sort "$uvFolder".exe.set "$uvFolder".so.set) "$uvFolder".set > "$uvFolder".set.no-dlapi-elfs
			if [ -s "$uvFolder".set.no-dlapi-elfs ]; then
				echo "$name# Warn  : \"$uvFolder\" folder contains not libdl api dependent elfs! See \"$uvFolder.set.no-dlapi-elfs\"" | tee -a "$name".log
			fi
		fi
		if [ -s "$uvFolder".add ] || [ -s "$uvFolder".del ]; then
			# "$uvFolder"/*.uv.add/.del uv settings complement those identified by the script
			cat /dev/null > "$uvFolder".ads
			[ -s "$uvFolder".add ] && cat "$uvFolder".add >> "$uvFolder".ads
			[ -s "$uvFolder".del ] && cat "$uvFolder".del >> "$uvFolder".ads
			if [ -s "$uvFolder".ads ]; then
				sort -u "$uvFolder".ads -o "$uvFolder".ads
				if [ -n "$exeList" ]; then
					# Strip off all non $exeList execs from the "$uvFolder".ads
					comm -12 <(sort "$rootFS".files.exe.dlink-libdl.dlapi.short "$rootFS".files.so.dlapi.all.short) "$uvFolder".ads > "$uvFolder".ads.tmp
					mv "$uvFolder".ads.tmp "$uvFolder".ads
				fi
				# Remove non libdl api dependent execs from the "$uvFolder".ads execs
				comm -12 "$rootFS".files.exe.dlink-libdl.dlapi.short "$uvFolder".ads > "$uvFolder".exe.ads
				# Extract libdl api libs from "$uvFolder".ads
				comm -12 "$rootFS".files.so.dlapi.all.short "$uvFolder".ads > "$uvFolder".so.ads

				# validate user input
				sort "$uvFolder".exe.ads "$uvFolder".so.ads -o "$uvFolder".elf.ads
				comm -13 "$uvFolder".elf.ads "$uvFolder".ads > "$uvFolder".ads.no-dlapi-elfs
				if [ -s "$uvFolder".ads.no-dlapi-elfs ]; then
					echo "$name# Warn  : \"$uvFolder\" folder contains not libdl api dependent elfs! See \"$uvFolder.ads.no-dlapi-elfs\"" | tee -a "$name".log
				fi

				mv "$uvFolder".elf.ads "$uvFolder".ads
			fi
		fi
		if [ -s "$uvFolder".ldp ]; then
			# "$uvFolder"/*.uv.ldp uv settings add LD_PRELOADed libs to execs:
			# Remove non related execs from the "$uvFolder".ldp
			comm -12 "$rootFS".files.exe.all.short "$uvFolder".ldp > "$uvFolder".ldp.exe
			mv "$uvFolder".ldp.exe "$uvFolder".ldp

			# Split "$uvFolder".ldp on libdl api dependent / not libs, if any
			if [ -s "$uvFolder".ldp ]; then
				while read exe
				do
					exeP=$(echo "$exe" | tr '/' '%')
					if [ -s $uvFolder/$exeP.uv.ldp ]; then
						comm -1 "$rootFS".files.so.dlapi.all.short <(sort $uvFolder/$exeP.uv.ldp) | awk -F'\t' -v base="$uvFolder/$exeP".uv.ldp '{\
						if (NF == 2) {\
							printf("%s\n", $2) > base".dlapi"
						} else if (NF == 1) {\
							printf("%s\n", $1) > base".nodlapi"
						}\
						}'
						[ -s $uvFolder/$exeP.uv.ldp.dlapi ] && sort -u $uvFolder/$exeP.uv.ldp.dlapi -o $uvFolder/$exeP.uv.ldp.dlapi
						[ -s $uvFolder/$exeP.uv.ldp.nodlapi ] && sort -u $uvFolder/$exeP.uv.ldp.nodlapi -o $uvFolder/$exeP.uv.ldp.nodlapi
					fi
				done < "$uvFolder".ldp
			fi
		fi

		# Check uv for mutually exclusive uv settings set via .set & .ads extensions
		for elf in "exe" "so"
		do
			if [ -s "$uvFolder.$elf".set ] && [ -s "$uvFolder.$elf".ads ]; then
				#comm -12 "$uvFolder.$elf".set "$uvFolder.$elf".ads | sed "s:/:%:g;s:$:.uv.$elf.set/.add/.del:" > "$uvFolder.$elf".conflicts
				ls "$uvFolder"/*.uv.* 2>/dev/null | grep -f <(comm -12 "$uvFolder".exe.set "$uvFolder".exe.ads | sed "s:/:%:g;s:$:.uv.*:") > "$uvFolder.$elf".conflicts
				if [ -s "$uvFolder.$elf".conflicts ]; then
					echo "$name# ERROR : \"$uvFolder\" folder contains mutually exclusive uv settings! See \"$uvFolder.$elf.conflicts\". Exit." | tee -a "$name".log
					# Cleanup
					find ./ -maxdepth 1 -name "$uvFolder.*" ! -name "$uvFolder.$elf".conflicts -size 0 -exec rm {} \;
					exit $ERR_OBJ_NOT_VALID
				fi
			fi
		done

		if [ -s "$uvFolder".exe.set ]; then
			# "$uvFolder"/*.uv.set uv settings completely override those identified by the script:
			# Remove the "$uvFolder".exe.set execs from the "$rootFS".files.exe.dlink-libdl.dlapi.short
			#comm -23 "$rootFS".files.exe.dlink-libdl.dlapi.short "$uvFolder".exe.set > "$rootFS".files.exe.dlink-libdl.dlapi.uv.short
			# and set a link to the list of dlapi execs to analyze
			#ln -sf "$rootFS".files.exe.dlink-libdl.dlapi.uv.short "$rootFS".files.exe.dlapi.link
			ln -sf "$uvFolder".exe.set "$rootFS".files.exe.dlapi.link
		fi

		# Cleanup
		find ./ -maxdepth 1 -name "$uvFolder.*" -size 0 -exec rm {} \;
	fi

	iter=1
	cat /dev/null > "$rootFS".files.exe.dlink-libdl.dlapi.parsed
	[ -s "$uvFolder".set ] && uvelfset="$uvFolder".set || uvelfset=
	[ -s "$uvFolder".ads ] && uvelfads="$uvFolder".ads || uvelfads=
	[ -s "$uvFolder".ldp ] && uvldp="$uvFolder".ldp || uvldp=
	while read dlapiExe
	do
		printf "%-2d: dlapiExe = %s\n" "$iter" "$dlapiExe" | tee -a "$name".log
		outFile=$(echo "$dlapiExe" | tr '/' '%')
		# _rootFSDLoadElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name : $3 - output file name : $4 - work folder : $5 - rootFS dbg folder 
		# : $6 - uv so set : $7 - uv so ads : $8 uv ldp exe
		_rootFSDLoadElfAnalyzer "$rfsFolder" "$dlapiExe" $outFile "$wFolderPfx" "$rdbgFolder" "$uvelfset" "$uvelfads" "$uvldp"

		printf "%s:\n" "$dlapiExe" >> "$rootFS".files.exe.dlink-libdl.dlapi.parsed
		# log parsed execs along with dependent libdl api libs
		if [ -s "$rfsDLoadFolder/$outFile".dlink.dlapi.parsed ]; then
			sed 's/^/\t/' "$rfsDLoadFolder/$outFile".dlink.dlapi.parsed >> "$rootFS".files.exe.dlink-libdl.dlapi.parsed
		else
			echo "" >> "$rootFS".files.exe.dlink-libdl.dlapi.parsed
		fi

		((iter++))
	done < "$rootFS".files.exe.dlapi.link

	# Find and log libdl api dlopen & dlsym methods source code references:
	find "$odTCDFUNDFolder"/*.usr.dlopen -type f -printf '%p:\n' -exec sed 's:^:\t:' {} \; > "$rootFS".files.elf.dlopen.log
	find "$odTCDFUNDFolder"/*.usr.dlsym  -type f -printf '%p:\n' -exec sed 's:^:\t:' {} \; > "$rootFS".files.elf.dlsym.log
	printf "%-86s : %s\n" "libdl dlopen api libs referenced by elfs" "$rootFS".files.elf.dlopen.log | tee -a $name.log
	printf "%-86s : %s\n" "libdl dlsym  api libs referenced by elfs" "$rootFS".files.elf.dlsym.log | tee -a $name.log

	#Cleanup
	rm -f "$rfsDLoadFolder"/*.dlink.dlapi.parsed "$rootFS".files.exe.dlapi.link
	find $rfsSymsFolder -maxdepth 1 -size 0 -exec rm {} \;
fi

if [ -e "$rfsFolder"/etc/nsswitch.conf ]; then
	echo "NSS dynamically loaded shared object analysis:" | tee -a "$name".log

	rfsNssFolder="$rootFS".nss
	[ -z "$cache" ] && rm -rf "$rfsNssFolder"
	mkdir -p "$rfsNssFolder"

	_rootFSBuildNssCache "$rfsFolder"

	printf "%-36s : %5d : %*c : %s\n" "All NSS services" $(wc -l "$rfsNssFolder"/nss.services | cut -d ' ' -f1) 39 " " "$rfsNssFolder"/nss.services | tee -a "$name".log
	if [ -s "$rfsNssFolder"/nss.short ]; then
		# Find nss.short library dlink dependencies
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name
		# : $5 - work folder : $6 - libdl deps : $7 - rootFS dbg folder : $8 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "" "$rfsNssFolder"/nss.short "$rfsNssFolder"/nss.dlink "$rfsNssFolder" "" "$rdbgFolder" ""
		mv "$rfsNssFolder"/nss.dlink "$rfsNssFolder"/nss.dlink.short

		flsh2lo "$rfsNssFolder"/nss.short "$rootFS".files.so.all "$rfsNssFolder"/nss
		flsh2lo "$rfsNssFolder"/nss.dlink.short "$rootFS".files.so.all "$rfsNssFolder"/nss.dlink

		logFile "$rfsNssFolder"/nss "Found NSS shared libraries" "$name".log
		logFile "$rfsNssFolder"/nss.dlink "NSS shared libraries & deps " "$name".log
		if [ -s "$rootFS".files.so.unrefed ]; then
			join -j 9 "$rfsNssFolder"/nss.dlink "$rootFS".files.so.unrefed -o 1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9 > "$rfsNssFolder"/nss.non-redundant
			logFile "$rfsNssFolder"/nss.non-redundant "NSS added non redundant shared objs" "$name".log
		fi
	fi

	if [ -s "$rfsNssFolder"/nss.not-found ]; then
		printf "%-36s : %5d : %*c : %s\n" "Not found NSS shared libraries" $(wc -l "$rfsNssFolder"/nss.not-found | cut -d ' ' -f1) 39 " " ""$rfsNssFolder"/nss.not-found" | tee -a "$name".log
	fi

	if [ -n "$nss" ]; then
		#iter=1
		while read exe
		do
			#printf "%-2d: exe = %s\n" "$iter" "$exe"
			exeP=$(echo "$exe" | tr '/' '%')
			# _rootFSNssElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name : $3 - output file name base : $4 - rdbg folder : $5 - list of ELFs : $6 - list of DL ELFs
			_rootFSNssElfAnalyzer "$rfsFolder" "$exe" "$rfsNssFolder/$exeP" "$rdbgFolder" "" ""
			#((iter++))
		done < "$rootFS".files.elf.analyze.short

		if [ -n "$uvFolder" ]; then
			while read exe
			do
				exeP=$(echo "$exe" | tr '/' '%')
				[ ! -s "$rfsDLoadFolder/$exeP".dload.all ] && continue
				# Skip NSS analysis if all NSS based files are already part of the executable $exe
				[ -z "$(comm -13 "$rfsNssFolder/$exeP".nss "$rfsNssFolder"/nss.short)" ] && continue

				# Skip NSS analysis if an executable doesn't have any dloaded and user validated added files
				[ ! -s "$rfsDLoadFolder/$exeP".dload+dlink.all ] && continue
				# Skip NSS analysis for already analyzed dlink files
				comm -23 "$rfsDLoadFolder/$exeP".dload+dlink.all "$rfsDLinkFolder/$exeP".dlink > "$rfsNssFolder/$exeP".uvdl
				# Skip NSS analysis if there is nothing to analyze
				[ ! -s "$rfsNssFolder/$exeP".uvdl ] && continue

				# Do NSS analysis of dloaded and user validated added files & their dlink deps for an executable $exe
				# _rootFSNssElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name : $3 - output file name base : $4 - rdbg folder : $5 - list of ELFs : $6 - list of DL ELFs
				_rootFSNssElfAnalyzer "$rfsFolder" "" "$rfsNssFolder/$exeP".uvdl "$rdbgFolder" "" "$rfsNssFolder/$exeP".uvdl

			done < "$rootFS".files.elf.analyze.short
		fi
	fi

	# Cleanup
	rm -f "$rfsNssFolder"/nss.short "$rfsNssFolder"/nss.dlink.short
	find $rfsNssFolder -maxdepth 1 -size 0 -exec rm {} \;
fi

if [ -n "$dlink" ] && [ -n "$nss" ] && [ -n "$dload" ]; then

	rfsElfFolder="$rootFS".elf
	[ -z "$cache" ] && rm -rf "$rfsElfFolder"
	mkdir -p "$rfsElfFolder"

	while read exe
	do
		exeP=$(echo "$exe" | tr '/' '%')
		echo "$exe" > "$rfsElfFolder/$exeP"
		[ -s "$rfsDLinkFolder/$exeP".dlink ] && cat "$rfsDLinkFolder/$exeP".dlink >> "$rfsElfFolder/$exeP"
		if [ -n "$uvFolder" ]; then
			if [ -s "$uvFolder".set ] && [ -e "$uvFolder/$exeP".uv.set.dlink ] ; then
				cat "$uvFolder/$exeP".uv.set.dlink >> "$rfsElfFolder/$exeP"
			elif [ -s "$uvFolder".ads ] && [ -e "$uvFolder/$exeP".uv.ads.dlink ] ; then
				cat "$uvFolder/$exeP".uv.ads.dlink >> "$rfsElfFolder/$exeP"
			fi
			[ -s "$uvFolder/$exeP".uv.ldp.nodlapi.nodlapi ] && cat "$uvFolder/$exeP".uv.ldp.nodlapi.nodlapi >> "$rfsElfFolder/$exeP"
			[ -s "$rfsNssFolder/$exeP".uvdl.nss ] && cat "$rfsNssFolder/$exeP".uvdl.nss >> "$rfsElfFolder/$exeP"
			[ -s "$rfsNssFolder/$exeP".uvdl.nss.dlink ] && cat "$rfsNssFolder/$exeP".uvdl.nss.dlink >> "$rfsElfFolder/$exeP"
		fi
		
		if [ -s "$rfsDLoadFolder/$exeP".dload+dlink.all ]; then 
			cat "$rfsDLoadFolder/$exeP".dload+dlink.all >> "$rfsElfFolder/$exeP"
		fi
		[ -s "$rfsNssFolder/$exeP".nss ] && cat "$rfsNssFolder/$exeP".nss >> "$rfsElfFolder/$exeP"
		[ -s "$rfsNssFolder/$exeP".nss.dlink ] && cat "$rfsNssFolder/$exeP".nss.dlink >> "$rfsElfFolder/$exeP"

		sort -u "$rfsElfFolder/$exeP" -o "$rfsElfFolder/$exeP"
	done < "$rootFS".files.elf.analyze.short

	sort -u "$rfsElfFolder"/* -o "$rootFS".files.elf.dlink+dload+nss.short
	flsh2lo "$rootFS".files.elf.dlink+dload+nss.short "$rootFS".files.elf.all "$rootFS".files.elf.dlink+dload+nss

	if [ -z "$exeList" ]; then
		comm -23 "$rootFS".files.elf.all.short "$rootFS".files.elf.dlink+dload+nss.short > "$rootFS".files.so.dlink+dload+nss.unrefed.short
		flsh2lo "$rootFS".files.so.dlink+dload+nss.unrefed.short "$rootFS".files.elf.all "$rootFS".files.so.dlink+dload+nss.unrefed

		logFile "$rootFS".files.elf.dlink+dload+nss "All dlink+dload+nss ELFs" "$name".log
		logFile "$rootFS".files.so.dlink+dload+nss.unrefed "All dlink+dload+nss unrefed libs" "$name".log
	fi

	comm -12 "$rootFS".files.elf.dlink+dload+nss.short "$rootFS".files.so.all.short > "$rootFS".files.so.dlink+dload+nss.short
	#_soRefedByApp $_folder $_elfFileList $_log $_ext
	_soRefedByApp "$rfsElfFolder" "$rootFS".files.so.dlink+dload+nss.short "$rootFS".files.so.dlink+dload+nss.log ""

	[ -s "$rootFS".files.so."$rootFS".files.so.dlink+dload+nss.short ] && logFile "$rootFS".files.so.dlink+dload+nss.short "dlink+dload+nss shared libraries" "$name".log
	printf "%-86s : %s\n" "dlink+dload+nss shared libraries referenced by applications" "$rootFS".files.so.dlink+dload+nss.log | tee -a $name.log

	#Cleanup
	if [ -n "$uvFolder" ]; then
		find "$uvFolder" -type f \( -name "*.dlink" -o -name "*.uv.ldp.*" \) -exec rm {} \;
		find ./ -maxdepth 1 -type f -name "$uvFolder.*" ! -name "$uvFolder".ads.no-dlapi-elfs -exec rm {} \;
	fi
	rm "$rootFS".files.elf.dlink+dload+nss.short
fi

if [[ -n "$rtValidation" || -n "$usedFiles" ]] && [ -n "$dlink" ] && [ -n "$nss" ] && [ -n "$dload" ]; then
	echo "Dynamically linked/loaded shared object validation:" | tee -a $name.log

	[ ! -e "$rootFS".files.exe.all.short ] && fllo2sh "$rootFS".files.exe.all "$rootFS".files.exe.all.short
	[ -z "$exeList" ] && procs= || procs="$exeList".short

	sort "$rootFS".files.elf.dlink-libdld.dlapi.short "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short > "$rootFS".files.elf.libdld.dlapi.short

	if [ -n "$rtValidation" ]; then
		if [ -n "$ppmList" ]; then
			# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps files list : $4 - rt validation folder
			#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - procs to analyze : $8 - log name : $9 - work folder :  $10 - mrtv analysis ops
			_rootFSElfAnalyzerMValidation "$rootFS" "$rfsElfFolder" "$ppmList" "$rootFS".rt-validation \
							"$rootFS".files.exe.all.short "$rootFS".files.elf.libdld.dlapi.short "$procs" "$name".log "$rootFS".run-time "$ppmlOpts"
		else
			# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps file : $4 - rt validation folder
			#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - procs to analyze : $8 - log name : $9 - work folder
			_rootFSElfAnalyzerValidation "$rootFS" "$rfsElfFolder" "$ppmFile" "$rootFS".rt-validation \
							"$rootFS".files.exe.all.short "$rootFS".files.elf.libdld.dlapi.short "$procs" "$name".log "$rootFS".run-time
		fi
	fi

	if [ -z "$exeList" ]; then
		cat /dev/null > "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
		if [ -n "$rtValidation" ]; then
			# reevaluation of the "$rootFS".files.so.dlink+dload+nss.unrefed
			if [ -n "$ppmList" ]; then
				if [ "${ppmlOpts#*t}" != "$ppmlOpts" ]; then
					if [ -s "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_analyze_not_validated ] && [ -s "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_elf_rt_used ]; then
						comm -23 "$rootFS".files.so.dlink+dload+nss.unrefed.short \
						<(sort -u "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_analyze_not_validated "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_elf_rt_used) > \
						"$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
					elif [ -s "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_elf_rt_used ]; then
						comm -23 "$rootFS".files.so.dlink+dload+nss.unrefed.short "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_elf_rt_used > \
						"$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
					elif [ -s "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_analyze_not_validated ]; then
						comm -23 "$rootFS".files.so.dlink+dload+nss.unrefed.short "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_analyze_not_validated > \
						"$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
					fi
				fi
			else
				ls "$rootFS".run-time/"$rootFS".rt-validation/*.not-validated 2>/dev/null | sort -u -o "$rootFS".run-time/"$rootFS".rt-validation.not-validated
				if [ -s "$rootFS".run-time/"$rootFS".rt-validation.not-validated ] && [ -s "$rootFS".run-time/"$rootFS".$fme_elf_rt_used ]; then
					comm -23 "$rootFS".files.so.dlink+dload+nss.unrefed.short \
						<(sort -u "$rootFS".run-time/"$rootFS".rt-validation.not-validated "$rootFS".run-time/"$rootFS".$fme_elf_rt_used) > \
						"$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
				elif [ -s "$rootFS".run-time/"$rootFS".$fme_elf_rt_used ]; then
					comm -23 "$rootFS".files.so.dlink+dload+nss.unrefed.short "$rootFS".run-time/"$rootFS".$fme_elf_rt_used > \
						"$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
				elif [ -s "$rootFS".run-time/"$rootFS".rt-validation.not-validated ]; then
					comm -23 "$rootFS".files.so.dlink+dload+nss.unrefed.short "$rootFS".run-time/"$rootFS".rt-validation.not-validated > \
						"$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
				fi
				rm "$rootFS".run-time/"$rootFS".rt-validation.not-validated
			fi
		fi
		if [ -n "$usedFiles" ]; then
			# strip "used" files off the unrefed
			if [ -s "$rootFS".files.so.used.short ]; then
				comm -13 "$rootFS".files.so.used.short <(sort -u "$rootFS".files.so.dlink+dload+nss.unrefed.short "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short) \
					> "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short.tmp
				mv "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short.tmp "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
			fi
		fi

		if [ -s "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short ]; then
			flsh2lo "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short "$rootFS".files.elf.all "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated
			logFile "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated "All dlink+dload+nss urefed libs reev" "$name".log

			if [ -z "$ppmList" ] && [ -s "$rootFS".run-time/"$rootFS".$fme_so_rt_used ]; then
				ln -sf "$rootFS".run-time/"$rootFS".$fme_so_rt_used "$rootFS".$fme_so_rt_used
			elif [ -n "$ppmList" ]; then
				if [ -s "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_so_rt_used ]; then
					ln -sf "$rootFS".run-time/"$rootFS".total/"$rootFS".total.$fme_so_rt_used "$rootFS".$fme_so_rt_used
				elif [ -s "$rootFS".run-time/"$rootFS".common/"$rootFS".common.$fme_so_rt_used ]; then
					ln -sf "$rootFS".run-time/"$rootFS".common/"$rootFS".common.$fme_so_rt_used "$rootFS".$fme_so_rt_used
				fi
			fi
			if [ -s "$rootFS".$fme_so_rt_used ]; then
				comm -12 "$rootFS".files.so.dlink+dload+nss.unrefed.short "$rootFS".$fme_so_rt_used > "$rootFS".files.so.unrefed.missed.short
				flsh2lo "$rootFS".files.so.unrefed.missed.short "$rootFS".files.so.all "$rootFS".files.so.unrefed.missed
				logFile "$rootFS".files.so.unrefed.missed "unrefed libs missed" "$name".log
				rm "$rootFS".$fme_so_rt_used
			fi

			rm -f "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short "$rootFS".files.so.unrefed.missed.short
		fi
	else
		rm -f "$procs" "$procs".analyze
	fi

	# Cleanup
	rm -f "$rootFS".maps.list
fi

find "$rfsSymsFolder" -maxdepth 1 -name "*.str-so.dlink.error" -exec cat > "$rootFS".files.elf.str-so.dlink.not-found {} \; -exec rm {} \;
if [ -s "$rootFS".files.elf.str-so.dlink.not-found ]; then
	echo "$name # FYI       : ELF files with unresolved str-so reference(s) found! See $rootFS.files.elf.str-so.dlink.not-found" | tee -a "$name".log
fi

find ./ -maxdepth 2 -name "*.dlink.error" ! -name "$rootFS".files.elf.dlink.error ! -name "$rootFS".files.elf.str-so.dlink.error -exec cat > "$rootFS".files.elf.dlink.error {} \; -exec rm {} \;
if [ -s "$rootFS".files.elf.dlink.error ]; then
	echo "$name # Warn      : Unresolved reference(s) found! See $rootFS.files.elf.dlink.error" | tee -a "$name".log
fi

if [ -n "$rdbgFolder" ]; then
	cat /dev/null > "$rootFS".files.elf.dbg-missing
	find ./ -maxdepth 2 -name "*.dbg-missing" ! -name "$rootFS".files.elf.dbg-missing -exec cat >> "$rootFS".files.elf.dbg-missing {} \; -exec rm {} \;

	if [ -s "$rootFS".files.elf.dbg-missing ]; then
		sed -i "s:$rdbgFolder::;s:.debug::;s:\(/\)\1\+:\1:g" "$rootFS".files.elf.dbg-missing
		sort -u "$rootFS".files.elf.dbg-missing -o "$rootFS".files.elf.dbg-missing
		echo "$name # Warn      : ELF files with missing symbolic/dbg info found! See $rootFS.files.elf.dbg-missing" | tee -a "$name".log
	fi
fi

# Cleanup
[ -n "$dload" ] && find "$rfsDLoadFolder" -maxdepth 1 -size 0 -exec rm {} \;
[ -n "$uvFolder" ] && find "$uvFolder" -maxdepth 1 -size 0 -exec rm {} \;
find ./ "$odTCDFUNDFolder" "$odTCDFtextFolder" -maxdepth 1 -size 0 -exec rm {} \;
find ./ \( -name "*.str-symb" -o -name "*.libdl.user*" -o -name "*.dC" \) -exec rm {} \;

rm -f "$rootFS".files.so.dlink.short "$rootFS".files.so.unrefed.short
rm -f "$rootFS".files.exe.all.short "$rootFS".files.so.all.short
if [ -n "$usedFiles" ]; then
	rm -f "$usedFiles".short "$rootFS".files.all.short "$rootFS".files.exe.used.short \
		"$rootFS".files.exe.unused.short "$rootFS".files.so.used.short "$rootFS".files.so.unused.short
	[ -e "$usedFiles".missing.short ] && [ ! -s "$usedFiles".missing.short ] && rm "$usedFiles".missing.short
fi
rm -f "$rfsNssFolder"/nss.dlink.short "$rootFS".files.elf.analyze.short "$rootFS".files.elf.descr "$rootFS".files.elf.all.short
rm -f "$rootFS".files.exe.dlink-libdl.short "$rootFS".files.elf.dlink-libdld.no-dlapi.short "$rootFS".files.elf.dlink-libdld.dlapi.short "$rootFS".files.elf.dlink-libdld.short
rm -f "$rootFS".files.so.unrefed.dlink-libdl.short "$rootFS".files.so.unrefed.dlink-libdld.short "$rootFS".files.so.unrefed.dlink-libdld.no-dlapi.short
rm -f "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short
rm -f "$rootFS".files.exe.dlink-libdld.dlapi.short "$rootFS".files.so.dlink-libdld.dlapi.short
rm -f "$rootFS".files.so.dlink+dload+nss.unrefed.short

phase3EndTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

phase3ExecTime=`expr $phase3EndTime - $phase3StartTime`
printf "$name: Phase 3 Execution time: %02dh:%02dm:%02ds\n" $((phase3ExecTime/3600)) $((phase3ExecTime%3600/60)) $((phase3ExecTime%60))

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Total   Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

