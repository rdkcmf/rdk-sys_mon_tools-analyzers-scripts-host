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
# $0 : soAnalyzer.sh is a Linux Host based script to analyze the usage of shared library objects in ELF format.
# $1 : param1 is rootfs [ramdisk] folder to be analyzed
# $2 : param2 is an optional input file with a list of "used" shared library objects with full path.

# Setup:
# 1. Set USE_SYSRES_PLATFORM to use {BROADCOM | CANMORE}. Ex.: export USE_SYSRES_PLATFORM=broadcom
# 2. Set platforms's SDK. Ex.:
#    export WORK_DIR=<WORK_DIR>/workRNG150/
#    source $WORK_DIR/../SDK/Scripts/setBcmEnv.sh
# 3. Run soAnalyzer.sh. Ex.: ./soAnalyzer.sh <path to rootFS/ramdisk> [<path to a file>] 2>/dev/null
# 4. The output files: 
#    1. <rootFS baseName>.so.total  - a list of all rootFS shared object library files
#    2. <rootFS baseName>.so.used   - a list of "used" shared object library files
#    3. <rootFS baseName>.so.unused - a list of "unused" shared object library files

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
	echo "$name# param2: an optional input file with a list of used shared library objects with full path"
	exit
fi

if [ -d "$1" ]; then
	if [ ! -e $1/version.txt ]; then
		echo "$name# WARNING : $1/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name"
		rootFS=`basename $1`
	else
		rootFS=`cat $1/version.txt | grep imagename | cut -d ':' -f2`
	fi
	#echo "$name# rootFS  : $rootFS"
	find $1 -type f -exec ls -la {} \; | grep "\bso" | sort -u -k9 > $rootFS.so.total.all
else
	echo "$name# Error   : param1 is not a folder!"
	exit
fi

if [ -e $rootFS.so.total ]; then
	rm $rootFS.so.total
fi
if [ -e $rootFS.so.total.full ]; then
	rm $rootFS.so.total.full
fi

sub=$1
sub=${sub%/}
cat $rootFS.so.total.all | while read line
do
	file=`echo "$line" | tr -s ' ' | cut -d ' ' -f9`
	#echo $file
	type=`$ELFREADER -h $file | grep "Type:" | tr -s ' ' | cut -d ' ' -f2- | grep "Type: DYN (Shared object file)"`
	if [ "$type" != "" ] ; then
		echo -e "${line%$sub*}\c" >> $rootFS.so.total.full; echo ${line#*$sub} >> $rootFS.so.total.full
	fi
done
sort -u -k9 $rootFS.so.total.full > $rootFS.so.total
 
if [ -e $rootFS.so.log ]; then
	rm $rootFS.so.log
fi

echo "File count   :" `wc -l $rootFS.so.total.all | cut -d ' ' -f1` | tee -a $rootFS.so.log
echo ".so  count   :" `wc -l $rootFS.so.total     | cut -d ' ' -f1` | tee -a $rootFS.so.log

# total
cat $rootFS.so.total | awk '{total += $5} END { printf "Total inImage: %3d shared libs / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.so.log

if [ "$2" != "" ]; then
	dos2unix -db $2
	sort -u -k1 $2 > $2.s

	# total used
	#grep -f $2.s $rootFS.so.total > $rootFS.so.used
	if [ -e $rootFS.so.used.% ]; then
		rm $rootFS.so.used.%
	fi
	cat $2.s | while read line
	do
		file=$line
		grep -w "$file\$" $rootFS.so.total >> $rootFS.so.used.%
		#echo $file >> $rootFS.so.used.%%
	done
	sort -u -k9 $rootFS.so.used.% > $rootFS.so.used
	cat $rootFS.so.used | awk '{total += $5} END { printf "Total Used   : %3d shared libs / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.so.log

	# total unused
	cat $rootFS.so.total | tr -s ' ' | cut -d ' ' -f9 > $rootFS.so.total.short
	comm -23 $rootFS.so.total.short $2.s > $rootFS.so.unused.short
	#grep -f $rootFS.so.unused.short $rootFS.so.total > $rootFS.so.unused
	if [ -e $rootFS.so.unused.% ]; then
		rm $rootFS.so.unused.%
	fi
	cat $rootFS.so.unused.short | while read line
	do
		file=$line
		grep -w "$file\$" $rootFS.so.total >> $rootFS.so.unused.%
		#echo $file >> $rootFS.so.unused.%%
	done
	sort -u -k9 $rootFS.so.unused.% > $rootFS.so.unused
	cat $rootFS.so.unused | tr -s ' ' | cut -d ' ' -f9 > $rootFS.so.unused.%.short
	cat $rootFS.so.unused | awk '{total += $5} END { printf "Total Unused : %3d shared libs / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.so.log

	# total used duplicate
	cat $2 | awk -F"/" '{print $NF}' | sort | uniq -d > $rootFS.so.used_duplicate.short
	soDuplCount=`wc -l $rootFS.so.used_duplicate.short`
	if [ "$soDuplCount" != "0" ]; then
		if [ -e $rootFS.so.used_duplicate ]; then
			rm $rootFS.so.used_duplicate
		fi
		cat $rootFS.so.used_duplicate.short | while read line
		do
			grep "$line\$" $rootFS.so.total >> $rootFS.so.used_duplicate
		done
		#grep -f $rootFS.so.used_duplicate.short $rootFS.so.total > $rootFS.so.used_duplicate
		cat $rootFS.so.used_duplicate | awk '{total += $5} END { printf "Total UsedDup: %3d shared libs / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.so.log
	fi

	# total given
	soSuplCount=`wc -l $2.s | cut -d ' ' -f1`
	echo $soSuplCount | awk '{ printf "Total Given  : %3d shared libs /\n", $1 }' | tee -a $rootFS.so.log

	# total missing
	soPresCount=`wc -l $rootFS.so.used | cut -d ' ' -f1`
	if [ "$soSuplCount" -gt "$soPresCount" ]; then
		cat $rootFS.so.used | tr -s ' ' | cut -d ' ' -f9 > $rootFS.so.used.short
		comm -23 $2.s $rootFS.so.used.short > $rootFS.so.missing
		soMissCount=`wc -l $rootFS.so.missing | cut -d ' ' -f1`
		echo $soMissCount | awk '{ printf "Total Missing: %3d shared libs /\n", $1 }' | tee -a $rootFS.so.log
		echo "$name# WARNING : $2 shared libs count [$soSuplCount] is greater than $rootFS Root File System count [$soPresCount]!"
	fi

	# remove .so.txt from the $procSo
	procSo=`basename $2 .h`
	procSo=${procSo%".so.txt"}
	#echo "$name# procSo  : $procSo"
	if [ "$procSo" != "$rootFS" ]; then
		echo "$name# WARNING : Shared objects list file doesn't match rootFS !" | tee -a $rootFS.so.log
	fi

	# clean up
	rm $2.s $rootFS.so.used.* $rootFS.so.unused.* $rootFS.so.used_duplicate.short
fi

# clean up
rm $rootFS.so.total.*
