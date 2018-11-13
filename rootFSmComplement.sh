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
# $0 : rootFSmComplement.sh is a Linux Host based script that complements a set of used/unused file lists to a given rootFS file list.

# Output:

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-f file] | [-h]"
	echo "$name# Usage : `basename $0 .sh` [-r file -u file {-e file} {-refed file}] | [-h]"
	echo "$name# Target RootFS unused files builder based on a given used file list desriptor"
	echo "$name# -r    : a target rootFS file list"
	echo "$name# -u    : a used file list  desriptor to describe a set of rootFS and used file lists"
	echo "$name# -e    : an optional excluded file list"
	echo "$name# -refed: an optional referenced file list"
	echo "$name# -o    : an optional settings flag : a - adjust for moved missing used files, c - analysis of the ufld contributors"
	echo "$name# -h    : display this help and exit"
}

# Function: flLog
# $1: fileName	- file list to print
# $2: fileDescr	- 
# $3: logFile	- log file
function flPrint()
{
	cat $1 | awk -v fileName="$1" -v fileDescr="$2" '{total += $5} END { printf "%-16s : %4d files / %9d Bytes / %6d KB / %3d MB : %s\n", fileDescr, NR, total, total/1024, total/(1024*1024), fileName }' | tee -a $3
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/rootFSCommon.sh

ufld=
contribsAnalysis=
adjustMovedFiles=y
while [ "$1" != "" ]; do
	case $1 in
		-r | --root )   shift
				rFL=$1
				;;
		-u | --ufld )   shift
				ufld=$1
				;;
		-o | --opts )   shift
				options=$1
				[ "${options#*c}" != "$options" ] && contribsAnalysis="y"
				[ "${options#*a}" != "$options" ] && adjustMovedFiles="y"
				;;
		-refed )   	shift
				refedFL=$1
				;;
		-e | --excl )   shift
				eFL=$1
				;;
		-h | --help )   usage
				exit
				;;
		* )             echo "$name# ERROR : unknown parameter in the command argument list!"
				usage
				exit 1
    esac
    shift
done

if [ ! -s "$rFL" ]; then
	echo "$name# ERROR : rootFS file list doesn't exist or empty!"
        usage
	exit
fi

if [ "$ufld" == "" ]; then
	echo "$name# ERROR : file descriptor is not set!"
        usage
	exit
fi

if [ ! -e "$ufld" ]; then
	echo "$name# ERROR : $ufld file descriptor doesn't exist or empty!"
	exit 1
fi

cFL="$eFL$refedFL"
reAnalysis=
if [ "$cFL" != "" ]; then
	for fileList in "$eFL" "$refedFL"; do
		if [ "$fileList" != "" ] && [ ! -e $fileList ]; then
			echo "$name# ERROR : $fileList file not found!"
			usage
			exit
		else if [ ! -s "$fileList" ]; then
			echo "$name# Warning : $fileList file list is empty!"
		else
			reAnalysis="y"
		fi
		fi
	done
fi

# validate file list descriptor entries:
# 1. rootFS file list; 2. rootFS used file list
cat $ufld | while read line
do
	ufldRootFS=`echo $line | tr -s ' ' | cut -d ' ' -f1`
	if [ ! -s "$ufldRootFS" ]; then
		echo "$name# ERROR : $ufld file descriptor's mandatory $ufldRootFS rootFS file list doesn't exist or empty!"
		exit 1
	fi

	ufldUsedFL=`echo $line | tr -s ' ' | cut -d ' ' -f2`
	if [ ! -s "$ufldUsedFL" ]; then
		echo "$name# ERROR : $ufld file descriptor's mandatory $ufldUsedFL used file list doesn't exist or empty!"
		exit 1
	fi
done

rootFS=`echo $rFL | cut -d '.' -f1`

echo "$cmdline" > $ufld.log
if [ "$reAnalysis" != "y" ]; then
	echo "$name: rootFS = $rootFS : rFL = $rFL : ufld = $ufld" | tee -a $ufld.log
else
	echo "$name: rootFS = $rootFS : rFL = $rFL : ufld = $ufld : eFL = $eFL : refedFL = $refed" | tee -a $ufld.log
fi

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
rFLFormat=$(fileFormat $rFL)

# build a superset of all used files based on entries of the used files list descriptor
iter=1
cat $ufld | while read line
do
	ufldUsedFL=`echo $line | tr -s ' ' | cut -d ' ' -f2`
	ufldUsedFLFormat=$(fileFormat $ufldUsedFL)
	if [ "$ufldUsedFLFormat" -eq 1 ]; then
		ln -sf $ufldUsedFL $ufld.used.$iter.short
	else
		cat $ufldUsedFL | tr -s ' ' | cut -d ' ' -f$ufldUsedFLFormat- | sort -k1 -o $ufld.used.$iter.short
	fi

	iter=`expr $iter + 1`
done

extglobStat=`shopt | grep extglob | cut  -f2`
shopt -s extglob

test -e $ufld.sused && rm $ufld.sused
for file in $ufld.used.+([0-9]).short
do
	cat $file >> $ufld.sused
done
sort -u $ufld.sused -o $ufld.sused

echo "Analysis of all used files:" | tee -a $ufld.log
path=$0
path=${path%/*}
$path/rootFSComplement.sh -r $rFL -used $ufld.sused | tee -a $ufld.log

# check for missing files
missingFiles=
if [ -s $ufld.sused.missing ] || [ -s $ufld.sused.missing.short ]; then
	echo "Analysis of missing files:" | tee -a $ufld.log
	missingFiles="y"
	if [ -s $ufld.sused.missing.short ]; then
		ln -sf $ufld.sused.missing.short $ufld.sused.missing.all.short
	else
		seusedmFLFormat=$(fileFormat $ufld.sused.missing)
		if [ "$seusedmFLFormat" -eq 1 ]; then 
			ln -sf $ufld.sused.missing $ufld.sused.missing.all.short
		else
			cat $ufld.sused.missing | tr -s ' ' | cut -d ' ' -f$seusedmFLFormat- | sort > $ufld.sused.missing.short
			ln -sf $ufld.sused.missing.short $ufld.sused.missing.all.short
		fi
	fi
	
	cat /dev/null > $ufld.sused.missing.all.basename
	cat $ufld.sused.missing.all.short | while read line
	do
		echo ${line##*/} >> $ufld.sused.missing.all.basename
	done
	sort -u $ufld.sused.missing.all.basename -o $ufld.sused.missing.all.basename
	
	# check for moved files
	flsh2lo $ufld.sused.missing.all.basename $rFL $ufld.sused.missing.moved
	
	cat /dev/null > $ufld.sused.missing.moved.basename
	if [ -s $ufld.sused.missing.moved ];  then
		cat $ufld.sused.missing.moved | while read line
		do
			echo ${line##*/} >> $ufld.sused.missing.moved.basename
		done
		sort $ufld.sused.missing.moved.basename | uniq -d > $ufld.sused.missing.moved.basename.dname
		if [ -s $ufld.sused.missing.moved.basename.dname ]; then
			flsh2lo $ufld.sused.missing.moved.basename.dname $rFL $ufld.sused.missing.moved.dname
		fi
		
		sort -u $ufld.sused.missing.moved.basename -o $ufld.sused.missing.moved.basename
	fi
	
	# check for removed files
	comm -13 $ufld.sused.missing.moved.basename $ufld.sused.missing.all.basename > $ufld.sused.missing.removed.basename
	flsh2lo $ufld.sused.missing.removed.basename $ufld.sused.missing.all.short $ufld.sused.missing.removed.short
	
	if [ -s $ufld.sused.missing.moved ]; then
		flPrint "$ufld.sused.missing.moved" "moved all" $ufld.log
	fi
	if [ -s $ufld.sused.missing.moved.dname ]; then
		flPrint "$ufld.sused.missing.moved.dname" "moved dups" $ufld.log
	fi
	if [ -s $ufld.sused.missing.removed.short ]; then
		flPrint "$ufld.sused.missing.removed.short" "removed" $ufld.log
	fi

	cat $ufld.sused.applied $ufld.sused.missing.moved | sort -k$rFLFormat -o $ufld.sused.tmp
	uniq -d $ufld.sused.tmp > $ufld.sused.missing.moved.redundant
	test -e $ufld.sused.missing.moved.applicable && rm $ufld.sused.missing.moved.applicable
	if [ -s $ufld.sused.missing.moved.redundant ]; then
		flPrint "$ufld.sused.missing.moved.redundant" "redundant" $ufld.log
		sed -e "$SPEC_CHAR_PATTERN" $ufld.sused.missing.moved.redundant | grep -w -v -f - $ufld.sused.missing.moved > $ufld.sused.missing.moved.applicable
	else
		test -s $ufld.sused.missing.moved && ln -s $ufld.sused.missing.moved $ufld.sused.missing.moved.applicable || touch $ufld.sused.missing.moved.applicable
		rm $ufld.sused.missing.moved.redundant	
	fi
	flPrint "$ufld.sused.missing.moved.applicable" "applicable" $ufld.log

	if [ "$adjustMovedFiles" == "y" ]; then
		# adjusting for applicable [moved used] files
		echo "adjusting for applicable [moved used] files:" | tee -a $ufld.log
		sort -u -k$rFLFormat $ufld.sused.tmp -o $ufld.asused
		$path/rootFSComplement.sh -r $rFL -used $ufld.asused | tee -a $ufld.log
	fi

	#clean up
	rm $ufld.sused.tmp
	rm $ufld.sused.missing.all.short
	rm $ufld.sused.missing.all.basename $ufld.sused.missing.moved.basename $ufld.sused.missing.removed.basename
	[ -e $ufld.sused.missing.moved.basename.dname ] && rm $ufld.sused.missing.moved.basename.dname
else
	missingFiles="n"
fi

# Analysis of the excluded and referenced files
if [ "$reAnalysis" == "y" ]; then
	echo "Analysis of the excluded files:" | tee -a $ufld.log
	if [ "$missingFiles" == "y" ]; then
		if [ "$adjustMovedFiles" == "y" ]; then
			ln -sf $ufld.asused.applied $ufld.aeused
		else
			ln -sf $ufld.sused.applied $ufld.aeused
		fi
	else
		ln -sf $ufld.sused $ufld.aeused
	fi

	reargs=
	[ -s "$eFL" ] && reargs="-e $eFL"
	[ -s "$refedFL" ] && reargs="$reargs -refed $refedFL"
	$path/rootFSComplement.sh -r $rFL -used $ufld.aeused $reargs | tee -a $ufld.log
fi

# Analysis of the ufld contributors
if [ "$contribsAnalysis" == "y" ]; then
	echo "Analysis of ufld contributors:" | tee -a $ufld.log
	if [ "$reAnalysis" == "y" ]; then
		ln -sf $ufld.aeused.applied $ufld.aeused
	else
		if [ "$missingFiles" == "y" ]; then
			if [ "$adjustMovedFiles" == "y" ]; then
				ln -sf $ufld.asused.applied $ufld.aeused
			else
				ln -sf $ufld.sused.applied $ufld.aeused
			fi
		else
			ln -sf $ufld.sused $ufld.aeused
		fi
	fi
	
	if [ -e $ufld.aeused ];   then
		cat $ufld.aeused | tr -s ' ' | cut -d ' ' -f$rFLFormat | sort > $ufld.aeused.short

		printf "#  %-40s %-10s  %-14s  %-20s  %-18s  %-13s\n" "RootFS Name" "TotalFiles" "TotalSize, MB" "Used/Cntr/UniqFiles" "Used/CntrSize, MB" "Used/CntrFileRatio" | tee -a $ufld.log
		rootFSDscr=$(cat $rFL | awk '{total += $5} END { printf "%d %d", NR, total/(1024*1024) }')
		rootFSFiles=$(echo $rootFSDscr | tr -s ' ' | cut -d ' ' -f1)
		rootFSSize=$(echo $rootFSDscr | tr -s ' ' | cut -d ' ' -f2)
		rootFSUsed=$(cat $ufld.aeused | awk '{total += $5} END { printf "%d %d", NR, total/(1024*1024) }')
		rootFSUsedFiles=$(echo $rootFSUsed | tr -s ' ' | cut -d ' ' -f1)
		rootFSUsedSize=$(echo $rootFSUsed | tr -s ' ' | cut -d ' ' -f2)
		printf "*  %-40s %-10d  %-14d  %4d/%4d/%-10d  %3d/%-14d  %s\n" $rootFS $rootFSFiles $rootFSSize $rootFSUsedFiles $rootFSUsedFiles $rootFSUsedFiles $rootFSUsedSize $rootFSUsedSize "100/100" | tee -a $ufld.log

		# find all existing contributors
		iter=1
		for file in $ufld.used.+([0-9]).short
		do
			sort $file -o $file
			comm -12 $file $ufld.aeused.short > $ufld.ceused.$iter.short
			flsh2lo $ufld.ceused.$iter.short $rFL $ufld.ceused.$iter

			iter=`expr $iter + 1`
		done

		# find common files among all existing contributors
		cat $ufld.ceused.+([0-9]) | sort -k$rFLFormat | uniq -d > $ufld.ceused.common

		# find unique files among all existing contributors
		cat $ufld.ceused.+([0-9]) | sort -k$rFLFormat | uniq -u > $ufld.ceused.uniq
		cat $ufld.ceused.uniq | tr -s ' ' | cut -d ' ' -f$rFLFormat > $ufld.ceused.uniq.short

		iter=1
		for file in $ufld.ceused.+([0-9])
		do
			cat $file | tr -s ' ' | cut -d ' ' -f$rFLFormat > $file.short
			comm -12 $file.short $ufld.ceused.uniq.short > $ufld.ceused.uniq.$iter.short
			flsh2lo $ufld.ceused.$iter.short $ufld.ceused.uniq $ufld.ceused.uniq.$iter

			iter=`expr $iter + 1`
		done

		iter=1
		cat $ufld | while read line
		do
			ufldRootFS=`echo $line | tr -s ' ' | cut -d ' ' -f1`
			ufldRootFSName=`echo ${ufldRootFS##*/} | cut -d '.' -f1`
			ufldRootFSDscr=$(cat $ufldRootFS | awk '{total += $5} END { printf "%d %d", NR, total/(1024*1024) }')
			ufldRootFSFiles=$(echo $ufldRootFSDscr | tr -s ' ' | cut -d ' ' -f1)
			ufldRootFSSize=$(echo $ufldRootFSDscr | tr -s ' ' | cut -d ' ' -f2)

			ufldUsedFL=`echo $line | tr -s ' ' | cut -d ' ' -f2`
			ufldUsedFLDscr=$(cat $ufldUsedFL | awk '{total += $5} END { printf "%d %d", NR, total/(1024*1024) }')
			ufldUsedFLFiles=$(echo $ufldUsedFLDscr | tr -s ' ' | cut -d ' ' -f1)
			ufldUsedFLSize=$(echo $ufldUsedFLDscr | tr -s ' ' | cut -d ' ' -f2)

			cntrUsedFLDscr=$(cat $ufld.ceused.$iter | awk '{total += $5} END { printf "%d %d", NR, total/(1024*1024) }')
			cntrUsedFLFiles=$(echo $cntrUsedFLDscr | tr -s ' ' | cut -d ' ' -f1)
			cntrUsedFLSize=$(echo $cntrUsedFLDscr | tr -s ' ' | cut -d ' ' -f2)

			cntrUniqFLFiles=$(wc -l $ufld.ceused.uniq.$iter.short | cut -d ' ' -f1)
			printf "%d. %-40s %-10d  %-14d  %4d/%4d/%-10d  %3d/%-14d  %3d/%-11d\n" \
			$iter \
			$ufldRootFSName $ufldRootFSFiles $ufldRootFSSize $ufldUsedFLFiles $cntrUsedFLFiles $cntrUniqFLFiles $ufldUsedFLSize $cntrUsedFLSize \
			$((ufldUsedFLFiles*100/rootFSUsedFiles)) $((cntrUsedFLFiles*100/rootFSUsedFiles)) | tee -a $ufld.log

			iter=`expr $iter + 1`
		done
		
		#clean up
		rm $ufld.aeused.short
		rm $ufld.ceused.+([0-9]) $ufld.ceused.+([0-9]).short $ufld.ceused.uniq $ufld.ceused.uniq.short $ufld.ceused.uniq.+([0-9]).short
	fi
fi

# clean up
rm $ufld.used.*.short
test -e $rootFS.cmpl.log && rm $rootFS.cmpl.log

test "$extglobStat" == "off" && shopt -u extglob

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60)) | tee -a $ufld.log

