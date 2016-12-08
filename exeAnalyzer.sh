#!/bin/sh
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
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
##########################################################################
#
# $0 : exeAnalyze.sh is a Linux Host based script to analyze the usage of executables in ELF format.
# $1 : param1 is rootfs [ramdisk] folder to be analyzed
# $2 : param2 is an optional input file with a list of "used/executed" processes instantiated via calls to executables and links pointing to executables

# Setup:
# 1. Set USE_SYSRES_PLATFORM to use {BROADCOM | CANMORE}. Ex.: export USE_SYSRES_PLATFORM=broadcom
# 2. Set platforms's SDK. Ex.:
#    export WORK_DIR=<WORK_DIR>/workRNG150/
#    source $WORK_DIR/../SDK/Scripts/setBcmEnv.sh
# 3. Run exeAnalyzer.sh. Ex.: ./exeAnalyzer.sh <path to rootFS/ramdisk> [<path to a file>] 2>/dev/null
# 4. The output files: 
#    1. <rootFS baseName>.exe.total        - a list of all rootFS executable files and links to executables
#    2. <rootFS baseName>.exe.total.execs  - a list of all rootFS executable files
#    3. <rootFS baseName>.exe.total.links  - a list of all rootFS links to executables
#    4. <rootFS baseName>.exe.used   	   - a list of "used" executable files
#    5. <rootFS baseName>.exe.unused       - a list of "unused" executable files

name=`basename $0 .sh`
PLATFORM=`echo $USE_SYSRES_PLATFORM | tr '[:lower:]' '[:upper:]'`
if [ "$PLATFORM" == "BROADCOM" ]; then
	ELFREADER=mipsel-linux-readelf
else
	if [ "$PLATFORM" == "CANMORE" ]; then
		ELFREADER=i686-cm-linux-readelf
	else
		echo "$name# Error : USE_SYSRES_PLATFORM must be set to { BROADCOM | CANMORE }"
		exit
	fi
fi
echo "$name# Platform: $PLATFORM  ELFReader: $ELFREADER"
if [ "`which $ELFREADER`" == "" ]; then
	echo "$name# Error   : Path to $ELFREADER is not set!"
	exit
fi

if [ "$1" == "" ]; then
	echo "$name# Usage : $0 param1 [param2]"
	echo "$name# Usage : $0 param1 = folder param2 = file"
	echo "$name# param1: a rootFS folder [ramdisk]"
	echo "$name# param2: an optional input file with a list of used/executed processes"
	exit
fi

if [ -d "$1" ]; then
	if [ ! -e $1/version.txt ]; then
		echo "$name# WARNING: $1/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name"
		rootFS=`basename $1`
	else
		rootFS=`cat $1/version.txt | grep imagename | cut -d ':' -f2`
	fi

	find $1 \( -type f -a -perm -111 -o -type l \) -exec ls -la {} \; | grep -v "\.so" | grep -v "\.sh" | sort -u -k9 > $rootFS.exe.total.local.all
else
	echo "$name# Error   : param1 is not a folder!"
	exit
fi

if [ -e $rootFS.exe.total.local.elf ]; then
	rm $rootFS.exe.total.local.elf
fi
cat $rootFS.exe.total.local.all | while read line
do
	file=`readlink -e \`echo "$line" | tr -s ' ' | cut -d ' ' -f9\``
	type=`$ELFREADER -h $file | grep "Type:" | tr -s ' ' | cut -d ' ' -f2- | grep "Type: EXEC (Executable file)"`
	if [ "$type" != "" ] ; then
		echo $line >> $rootFS.exe.total.local.elf
	fi
done
sort -u -k9 $rootFS.exe.total.local.elf > $rootFS.exe.total.local

sub=$1
sub=${sub%/}
if [ -e $rootFS.exe.total ]; then
	rm $rootFS.exe.total
fi
cat $rootFS.exe.total.local | while read line
do
	echo -e "${line%$sub*}\c" >> $rootFS.exe.total; echo ${line#*$sub} >> $rootFS.exe.total
done

if [ -e $rootFS.exe.log ]; then
	rm $rootFS.exe.log
fi

echo "File count   :" `wc -l $rootFS.exe.total.local.all | cut -d ' ' -f1` | tee -a $rootFS.exe.log
echo ".exe/ln count:" `wc -l $rootFS.exe.total.local     | cut -d ' ' -f1` | tee -a $rootFS.exe.log

# total .exec/links
cat $rootFS.exe.total | awk '{total += $5} END { printf "Total        : %3d .exec/links / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.exe.log

# total .execs
grep -v "lrwxrwxrwx" $rootFS.exe.total > $rootFS.exe.execs
cat $rootFS.exe.execs | awk '{total += $5} END { printf "Total        : %3d executables / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.exe.log

# total links
grep -e "->" $rootFS.exe.total > $rootFS.exe.links
#wc -l $rootFS.exe.links | head -n 1 | awk '{ printf "Total Links  : %3d to .execs   /\n", $1 }'
cat $rootFS.exe.links | awk '{total += $5} END { printf "Total        : %3d links to exe/ %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.exe.log

if [ "$2" != "" ]; then
	dos2unix -db $2
	sort -u -k1 $2 > $2.s

	# total used
	if [ -e $rootFS.exe.used.tmp ]; then
		rm $rootFS.exe.used.tmp
	fi

	iter=1
	cat $2.s | while read line
	do
		files=`grep "/$line\b" $rootFS.exe.total.local | cut -d ' ' -f9`
		if [ "$files" == "" ]; then
			continue
		else
			for file in $files
			do
				base=`basename $file`
				if [ "$base" == "$line" ]; then
					break
				fi
			done
		fi

		#echo "$iter: $line: $file" >> $rootFS.exe.used.%
		file=`readlink -e $file`
		#echo "$iter: $line: $file" >> $rootFS.exe.used.%%
		str1=`grep "$file\b" $rootFS.exe.total.local`
		#echo "$iter: $line: $str1" >> $rootFS.exe.used.%%%
		echo -e "${str1%$sub*}\c" >> $rootFS.exe.used.tmp; echo ${str1#*$sub} >> $rootFS.exe.used.tmp
		iter=`expr $iter + 1`
	done
	sort -u -k9 $rootFS.exe.used.tmp > $rootFS.exe.used
	cat $rootFS.exe.used | awk '{total += $5} END { printf "Total Used   : %3d executables / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.exe.log


	cat $rootFS.exe.used | tr -s ' ' | cut -d ' ' -f9 > $rootFS.exe.used.short
	# total unused
	cat $rootFS.exe.total | tr -s ' ' | cut -d ' ' -f9 > $rootFS.exe.total.short
	comm -23 $rootFS.exe.total.short $rootFS.exe.used.short > $rootFS.exe.unused.short
	#grep -f $rootFS.exe.unused.short $rootFS.exe.total > $rootFS.exe.unused
	if [ -e $rootFS.exe.unused.% ]; then
		rm $rootFS.exe.unused.%
	fi
	cat $rootFS.exe.unused.short | while read line
	do
		file=$line
		grep -w "$file\$" $rootFS.exe.total >> $rootFS.exe.unused.%
		#echo $file >> $rootFS.exe.unused.%%
	done
	sort -u -k9 $rootFS.exe.unused.% > $rootFS.exe.unused
	cat $rootFS.exe.unused | tr -s ' ' | cut -d ' ' -f9 > $rootFS.exe.unused.%.short
	cat $rootFS.exe.unused | awk '{total += $5} END { printf "Total Unused : %3d executables / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.exe.log

	# total used duplicate
	cat $2 | awk -F"/" '{print $NF}' | sort | uniq -d > $rootFS.exe.used_duplicate.short
	exeDuplCount=`wc -l $rootFS.exe.used_duplicate.short`
	if [ "$exeDuplCount" != "0" ]; then
		if [ -e $rootFS.exe.used_duplicate ]; then
			rm $rootFS.exe.used_duplicate
		fi
		cat $rootFS.exe.used_duplicate.short | while read line
		do
			grep "$line\$" $rootFS.exe.total >> $rootFS.exe.used_duplicate
		done
		#grep -f $rootFS.exe.used_duplicate.short $rootFS.exe.total > $rootFS.exe.used_duplicate
		cat $rootFS.exe.used_duplicate | awk '{total += $5} END { printf "Total UsedDup: %3d executables / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.exe.log
	fi

	# total given
	fileGivenCount=`wc -l $2.s | cut -d ' ' -f1`
	echo $fileGivenCount | awk '{ printf "Total Given  : %3d .exec/links /\n", $1 }' | tee -a $rootFS.exe.log

	# total missing
	if [ -e $rootFS.exe.missing ]; then
		rm $rootFS.exe.missing
	fi
	filePresCount=`wc -l $rootFS.exe.used  | cut -d ' ' -f1`
	linkPresCount=`wc -l $rootFS.exe.links | cut -d ' ' -f1`
	((filePresCount+=$linkPresCount))
	if [ "$fileGivenCount" -gt "$filePresCount" ]; then
		cat $rootFS.exe.used | tr -s ' ' | cut -d ' ' -f9 > $rootFS.exe.used.short
		comm -23 $2.s $rootFS.exe.used.short > $rootFS.exe.missing
		exeMissCount=`wc -l $rootFS.exe.missing | cut -d ' ' -f1`
		echo $exeMissCount | awk '{ printf "Total Missing: %3d .exec/links /\n", $1 }' | tee -a $rootFS.exe.log
		echo "$name# WARNING: $2 executables count [$fileGivenCount] is greater than $rootFS Root File System count [$filePresCount]!" | tee -a $rootFS.exe.log
	fi

	# remove .pr.txt from the $base
	base=`basename $2 .h`
	base=${base%".pr.txt"}
	if [ "$base" != "$rootFS" ]; then
		echo "$name# WARNING: Executables list file doesn't match rootFS !" | tee -a $rootFS.exe.log
	fi

	# clean up
	rm $2.s $rootFS.exe.used.* $rootFS.exe.unused.* $rootFS.exe.used_duplicate.short
fi

# clean up
rm $rootFS.exe.total.*
