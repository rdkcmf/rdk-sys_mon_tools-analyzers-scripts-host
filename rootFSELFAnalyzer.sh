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

# Variables:
EXE_FILE_PATTERN="ELF .* executable"
EXE_FILE_PATTERN_SUP="ELF 32-bit LSB executable"
SO_FILE_PATTERN="ELF .* shared object"
SO_FILE_PATTERN_SUP="ELF 32-bit LSB shared object"

defaultSkippedSystemLibs="/lib/ld-2.19.so /lib/libc-2.19.so $libdlDefault /lib/libgcc_s.so.1 /lib/libm-2.19.so /lib/libpthread-2.19.so /lib/libresolv-2.19.so \
			/lib/librt-2.19.so /lib/libsystemd.so.0.4.0 /lib/libz.so.1.2.8 /usr/lib/liblzma.so.5.0.99 /lib/libuuid.so.1.3.0 /usr/lib/libbcc.so"

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` -r folder [-e file] [-od name] [-V -psefw file -ppm file] [-o {a|d}] | [-h]"
	echo "$name# Target RootFS ELF objects analyzer, requires env PATH set to platform tools with objdump"
	echo "$name# -r    : a mandatory rootFS folder"
	echo "$name# -e    : an optional executable file list to analyze instead of default \"all executables\" analysis"
	echo "$name# -dlapi: an optional libdl api to verify; default is all \"$libdlDefault\" exposed api"
	echo "$name# -dlink: an optional dynamically linked exe file analysis"
	echo "$name# -dload: an optional dynamically loaded \"libdl dependent\" exe file analysis"
	echo "$name# -nss  : an optional \"name service switch\" exe file analysis"
	echo "$name# -cache: \"use cache\" option; default - cache is not used, all file folders are removed"
	echo "$name# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "$name# -V    : an optional validation mode to verify all shared objs properly dynamically linked to procs: requires -ppm option set"
	echo "$name# -pm   : an optional \"/proc/*/maps\" file of all processes, use \"grep r-xp /proc/*/maps\" to collect it: mandatory when -V is set"
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

while [ "$1" != "" ]; do
	case $1 in
		-r | --root )	shift
				rfsFolder="$1"
				;;
		-e)		shift
				exeList="$1"
				;;
		-od )		shift
				objdump="$1"
				;;
		-V )		rtValidation=y
				;;
		-pm)		shift
				ppmFile="$1"
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
		* )		usage
				exit 1
	esac
	shift
done

if [ -z "$rfsFolder" ] || [ ! -d "$rfsFolder" ]; then
	echo "$name# ERROR : rootFS folder \"$rfsFolder\" is not set or found!"
	usage
	exit $ERR_PARAM_NOT_SET
fi

if [ -n "$exeList" ]; then
	if [ ! -s "$exeList" ]; then
		echo "$name# Error : executable file list \"$exeList\" is empty or not found!"
		usage
		exit
	fi
	sort -u "$exeList" -o "$exeList".short
fi

if [ -n "$libdlApi" ] && [ ! -e "$libdlApi" ]; then
	echo "$name# ERROR : libdlApi file \"$libdlApi\" is not found!"
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
	echo "$name# ERROR : Skipped Libs File=\"$skippedLibsFile\" doesn't exist!"
	usage
	exit
fi

if [ -n "$rtValidation" ]; then
	if [ ! -e "$ppmFile" ]; then
		echo "$name# ERROR : a mandatory \"/proc/*/maps\" file=\"$ppmFile\" is not set or doesn't exist!"
		usage
		exit
	fi
fi

echo "$cmdline" > "$name".log
echo "$name: rootFS  = $rootFS" | tee -a "$name".log
echo "$name: objdump = $objdump" | tee -a "$name".log
if [ -n "$rtValidation" ]; then
	echo "$name: ppm     = $ppmFile" | tee -a "$name".log
fi
echo "$name: path    = $path" | tee -a "$name".log
[ -z "$cache" ] && echo "$name: cache   = no" | tee -a "$name".log || echo "$name: cache   = yes" | tee -a "$name".log
[ -z "$skippedLibsFile" ] && echo "$name: skl     = default" | tee -a "$name".log || echo "$name: skl     = $skippedLibsFile" | tee -a "$name".log

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
			echo "$name# ERROR : libdlApi file \"$libdlApi\" is not valid!"
			usage
			exit $ERR_OBJ_NOT_VALID
		fi
	else
		cut -f2- "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext | sort -u -o "$odTCDFtextFolder"/libdlApi
	fi

	echo "$name: dlapi   = $(cat "$odTCDFtextFolder"/libdlApi | tr '\n' ' ')" | tee -a "$name".log
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
#sort -k9,9 "$rootFS".files.elf.all -o "$rootFS".files.elf.all

# Referenced shared library object analysis - "needed" files referenced from the "used" elf files. Optional.
echo "Dynamically linked shared object analysis:" | tee -a "$name".log
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

[ -e "$rootFS".files.exe.used ] && rm "$rootFS".files.exe.used
[ -e "$rootFS".files.so.used  ] && rm "$rootFS".files.so.used
if [ -n "$usedFiles" ]; then
	usedFiles=$(flslfilter "$usedFiles")

	# check input file formats if analysis requested
	nf2=$(fileFormat "$usedFiles")
	if [ "$nf2" -ne 1 ]; then
		cat "$usedFiles" | tr -s ' ' | cut -d ' ' -f"$nf2"- | sort -o "$usedFiles".short
	else
		sort "$usedFiles" -o "$usedFiles".short
	fi

	# find missing files within given used
	fllo2sh "$rootFS".files.all "$rootFS".files.all.short
	comm -23 "$usedFiles".short "$rootFS".files.all.short > "$usedFiles".missing.short

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

	if [ -s "$rootFS".files.exe.used.short ] || [ ! -s "$rootFS".files.so.used.short ]; then
		ln -sf "$rootFS".files.exe.used.short "$rootFS".files.elf.analyze.short
	else
		ln -sf "$rootFS".files.so.used.short "$rootFS".files.elf.analyze.short
	fi
elif [ -n "$exeList" ]; then
	comm -13 "$rootFS".files.exe.all.short "$exeList".short > "$exeList".notFound
	if [ -s "$exeList".notFound ]; then
		echo "$name# Warn  : executable file list \"$exeList\" contains not found files!" | tee -a "$name".log
	fi
	comm -12 "$rootFS".files.exe.all.short "$exeList".short > "$exeList".exe.short
	flsh2lo "$exeList".exe.short "$rootFS".files.exe.all "$exeList".exe
	ln -sf "$exeList".exe.short "$rootFS".files.elf.analyze.short
else
	ln -sf "$rootFS".files.exe.all.short "$rootFS".files.elf.analyze.short
fi

if [ -n "$dlink" ] || [ -n "$nss" ] || [ -n "$dload" ]; then
	# Dynamically linked shared libraries analysis
	cat /dev/null > "$rfsDLinkFolder"/dlink.error
	while read filename
	do
		outFile=$(echo "$filename" | tr '/' '%').dlink
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "$filename" "" "$rfsDLinkFolder/$outFile" "" "libdl" ""
		if [ -s "$rfsDLinkFolder/$outFile".error ]; then
			echo "$rfsDLinkFolder/$outFile".error >> "$rfsDLinkFolder"/dlink.error
		fi	
	done < "$rootFS".files.exe.all.short
	[ ! -s "$rfsDLinkFolder"/dlink.error ] && rm "$rfsDLinkFolder"/dlink.error
	sort -u "$rfsDLinkFolder"/*.dlink -o "$rootFS".files.so.dlink.short

	cat /dev/null > "$rootFS".files.so.dlink.log
	#_soRefedByApp $_folder $_elfFileList $_log
	_soRefedByApp "$rfsDLinkFolder" "$rootFS".files.so.dlink.short "$rootFS".files.so.dlink.log

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
	comm -1 "$rootFS".files.exe.all.short "$rootFS".files.elf.dlink-libdld.dlapi.short | awk -F$'\t' -v file="$rootFS".files '{\
		if (NF == 2) {\
			printf("%s\n", $2) > file".exe.dlink-libdld.dlapi.short"
		} else if (NF == 1) {\
			printf("%s\n", $1) > file".so.dlink-libdld.dlapi.short"
		}\
		}'
	flsh2lo "$rootFS".files.exe.dlink-libdld.dlapi.short "$rootFS".files.elf.all "$rootFS".files.exe.dlink-libdld.dlapi
	flsh2lo "$rootFS".files.so.dlink-libdld.dlapi.short "$rootFS".files.elf.all "$rootFS".files.so.dlink-libdld.dlapi

	cat /dev/null > "$rootFS".files.so.dlink-libdld.dlapi.log
	#_soRefedByApp $_folder $_elfFileList $_log
	_soRefedByApp "$rfsDLinkFolder" "$rootFS".files.so.dlink-libdld.dlapi.short "$rootFS".files.so.dlink-libdld.dlapi.log

	flsh2lo "$rootFS".files.so.dlink.short "$rootFS".files.so.all "$rootFS".files.so.dlink

	# Dynamically linked unreferenced shared libraries analysis

	# build "$rootFS".files.so.unrefed
	comm -13 "$rootFS".files.so.dlink.short "$rootFS".files.so.all.short > "$rootFS".files.so.unrefed.short
	flsh2lo "$rootFS".files.so.unrefed.short "$rootFS".files.so.all "$rootFS".files.so.unrefed

	cat /dev/null > "$rfsDLinkUnrefedSoFolder"/dlink.error
	while read filename
	do
		outFile=$(echo "$filename" | tr '/' '%').dlink
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "$filename" "" "$rfsDLinkUnrefedSoFolder/$outFile" "" "libdl" ""
		if [ -s "$rfsDLinkUnrefedSoFolder/$outFile".error ]; then
			echo "$rfsDLinkUnrefedSoFolder/$outFile".error >> "$rfsDLinkUnrefedSoFolder"/dlink.error
		fi	
	done < "$rootFS".files.so.unrefed.short
	[ ! -s "$rfsDLinkUnrefedSoFolder"/dlink.error ] && rm "$rfsDLinkUnrefedSoFolder"/dlink.error

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

# missing requested files if any
[ -s "$usedFiles".missing.short ] && echo "$name# Warn  : There are missing files in $usedFiles : $usedFiles.missing.short" | tee -a "$name".log

# all/used/unused executables
logFile "$rootFS".files.exe.all "All executable files" "$name".log
[ -s "$rootFS".files.exe.used ] && logFile "$rootFS".files.exe.used "Used executable files" "$name".log
[ -s "$rootFS".files.exe.unused ] && logFile "$rootFS".files.exe.unused "Unused executable files" "$name".log

# all/used/unused shared library objects
logFile "$rootFS".files.so.all "All shared libraries" "$name".log
[ -s "$rootFS".files.so.used ] && logFile "$rootFS".files.so.used "Used shared libraries" "$name".log
[ -s "$rootFS".files.so.unused ] && logFile "$rootFS".files.so.unused "Unused shared libraries" "$name".log

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
	[ -s "$rootFS".files.elf.dlink-libdld.no-dlapi ] && logFile "$rootFS".files.elf.dlink-libdld.no-dlapi "elfs dlinked with libdl, no dlapi" "$name".log

	# elf (exe/so) files dynamically linked with libdl directly and containing libdl api calls
	[ -s "$rootFS".files.elf.dlink-libdld.dlapi ] && logFile "$rootFS".files.elf.dlink-libdld.dlapi "elfs dlinked with libdl, dlapi" "$name".log

	# exe files dynamically linked with libdl directly and containing libdl api calls
	[ -s "$rootFS".files.exe.dlink-libdld.dlapi ] && logFile "$rootFS".files.exe.dlink-libdld.dlapi "exe dlinked with libdl, dlapi" "$name".log

	# so files dynamically linked with libdl directly and containing libdl api calls
	[ -s "$rootFS".files.so.dlink-libdld.dlapi ] && logFile "$rootFS".files.so.dlink-libdld.dlapi "so dlinked with libdl, dlapi" "$name".log
	printf "%-86s : %s\n" "so dlinked with libdl, dlapi - referenced by applications" "$rootFS".files.so.dlink-libdld.dlapi.log | tee -a $name.log

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

	[ ! -e "$rootFS".files.exe.dlink-libdld.dlapi.short ] && fllo2sh "$rootFS".files.exe.dlink-libdld.dlapi "$rootFS".files.exe.dlink-libdld.dlapi.short

	#iter=1
	while read libdldExe
	do
		#printf "%-2d: libdldExe=%s\n" "$iter" "$libdldExe"
		outFile=$(echo "$libdldExe" | tr '/' '%')
		# _rootFSDLoadElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name : $3 - output file name : $4 - work folder
		_rootFSDLoadElfAnalyzer "$rfsFolder" "$libdldExe" $outFile "$wFolderPfx"
		#((iter++))
	done < "$rootFS".files.exe.dlink-libdld.dlapi.short
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
		cat /dev/null > "$rfsNssFolder"/nss.dlink.error
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "" "$rfsNssFolder"/nss.short "$rfsNssFolder"/nss.dlink "$rfsNssFolder" "" ""
		#[ ! -s ""$rfsNssFolder""/nss.dlink.error ] && rm -f ""$rfsNssFolder""/nss.dlink.error
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
	else
		rm "$rfsNssFolder"/nss.not-found
	fi

	if [ -n "$nss" ]; then
		iter=1
		while read exe
		do
			#printf "%-2d: exe=%s\n" "$iter" "$exe"
			outFile=$(echo "$exe" | tr '/' '%')
			_rootFSNssElfAnalyzer "$rfsFolder" "$exe" "$rfsNssFolder/$outFile"
			((iter++))
		done < "$rootFS".files.exe.all.short
	fi

	# Cleanup
	rm -f "$rfsNssFolder"/nss.short "$rfsNssFolder"/nss.dlink.short
fi

if [ -n "$dlink" ] && [ -n "$nss" ] && [ -n "$dload" ]; then

	rfsElfFolder="$rootFS".elf
	[ -z "$cache" ] && rm -rf "$rfsElfFolder"
	mkdir -p "$rfsElfFolder"

	[ ! -e "$rootFS".files.exe.all.short ] && fllo2sh "$rootFS".files.exe.all "$rootFS".files.exe.all.short

	while read exe
	do
		outFile=$(echo "$exe" | tr '/' '%')
		echo "$exe" > "$rfsElfFolder/$outFile"
		[ -s "$rfsDLinkFolder/$outFile".dlink ] && cat "$rfsDLinkFolder/$outFile".dlink >> "$rfsElfFolder/$outFile"
		[ -s "$rfsDLoadFolder/$outFile".dload+dlink.all ] && cat "$rfsDLoadFolder/$outFile".dload+dlink.all >> "$rfsElfFolder/$outFile"
		[ -s "$rfsNssFolder/$outFile".nss ] && cat "$rfsNssFolder/$outFile".nss >> "$rfsElfFolder/$outFile"
		[ -s "$rfsNssFolder/$outFile".nss.dlink ] && cat "$rfsNssFolder/$outFile".nss.dlink >> "$rfsElfFolder/$outFile"

		sort -u "$rfsElfFolder/$outFile" -o "$rfsElfFolder/$outFile"
	done < "$rootFS".files.exe.all.short

	sort -u "$rfsElfFolder"/* -o "$rootFS".files.elf.dlink+dload+nss.short
	flsh2lo "$rootFS".files.elf.dlink+dload+nss.short "$rootFS".files.elf.all "$rootFS".files.elf.dlink+dload+nss

	comm -23 "$rootFS".files.elf.all.short "$rootFS".files.elf.dlink+dload+nss.short > "$rootFS".files.so.dlink+dload+nss.unrefed.short
	flsh2lo "$rootFS".files.so.dlink+dload+nss.unrefed.short "$rootFS".files.elf.all "$rootFS".files.so.dlink+dload+nss.unrefed

	logFile "$rootFS".files.elf.dlink+dload+nss "All dlink+dload+nss ELFs" "$name".log
	logFile "$rootFS".files.so.dlink+dload+nss.unrefed "All dlink+dload+nss unrefed libs" "$name".log

	#Cleanup
	rm -f "$rootFS".files.elf.dlink+dload+nss.short
fi

if [ -n "$rtValidation" ] && [ -n "$dlink" ] && [ -n "$nss" ] && [ -n "$dload" ]; then
	echo "Dynamically linked/loaded shared object validation:" | tee -a $name.log

	# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps file : $4 - rt validation folder
	#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - log name
	sort "$rootFS".files.elf.dlink-libdld.dlapi.short "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short > "$rootFS".files.elf.libdld.dlapi.short
	_rootFSElfAnalyzerValidation	"$rootFS" "$rfsElfFolder" "$ppmFile" "$rootFS".rt-validation \
					"$rootFS".files.exe.all.short "$rootFS".files.elf.libdld.dlapi.short "$name".log

	# reevaluation of the "$rootFS".files.so.dlink+dload+nss.unrefed
	comm -23 "$rootFS".files.so.dlink+dload+nss.unrefed.short <(sort -u "$rootFS".rt-validation/*.not-validated) > "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
	if [ -s "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short ]; then
		flsh2lo "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short "$rootFS".files.elf.all "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated
		logFile "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated "All dlink+dload+nss urefed libs reev" "$name".log
		rm "$rootFS".files.so.dlink+dload+nss.unrefed.reevaluated.short
	fi
fi

if [ -s "$rfsDLinkFolder"/dlink.error ]; then
	echo "$name # Warn      : Unresolved reference(s) present! See "$rfsDLinkFolder"/dlink.error" | tee -a "$name".log
fi	

# Cleanup
rm -f "$rootFS".files.so.dlink.short "$rootFS".files.so.unrefed.short
rm -f "$rootFS".files.all.short
rm -f "$rootFS".files.so.all.short "$rootFS".files.so.used.short "$rootFS".files.so.unused.short "$rootFS".files.so.lessSystem.short
rm -f "$rootFS".files.exe.all.short "$rootFS".files.exe.used.short  "$rootFS".files.exe.unused.short
rm -f "$rfsNssFolder"/nss.dlink.short "$rootFS".files.elf.analyze.short "$rootFS".files.elf.descr "$rootFS".files.elf.all.short
rm -f "$usedFiles".short
rm -f "$rootFS".files.exe.dlink-libdl.short "$rootFS".files.elf.dlink-libdld.no-dlapi.short "$rootFS".files.elf.dlink-libdld.dlapi.short "$rootFS".files.elf.dlink-libdld.short
rm -f "$rootFS".files.so.unrefed.dlink-libdl.short "$rootFS".files.so.unrefed.dlink-libdld.short "$rootFS".files.so.unrefed.dlink-libdld.no-dlapi.short
rm -f "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short
rm -f "$rootFS".files.exe.dlink-libdld.dlapi.short "$rootFS".files.so.dlink-libdld.dlapi.short
rm -f "$rootFS".files.so.dlink+dload+nss.unrefed.short

[ -e "$usedFiles".missing.short ] && [ ! -s "$usedFiles".missing.short ] && rm "$usedFiles".missing.short

phase3EndTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

phase3ExecTime=`expr $phase3EndTime - $phase3StartTime`
printf "$name: Phase 3 Execution time: %02dh:%02dm:%02ds\n" $((phase3ExecTime/3600)) $((phase3ExecTime%3600/60)) $((phase3ExecTime%60))

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Total   Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

