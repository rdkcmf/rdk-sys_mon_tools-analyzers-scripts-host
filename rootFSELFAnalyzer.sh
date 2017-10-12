#!/bin/bash
#
# ============================================================================
# RDK MANAGEMENT, LLC CONFIDENTIAL AND PROPRIETARY
# ============================================================================
# This file (and its contents) are the intellectual property of RDK Management, LLC.
# It may not be used, copied, distributed or otherwise  disclosed in whole or in
# part without the express written permission of RDK Management, LLC.
# ============================================================================
# Copyright (c) 2014 RDK Management, LLC. All rights reserved.
# ============================================================================
#
# $0 : rootFSELFAnalyzer.sh is a Linux Host based script that analyzes ELF files.

# Variables:
EXE_FILE_PATTERN="ELF .* executable"
EXE_FILE_PATTERN_SUP="ELF 32-bit LSB executable"
SO_FILE_PATTERN="ELF .* shared object"
SO_FILE_PATTERN_SUP="ELF 32-bit LSB shared object"

# Function: usage
function usage()
{
	echo "${name}# Usage : `basename $0 .sh` -r folder [-e file] [-od name] [-V -psefw file -ppm file] [-o {a|d}] | [-h]"
	echo "${name}# Target RootFS ELF objects analyzer, requires env PATH set to platform tools with objdump"
	echo "${name}# -r    : a mandatory rootFS folder"
	echo "${name}# -e    : an optional executable file list to analyze instead of default \"all executables\" analysis"
	echo "${name}# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "${name}# -V    : an optional validation mode to verify all shared objs properly dynamically linked to procs: requires -psefw & -ppm set"
	echo "${name}# -psefw: an optional \"ps -efw\" file that maps process ids and names, use \"ps -efw\" to collect it: mandatory when -V is set"
	echo "${name}# -ppm  : an optional \"/proc/*/maps\" file of all processes, use \"grep r-xp /proc/*/maps\" to collect it: mandatory when -V is set"
	echo "${name}# -o    : an optional output control : a - all | d - default/minimal"
	echo "${name}# -h    : display this help and exit"
}

# Function: logFile
# $1: filename	-a file in "ls -la" format
# $2: filedescr	-a file descriptor
# $3: logname	-a log file
function logFile()
{
	if [ -s $1 ]; then
		awk -v filename="$1" -v filedescr="$2" '{total += $5} END { printf "%-36s : %5d : %10d B / %9.2f KB / %6.2f MB : %s\n", filedescr, NR, total, total/1024, total/(1024*1024), filename}' "$1" | tee -a $3
	else
		printf "%-36s : %5d : %10d B / %9.2f KB / %6.2f MB : %s\n" "$2" 0 0 0 0 "$1" | tee -a $3
	fi
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
source ${0%/*}/rootFSCommon.sh

rfsFolder=
usedFiles=
ignoredFiles=
options=
outputCtr="default/minimal"
findType="-type f"
exeList=
exeExtAnalysis=y
objdump=
validation=
psefwFile=
ppmFile=
while [ "$1" != "" ]; do
	case $1 in
		-r | --root )	shift
				rfsFolder=$1
				;;
		-e)		shift
				exeList=$1
				;;
		-od )		shift
				objdump=$1
				;;
		-V )		validation=y
				;;
		-psefw)		shift
				psefwFile=$1
				;;
		-ppm)		shift
				ppmFile=$1
				;;
		-o )		shift
				options=$1
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

if [ "${rfsFolder}" == "" ]; then
	echo "${name}# Error   : rootFS folder is not set!"
	usage
	exit
fi

if [ ! -d "${rfsFolder}" ]; then
	echo "${name}# Error   : ${rfsFolder} is not a folder!"
	usage
	exit
fi

if [ -n "${exeList}" ]; then
	if [ ! -s "${exeList}" ]; then
		echo "${name}# Error : executable file list \"${exeList}\" is empty or not found!"
		usage
		exit
	fi
	sort -u ${exeList} -o ${exeList}.short
fi

# It's assumed that a shell pointed to by a /bin/sh link defines a platform type.
elf=${rfsFolder}$(readlink ${rfsFolder}/bin/sh)
# Check if an elf object exists
if [ ! -e "${elf}" ]; then
	echo "${name} : ERROR : ${elf} file not found!" | tee -a ${name}.log
	usage
	exit
fi

# Check if an elf object
isElf="$(file -b "${elf}" | grep "^ELF ")"
if [ -z "${isElf}" ]; then
	echo "${name} : ERROR  : ${elf} is NOT an ELF file!" | tee -a ${name}.log
	usage
	exit
fi

# Check if a supported ELF object architechture
elfArch=$(echo "${isElf}" | cut -d, -f2)
if [ ! -z "$(echo "${elfArch}" | grep "MIPS")" ]; then
	[ -z ${objdump} ] && objdump=mipsel-linux-objdump
elif [ ! -z "$(echo "${elfArch}" | grep "Intel .*86")" ]; then
	[ -z ${objdump} ] && objdump=i686-cm-linux-objdump
elif [ ! -z "$(echo "${elfArch}" | grep "ARM")" ]; then
	[ -z ${objdump} ] && objdump=armeb-rdk-linux-uclibceabi-objdump
else
	echo "${name}# ERROR : unsupported architechture : ${elfArch}" | tee -a ${name}.log
	echo "${name}# ERROR : supported architechtures  = {ARM | MIPS | x86}" | tee -a ${name}.log
	usage
	exit
fi

# Check if the PATH to $objdump is set
if [ -z "$(which ${objdump})" ]; then
	echo "${name}# ERROR : Path to ${objdump} is not set!" | tee -a ${name}.log
	usage
	exit
fi
if [ ! -e "${rfsFolder}/version.txt" ]; then
	echo "${name}# WARNING: ${rfsFolder}/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name"
	rootFS=`basename ${rfsFolder}`
else
	rootFS=`cat ${rfsFolder}/version.txt | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
fi

if [ -n "$validation" ]; then
	if [ ! -e "$ppmFile" ]; then
		echo "${name}# ERROR : prcPidMap=\"$ppmFile\" is not set or doesn't exist!"
		usage
		exit
	fi
	if [ ! -e "$psefwFile" ]; then
		echo "${name}# ERROR : psefw=\"$psefwFile\" is not set or doesn't exist!"
		usage
		exit
	fi
fi

echo "${cmdline}" > ${name}.log
echo "${name}: rootFS  = ${rootFS}" | tee -a ${name}.log
echo "${name}: objdump = ${objdump}" | tee -a ${name}.log
if [ -n "$validation" ]; then
	echo "${name}: ppm     = $ppmFile" | tee -a ${name}.log
	echo "${name}: psefw   = $psefwFile" | tee -a ${name}.log
fi

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

# create listing of target rootFS on the host
echo "RootFS file list construction:"
sub=${rfsFolder%/}
find ${rfsFolder} \( $findType \) -exec ls -la {} \;  | tr -s ' ' | sed "s:$sub::" | sort -k9,9 -o ${rootFS}.files.all
logFile ${rootFS}.files.all "All regular files" ${name}.log
find ${rfsFolder} \( $findType \) -exec file {} \; | grep "${EXE_FILE_PATTERN}\|${SO_FILE_PATTERN}" | cut -d ',' -f1 | sed "s:$sub::" > ${rootFS}.files.elf.all

# Referenced shared library object analysis - "needed" files referenced from the "used" elf files. Optional.
echo "Dynamically linked shared object analysis:" | tee -a ${name}.log
phase3StartTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

# find all executable files
grep "$EXE_FILE_PATTERN" ${rootFS}.files.elf.all | cut -d ':' -f1 | sort -o ${rootFS}.files.exe.all.short

# find all shared library object files
grep "$SO_FILE_PATTERN" ${rootFS}.files.elf.all | cut -d ':' -f1 | sort -o ${rootFS}.files.so.all.short

if [ -n "$exeExtAnalysis" ]; then
	cat /dev/null > ${rootFS}.files.exe-as-so.all.short
	while read filename
	do
		_err_=$?
		main=$(${objdump} -dC "${rfsFolder}/${filename}" | grep "^[[:xdigit:]]\{8\} <main>:")
		if [ $_err_ != 0 ]; then
			echo "${name}: Error=$_err_ executing ${objdump} -dC ${rfsFolder}/${filename}. Exit." | tee -a ${name}.log
			exit 
		fi
		[ -n "$main" ] && echo ${filename} >> ${rootFS}.files.exe-as-so.all.short
	done < ${rootFS}.files.so.all.short
	if [ -s ${rootFS}.files.exe-as-so.all.short ]; then
		sort ${rootFS}.files.exe-as-so.all.short -o ${rootFS}.files.exe-as-so.all.short

		# Remove shared objects from the ${rootFS}.files.exe-as-so.all.short list
		grep "\.so" ${rootFS}.files.exe-as-so.all.short > ${rootFS}.files.so.withmain.short
		if [ -s ${rootFS}.files.so.withmain.short ]; then
			comm -23 ${rootFS}.files.exe-as-so.all.short ${rootFS}.files.so.withmain.short > ${rootFS}.files.exe-as-so.all.short.tmp
			flsh2lo ${rootFS}.files.so.withmain.short ${rootFS}.files.all ${rootFS}.files.so.withmain

			mv ${rootFS}.files.exe-as-so.all.short.tmp ${rootFS}.files.exe-as-so.all.short
		fi
		rm ${rootFS}.files.so.withmain.short

		# Add ${rootFS}.files.exe-as-so.all.short to ${rootFS}.files.exe.all.short
		cat ${rootFS}.files.exe-as-so.all.short >> ${rootFS}.files.exe.all.short
		sort ${rootFS}.files.exe.all.short -o ${rootFS}.files.exe.all.short
		# Remove ${rootFS}.files.exe-as-so.all.short from ${rootFS}.files.so.all.short
		comm -23 ${rootFS}.files.so.all.short ${rootFS}.files.exe-as-so.all.short > ${rootFS}.files.so.all.short.tmp
		mv ${rootFS}.files.so.all.short.tmp ${rootFS}.files.so.all.short

		flsh2lo ${rootFS}.files.exe-as-so.all.short ${rootFS}.files.all ${rootFS}.files.exe-as-so.all

		logFile ${rootFS}.files.exe-as-so.all "Executables as shared object files" ${name}.log
		if [ -s ${rootFS}.files.so.withmain ]; then
			logFile ${rootFS}.files.so.withmain "Shared object with main() files" ${name}.log
		fi
	fi
	# Cleanup
	rm ${rootFS}.files.exe-as-so.all.short
fi

flsh2lo ${rootFS}.files.exe.all.short ${rootFS}.files.all ${rootFS}.files.exe.all
flsh2lo ${rootFS}.files.so.all.short ${rootFS}.files.all ${rootFS}.files.so.all

[ -e ${rootFS}.files.exe.used ] && rm ${rootFS}.files.exe.used
[ -e ${rootFS}.files.so.used  ] && rm ${rootFS}.files.so.used
if [ -n "${usedFiles}" ]; then
	usedFiles=$(flslfilter ${usedFiles})

	# check input file formats if analysis requested
	nf2=$(fileFormat ${usedFiles})
	if [ "$nf2" -ne 1 ]; then
		cat ${usedFiles} | tr -s ' ' | cut -d ' ' -f${nf2}- | sort -o ${usedFiles}.short
	else
		sort ${usedFiles} -o ${usedFiles}.short
	fi

	# find missing files within given used
	fllo2sh ${rootFS}.files.all ${rootFS}.files.all.short
	comm -23 ${usedFiles}.short ${rootFS}.files.all.short > ${usedFiles}.missing.short

	# find used executable files
	comm -12 ${usedFiles}.short ${rootFS}.files.exe.all.short > ${rootFS}.files.exe.used.short
	flsh2lo ${rootFS}.files.exe.used.short ${rootFS}.files.exe.all ${rootFS}.files.exe.used

	# find unused executable files
	comm -13 ${rootFS}.files.exe.used.short ${rootFS}.files.exe.all.short > ${rootFS}.files.exe.unused.short
	flsh2lo ${rootFS}.files.exe.unused.short ${rootFS}.files.exe.all ${rootFS}.files.exe.unused

	# find used shared object files
	comm -12 ${usedFiles}.short ${rootFS}.files.so.all.short > ${rootFS}.files.so.used.short
	flsh2lo ${rootFS}.files.so.used.short ${rootFS}.files.so.all ${rootFS}.files.so.used

	# find unused shared object files
	comm -13 ${rootFS}.files.so.used.short ${rootFS}.files.so.all.short > ${rootFS}.files.so.unused.short
	flsh2lo ${rootFS}.files.so.unused.short ${rootFS}.files.so.all ${rootFS}.files.so.unused

	if [ -s ${rootFS}.files.exe.used.short ] || [ ! -s ${rootFS}.files.so.used.short ]; then
		ln -sf ${rootFS}.files.exe.used.short ${rootFS}.files.elf.analyze.short
	else
		ln -sf ${rootFS}.files.so.used.short ${rootFS}.files.elf.analyze.short
	fi
elif [ -n "${exeList}" ]; then
	comm -13 ${rootFS}.files.exe.all.short ${exeList}.short > ${exeList}.notFound
	if [ -s ${exeList}.notFound ]; then
		echo "${name}# Warn  : executable file list \"${exeList}\" contains not found files!" | tee -a ${name}.log
	fi
	comm -12 ${rootFS}.files.exe.all.short ${exeList}.short > ${exeList}.exe.short
	flsh2lo ${exeList}.exe.short ${rootFS}.files.exe.all ${exeList}.exe
	ln -sf ${exeList}.exe.short ${rootFS}.files.elf.analyze.short
else
	ln -sf ${rootFS}.files.exe.all.short ${rootFS}.files.elf.analyze.short
fi

rootFSELF=${rootFS}.elf
rm -rf ${rootFSELF}
mkdir -p ${rootFSELF}

rm -f ${rootFS}.elf.log
while read entryElf
do
	elfName=$(echo ${entryElf} | tr '/' '%')
	echo "${entryElf}:" >> ${rootFS}.elf.log

	# build a list of all referenced referenced/"needed" shared library objects from all/used executables
	${objdump} -x ${sub}${entryElf} | grep "NEEDED" | tr -s ' ' | cut -d ' ' -f3 > ${rootFS}.files.elf.refed.odump

	iter=0
	ln -sf ${rootFS}.files.elf.refed.odump ${rootFS}.files.so.refed.link
	while [ -s ${rootFS}.files.so.refed.link ]; do
		cat /dev/null > ${rootFS}.files.so.refed.$iter.short

		# find all references in the objdump output
		cat /dev/null > ${rootFS}.files.elf.odump.find
		while read entry
		do
			find ${sub} -name ${entry} > ${rootFS}.files.elf.odump.find.tmp
			[ -s ${rootFS}.files.elf.odump.find.tmp ] && cat ${rootFS}.files.elf.odump.find.tmp >> ${rootFS}.files.elf.odump.find || printf "%1d: unresolved entry: %s\n" $iter ${entry/$sub/} >> ${rootFS}.elf.log
		done < ${rootFS}.files.elf.refed.odump

		while read entry
		do
			entryHResolved=$(readlink -e ${entry})
			if [ "${entry}HResolved" != "" ]; then
				entryShort=${entryHResolved/$sub/}
				echo "$entryShort" >> ${rootFS}.files.so.refed.$iter.short
			else
				printf "%1d: unresolved  link: %s\n" $iter ${entry/$sub/} >> ${rootFS}.elf.log
			fi
		done < ${rootFS}.files.elf.odump.find
		sort -u ${rootFS}.files.so.refed.$iter.short -o ${rootFS}.files.so.refed.$iter.short

		if [ "$iter" -eq 0 ]; then
			cat ${rootFS}.files.so.refed.$iter.short > ${rootFSELF}/${elfName}
			ln -sf ${rootFS}.files.so.refed.$iter.short ${rootFS}.files.so.refed.link
		else
			comm -13 ${rootFS}.files.so.refed.$((iter-1)).short ${rootFS}.files.so.refed.$iter.short > ${rootFS}.files.so.refed.uniq.short
			cat ${rootFS}.files.so.refed.uniq.short >> ${rootFSELF}/${elfName}
			ln -sf ${rootFS}.files.so.refed.uniq.short ${rootFS}.files.so.refed.link
		fi
	
		if [ "$outputCtr" == "all" ]; then
			while read entry
			do
				printf "%1d: %s\n" ${iter} ${entry} >> ${rootFS}.elf.log
			done < ${rootFS}.files.so.refed.link
		fi

		cat /dev/null > ${rootFS}.files.elf.refed.odump
		while read entry
		do
			${objdump} -x ${sub}${entry} | grep "NEEDED" | tr -s ' ' | cut -d ' ' -f3 >> ${rootFS}.files.elf.refed.odump
		done < ${rootFS}.files.so.refed.link
		sort -u ${rootFS}.files.elf.refed.odump -o ${rootFS}.files.elf.refed.odump

		iter=`expr $iter + 1`
	done
	[ -e ${rootFSELF}/${elfName} ] && sort -u ${rootFSELF}/${elfName} -o ${rootFSELF}/${elfName}
	[ "$outputCtr" == "all" ] && echo "" >> ${rootFS}.elf.log
done < ${rootFS}.files.elf.analyze.short

# build ${rootFS}.files.so.refed
if [ "$(ls -A ${rootFSELF})" != "" ]; then
	cat ${rootFSELF}/* | sort -u -o ${rootFS}.files.so.refed.short
	rm -f ${rootFS}.elf.refed.log
	if [ -s ${rootFS}.files.so.refed.short ]; then
		while read entry
		do
			grep -r "${entry}" ${rootFSELF} | cut -d ':' -f1 | tr '%' '/' | sort > ${rootFS}.files.elf.entry
			printf "%4d %s:\n" $(wc -l ${rootFS}.files.elf.entry | cut -d ' ' -f1) ${entry} >> ${rootFS}.elf.refed.log
			while read refed
			do
				printf "%4c \t\t%s\n" " " ${refed/"${rootFSELF}/"/} >> ${rootFS}.elf.refed.log
			done < ${rootFS}.files.elf.entry
		done < ${rootFS}.files.so.refed.short
		rm ${rootFS}.files.elf.entry
	fi
else
	cat /dev/null > ${rootFS}.files.so.refed.short
fi
flsh2lo ${rootFS}.files.so.refed.short ${rootFS}.files.so.all ${rootFS}.files.so.refed

# build ${rootFS}.files.so.unrefed
comm -13 ${rootFS}.files.so.refed.short ${rootFS}.files.so.all.short > ${rootFS}.files.so.unrefed.short
flsh2lo ${rootFS}.files.so.unrefed.short ${rootFS}.files.so.all ${rootFS}.files.so.unrefed

if [ -s ${usedFiles}.missing.short ]; then
	logFile ${usedFiles}.missing.short "Warning: Missing files" ${name}.log
fi

# all/used/unused executables
logFile ${rootFS}.files.exe.all "All executable files" ${name}.log
if [ -s ${rootFS}.files.exe.used ]; then
	logFile ${rootFS}.files.exe.used "Used executable files" ${name}.log
fi
if [ -s ${rootFS}.files.exe.unused ]; then
	logFile ${rootFS}.files.exe.unused "Unused executable files" ${name}.log
fi
# all/used/unused shared library objects
logFile ${rootFS}.files.so.all "All shared object files" ${name}.log
if [ -s ${rootFS}.files.so.used ]; then
	logFile ${rootFS}.files.so.used "Used shared object files" ${name}.log
fi
if [ -s ${rootFS}.files.so.unused ]; then
	logFile ${rootFS}.files.so.unused "Unused shared object files" ${name}.log
fi
# refed/unrefed shared library objects
if [ -s ${rootFS}.files.so.refed ]; then
	logFile ${rootFS}.files.so.refed "Referenced shared object files" ${name}.log
fi
if [ -s ${rootFS}.files.so.unrefed ]; then
	logFile ${rootFS}.files.so.unrefed "Unreferenced shared object files" ${name}.log
fi

if [ -n "$validation" ]; then
	echo "Dynamically linked shared object validation:" | tee -a ${name}.log

	#/proc/1/maps:775d0000-775e3000 r-xp 00000000 1f:17 1110       /lib/libz.so.1.2.8
	#/proc/pid/maps:address perms offset dev inode       pathname
	exe=
	procPid=
	procName=
	psortFolder=./${rootFS}.proc-so-rtmap	# process/so run-time info
	rm -rf ${psortFolder}
	mkdir -p ${psortFolder}
	grep -v "\[vdso\]" "${ppmFile}" | while read proc perms offs dev inode ename
	do
		entryPid=$(echo "$proc" | cut -d '/' -f3)
		exe=$(file ${rfsFolder}/${ename} | grep "${EXE_FILE_PATTERN}")
		if [ "$procPid" != "$entryPid" ]; then
			# New process parsing with $entryPid
			procPid=$entryPid
			if [ -z "$exe" ]; then
				procName=
				echo "$ename" > ${psortFolder}/$procPid
			else
				procName=$(echo "$ename" | sed 's:/:%:g')
				[ -e "${psortFolder}/$procName" ] && procName=$procName.$procPid
			fi
		else
			# Continue parsing same process with procPid=$entryPid
			if [ -z "$exe" ]; then 
				if [ -z "$procName" ]; then
	 				echo "$ename" >> ${psortFolder}/$procPid
				else
					echo "$ename" >> ${psortFolder}/$procName
				fi
			else
				if [ -z "$procName" ]; then
					procName=$(echo "$ename" | sed 's:/:%:g');
					[ -e "${psortFolder}/$procName" ] && procName=$procName.$procPid
					[ -e "${psortFolder}/$procPid" ] && mv ${psortFolder}/$procPid ${psortFolder}/$procName
					echo "$ename" >> ${psortFolder}/$procName
				else
					echo "$ename" >> ${psortFolder}/$procName
				fi
			fi
		fi
		#echo "id=$entryPid" "ename=$ename" $([ -z "$exe" ] && echo "so" || echo "exe") " procName=$procName"
	done

	for file in ${psortFolder}/*
	do
		sort -u $file -o $file
	done

	tail -n +2 ${psefwFile} | tr -s ' ' | cut -d ' ' -f2,8 | sed 's/\[//;s/\]//' | sort -u -o ${rootFS}.pid-name
	for file in ${psortFolder}/[[:digit:]]*
	do
		entry=$(grep "^$(basename $file) " ${rootFS}.pid-name | cut -d ' ' -f2)
		if [ -h "${rfsFolder}/${entry}" ]; then
			procName=$(readlink ${rfsFolder}/${entry})
		else
			procName=${entry}
		fi
		#echo "file=$file : entry = $entry : procName=$procName"
		if [ -n "$procName" ]; then
			awk -vLine="$procName" '!index($0,Line)' ${file} > ${psortFolder}/$(echo "$procName" | sed 's:/:%:g')
			rm ${file}
		fi
	done

	find ${rootFSELF} -type f | sed "s:${rootFSELF}/::" | sort -u -o ${rootFS}.procs.all
	find ${psortFolder} -type f | sed "s:${psortFolder}/::" | sort -u -o ${rootFS}.procs.rt
	comm -12 ${rootFS}.procs.all ${rootFS}.procs.rt > ${rootFS}.procs.analyze
	comm -13 ${rootFS}.procs.all ${rootFS}.procs.rt > ${rootFS}.procs.rt-spec

	cat /dev/null > ${rootFS}.procs.analyze.ident
	cat /dev/null > ${rootFS}.procs.analyze.diff
	while read filename
	do
		md5s1=$(md5sum ${rootFSELF}/${filename} | cut -d ' ' -f1)
		md5s2=$(md5sum ${psortFolder}/${filename} | cut -d ' ' -f1)
		if [ "$md5s1" == "$md5s2" ]; then
			#echo "$md5s1 ${filename}" >> ${rootFS}.procs.analyze.ident
			echo "${filename}" >> ${rootFS}.procs.analyze.ident
		else
			#echo "$md5s1 $md5s2 ${filename}" >> ${rootFS}.procs.analyze.diff
			echo "${filename}" >> ${rootFS}.procs.analyze.diff
		fi
	done < ${rootFS}.procs.analyze

	cat /dev/null > ${rootFS}.procs.analyze.diff.libdl
	cat /dev/null > ${rootFS}.procs.analyze.diff.not-libdl
	#while read md5s1 md5s2 filename
	while read filename
	do
		procNameFull=${psortFolder}/$(echo "${filename}" | sed 's:/:%:g')
		[ -z $(grep "/lib/libdl-2.19.so" $procNameFull) ] && echo ${filename} >> ${rootFS}.procs.analyze.diff.not-libdl || echo ${filename} >> ${rootFS}.procs.analyze.diff.libdl
	done < ${rootFS}.procs.analyze.diff
	
	printf "\"ps -efw\" entries                    : %5d : %s\n" $(( $(wc -l ${psefwFile} | cut -d ' ' -f1) - 1)) "${psefwFile}" | tee -a ${name}.log
	#grep -v "\[.*\]" ${psefwFile} | grep -v " ps " > ${psefwFile}.paramed
	#printf "Parameterized processes              : %5d : %s\n" $(( $(wc -l ${psefwFile}.paramed | cut -d ' ' -f1) - 1)) "${psefwFile}.paramed" | tee -a ${name}.log
	printf "/proc/<pid>/maps processes           : %5d : %s\n" $(wc -l ${rootFS}.procs.rt | cut -d ' ' -f1) "${rootFS}.procs.rt" | tee -a ${name}.log
	printf "Analyzed processes                   : %5d : %s\n" $(wc -l ${rootFS}.procs.analyze | cut -d ' ' -f1) "${rootFS}.procs.analyze" | tee -a ${name}.log
	printf "Run-time redundant processes         : %5d : %s\n" $(wc -l ${rootFS}.procs.rt-spec | cut -d ' ' -f1) "${rootFS}.procs.rt-spec" | tee -a ${name}.log
	printf "Validated processes                  : %5d : %s\n" $(wc -l ${rootFS}.procs.analyze.ident | cut -d ' ' -f1) "${rootFS}.procs.analyze.ident" | tee -a ${name}.log
	printf "Not validated processes              : %5d : %s\n" $(wc -l ${rootFS}.procs.analyze.diff | cut -d ' ' -f1) "${rootFS}.procs.analyze.diff" | tee -a ${name}.log
	printf "Processes with libdl-2.19.so refs    : %5d : %s\n" $(wc -l ${rootFS}.procs.analyze.diff.libdl | cut -d ' ' -f1) "${rootFS}.procs.analyze.diff.libdl" | tee -a ${name}.log
	printf "Processes with no libdl-2.19.so refs : %5d : %s\n" $(wc -l ${rootFS}.procs.analyze.diff.not-libdl | cut -d ' ' -f1) "${rootFS}.procs.analyze.diff.not-libdl" | tee -a ${name}.log

	# Cleanup
	rm ${rootFS}.pid-name
fi

# Cleanup
rm -f ${rootFS}.files.elf.*
rm -f ${rootFS}.files.so.refed.* ${rootFS}.files.so.unrefed.*
rm -f ${rootFS}.files.all.short
rm -f ${rootFS}.files.so.all.short ${rootFS}.files.so.used.short ${rootFS}.files.so.unused.short
rm -f ${rootFS}.files.exe.all.short ${rootFS}.files.exe.used.short  ${rootFS}.files.exe.unused.short
rm -f ${usedFiles}.short
[ -e ${usedFiles}.missing.short ] && [ ! -s ${usedFiles}.missing.short ] && rm ${usedFiles}.missing.short

phase3EndTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

phase3ExecTime=`expr $phase3EndTime - $phase3StartTime`
printf "${name}: Phase 3 Execution time: %02dh:%02dm:%02ds\n" $((phase3ExecTime/3600)) $((phase3ExecTime%3600/60)) $((phase3ExecTime%60))

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "${name}: Total   Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

