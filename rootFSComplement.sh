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
# $0 : rootFSComplement.sh is a Linux Host based script that complements an input used/unused file list to rootFS file list.

# Output:
# A rootFS file list [if target rootFS folder is used]
# An unused/used file list [if specified] that complements used/unused one to the list of given rootFS folder or file list

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-r folder/file -used/-unused file {-e file} {-refed file}] | [-h]"
	echo "$name# Target RootFS file list and/or a complement file list builder"
	echo "$name# -r            : a rootFS descriptor: a folder or a file list"
	echo "$name# -used/-unused : a used/unused file list [optional if -r parameter is a target rootFS folder]"
	echo "$name# -e            : an optional excluded file list"
	echo "$name# -refed        : an optional referenced file list"
	echo "$name# -h            : display this help and exit"
}

# Function: flfc2LongS
# $1: inFile
# $2: outFile
# $3: patternFile
# $4: sort position
# $5: uniq sort
function flfc2LongS()
{
	flsh2lo $1 $3 $2

	local uniqS=
	test "$5" == "u" && uniqS="-u" || uniqS=""
	sort $uniqS -k$4 $2 -o $2
}

# Function: flNorm
# $1: inFile	- input file
# $2: vaFile	- validation file for the input file
# $3: rfsFile	- rootFS file
# $4: outFile	- output file
function flNorm()
{
	local inFile=$1
	local vaFile=$2
	local rfsFile=$3
	local outFile=$4
	# find duplicate and/or missing files in the unput file list
	nfi=$(fileFormat $inFile)
	if [ ! -e $inFile.short ]; then
		test ! "$nfi" -eq 1 && cat $inFile | tr -s ' ' | cut -d ' ' -f$nfi- | sort -k1 > $inFile.short || ln -sf $inFile $inFile.short
	fi
	
	test "$inFile" == "$vaFile" && nfv=$nfi || nfv=$(fileFormat $vaFile)
	
	nfr=$(fileFormat $rfsFile)
	if [ ! -e $rfsFile.short ]; then
		test ! "$nfr" -eq 1 && cat $rfsFile | tr -s ' ' | cut -d ' ' -f$nfr- | sort -k1 > $rfsFile.short || ln -s $rfsFile $rfsFile.short
	fi

	# find duplicate files in the unput file list
	uniq -d $inFile.short > $inFile.dups.short
	if [ -s $inFile.dups.short ]; then 
		if [ ! "$nfv" -eq 1 ]; then
			flfc2LongS $inFile.dups.short $inFile.dups $vaFile $nfv "u"
		else if [ ! "$nfr" -eq 1 ]; then
			flfc2LongS $inFile.dups.short $inFile.dups $rfsFile $nfr "u"
		fi
		fi
	fi
	sort -u $inFile.short > $outFile.short

	# find missing files in the unput file list
	comm -13 $rfsFile.short $outFile.short > $inFile.missing.short
	if [ -s $inFile.missing.short ]; then
		comm -23 $outFile.short $inFile.missing.short > $outFile.tmp.short
		mv $outFile.tmp.short $outFile.short

		if [ ! "$nfv" -eq 1 ]; then
			flfc2LongS $inFile.missing.short $inFile.missing $vaFile $nfv "u"
		else if [ ! "$nfr" -eq 1 ]; then
			flfc2LongS $inFile.missing.short $inFile.missing $rfsFile $nfr "u"
		fi
		fi
	fi

	if [ -s $inFile.dups.short ] || [ -s $inFile.missing.short ]; then 
		if [ ! "$nfv" -eq 1 ]; then
			flfc2LongS $outFile.short $outFile $vaFile $nfv "u"
		else if [ ! "$nfr" -eq 1 ]; then
			flfc2LongS $outFile.short $outFile $rfsFile $nfr "u"
		fi
		fi
	else
		if [ ! "$nfv" -eq 1 ]; then
			flfc2LongS $outFile.short $outFile $vaFile $nfv "u"
		else if [ ! "$nfr" -eq 1 ]; then
			flfc2LongS $outFile.short $outFile $rfsFile $nfr "u"
		else
			ln -s $inFile $outFile
		fi
		fi
	fi
}

# Function: flLog
# $1: baseFL	- base file list to output
# $2: usage	- used/unused/excluded/used+excl/uned-excl
# $3: logFile	- log file
function flLog()
{
	local baseFL=$1
	local usage=$2
	local logFile=$3
	
	if [ "$(fileFormat $baseFL)" -ne 1 ]; then
		cat $baseFL | awk -v usage="$usage" -v fileN="$baseFL" '{total += $5} END { printf "%-8s %-8s: %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", usage, \
		"original", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $logFile
	fi
	if [ -s $baseFL.applied ]; then
		local baseFLmd5=$(md5sum $baseFL | cut -d ' ' -f1)
		local baseFLappliedmd5=$(md5sum $baseFL.applied | cut -d ' ' -f1)
		if [ "$baseFLmd5" == "$baseFLappliedmd5" ]; then
			printf "%-8s %-8s: %5s files / %9s Bytes / %6s KB / %3s MB : %s\n" $usage "applied" "-\"\"-" "----\"----" "--\"\"--" "-\"-" $baseFL.applied | tee -a $logFile
		else
			cat $baseFL.applied | awk -v usage="$usage" -v fileN="$baseFL.applied" '{total += $5} END { printf "%-8s %-8s: %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", \
			usage, "applied", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $logFile
		fi
	fi
	
	if [ -s $baseFL.missing.short ] && [ -s $baseFL.dups ]; then
		cat $baseFL.dups     | awk -v usage="$usage" -v fileN="$baseFL.dups" '{total += $5} END { printf "%-8s %-8s: %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", \
		usage, "dups", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $logFile
		if [ -s $baseFL.missing ]; then 
			cat $baseFL.missing  | awk -v usage="$usage" -v fileN="$baseFL.missing" '{total += $5} END { printf "%-8s %-8s: %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", \
			usage, "missing", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $logFile
		else
			cat $baseFL.missing.short  | awk -v usage="$usage" -v fileN="$baseFL.missing.short" '{total += $5} END { printf "%-8s %-8s: %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", \
			usage, "missing", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $logFile
		fi
	else if [ -s $baseFL.missing.short ]; then
		if [ -s $baseFL.missing ]; then 
			cat $baseFL.missing  | awk -v usage="$usage" -v fileN="$baseFL.missing" '{total += $5} END { printf "%-8s %-8s: %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", \
			usage, "missing", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $logFile
		else
			cat $baseFL.missing.short  | awk -v usage="$usage" -v fileN="$baseFL.missing.short" '{total += $5} END { printf "%-8s %-8s: %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", \
			usage, "missing", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $logFile
		fi
	else if [ -s $baseFL.dups ]; then
		cat $baseFL.dups     | awk -v usage="$usage" -v fileN="$baseFL.dups" '{total += $5} END { printf "%-8s %-8s: %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", \
		usage, "dups", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $logFile
	fi
	fi
	fi
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/rootFSCommon.sh

rfs=
uFL=
eFL=
rfsDescr=
used=
while [ "$1" != "" ]; do
	case $1 in
		-r | --root )   shift
				[ -d "$1" ] && rfs="folder" || rfs="file"
				rfsDescr=$1
				;;
		-used )   	shift
				used="used"
				cmpl="unused"
				uFL=$1
				;;
		-unused )   	shift
				used="unused"
				cmpl="used"
				uFL=$1
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

if [ "$rfs" == "" ]; then
	echo "$name# ERROR : rootFS is not set!"
        usage
	exit
fi

if [ ! -e "$rfsDescr" ]; then
	echo "$name# ERROR : rootFS descriptor doesn't exist!"
        usage
	exit
fi

if [ "$uFL" == "" ] && [ "$rfs" == "file" ]; then
	echo "$name# ERROR : a used/unused file list is not set!"
        usage
	exit
fi

if [ ! -e "$uFL" ] && [ "$rfs" == "file" ]; then
	echo "$name# ERROR : $uFL file not found!"
        usage
	exit
fi

if [ "$eFL" != "" ] && [ ! -e $eFL ]; then
	echo "$name# ERROR : $eFL file not found!"
        usage
	exit
fi

if [ "$refedFL" != "" ] && [ ! -e $refedFL ]; then
	echo "$name# ERROR : $refedFL file not found!"
        usage
	exit
fi


startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

rFL=
rootFS=
if [ "$rfs" == "folder" ]; then
	if [ ! -e $rfsDescr/version.txt ]; then
		echo "$name# WARNING: $rfsDescr/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name" | tee -a $rootFS.cmpl.log
		rootFS=`basename $rfsDescr`
	else
		rootFS=`cat $rfsDescr/version.txt | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
	fi

	rFL=$rootFS.files.all
	$path/rootFSFLBuilder.sh -r $rfsFolder -o $rFL > /dev/null

else
	rootFS=`echo $rfsDescr | cut -d '.' -f1`
	rFL=$(flslfilter $rfsDescr)
fi

echo "$cmdline" > $rootFS.cmpl.log
echo "$name : rootFS = $rootFS : rootFS file list = $rFL : uFL = $uFL : eFL = $eFL : refedFL = $refedFL" | tee -a $rootFS.cmpl.log
cat $rFL | awk  -v fileN="$rFL" '{total += $5} END { printf "%-16s : %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", "rootFS total ", NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $rootFS.cmpl.log

if [ "$uFL" != "" ] && [ -s "$uFL" ]; then
	uFL=$(flslfilter $uFL)

	# check rFL file format
	nfr=$(fileFormat $rFL)
	test ! "$nfr" -eq 1 && cat $rFL | tr -s ' ' | cut -d ' ' -f$nfr- | sort > $rFL.short || ln -sf $rFL $rFL.short

	flNorm $uFL $uFL $rFL $uFL.applied

	eused=
	cFL="$eFL$refedFL"
	if [ "$cFL" != "" ]; then 
		[ "$eFL" != "" ] && eused="e"
		[ "$refedFL" != "" ] && eused="r$eused"
		eused="$eused$used"
		[ -e $uFL.$eused.short ] && rm $uFL.$eused.short
		for fileList in "$eFL" "$refedFL"; do
			[ "$fileList" == "" ] && continue
			fileList=$(flslfilter $fileList)
			flNorm $fileList $fileList $rFL $fileList.applied
			cat $fileList.applied.short >> $uFL.$eused.short
		done
		if [ "$used" == "used" ]; then
			cat $uFL.applied.short $uFL.$eused.short | sort  -o $uFL.$eused.short
		else
			sort $uFL.$eused.short -o $uFL.$eused.short
			comm -23 $uFL.applied.short $uFL.$eused.short > $uFL.$eused.tmp.short
			mv $uFL.$eused.tmp.short $uFL.$eused.short
		fi
		flfc2LongS $uFL.$eused.short $uFL.$eused $rFL $nfr ""
		flNorm $uFL.$eused $rFL $rFL $uFL.$eused.applied
		comm -23 $rFL.short $uFL.$eused.applied.short > $uFL.$cmpl.short
	else
		comm -23 $rFL.short $uFL.applied.short > $uFL.$cmpl.short
	fi
	
	if [ ! "$nfr" -eq 1 ]; then
		flfc2LongS $uFL.$cmpl.short $uFL.$cmpl $rFL $nfr "u"

		flLog $uFL $used $rootFS.cmpl.log

		if [ "$cFL" != "" ]; then
			[ "$eFL" != "" ] && flLog $eFL "excluded" $rootFS.cmpl.log
			[ "$refedFL" != "" ] && flLog $refedFL "refed" $rootFS.cmpl.log
			if [ "$used" == "used" ]; then
				flLog $uFL.$eused "used+re" $rootFS.cmpl.log
			else
				flLog $uFL.$eused "uned-re" $rootFS.cmpl.log
			fi
		fi

		cat $uFL.$cmpl | awk -v cmpl="$cmpl" -v fileN="$uFL.$cmpl" '{total += $5} END { printf "%-16s : %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", cmpl, NR, total, total/1024, total/(1024*1024), fileN }' | tee -a $rootFS.cmpl.log
	fi

	# clean up
	rm $rFL.*
	[ -e $uFL.$eused.short ] && rm $uFL.$eused.short
	if [ "$uFL" != "" ] && [ -s "$uFL" ]; then
		rm $uFL.short
		#[ -e $uFL.missing.short ] && rm $uFL.missing.short
		[ -e $uFL.applied.short ] && rm $uFL.applied.short
		[ -e $uFL.dups.short ] && rm $uFL.dups.short
		[ -e $uFL.$cmpl.short ] && rm $uFL.$cmpl.short
	fi
	if [ "$cFL" != "" ]; then
		[ -e $uFL.$eused.missing.short ] && rm $uFL.$eused.missing.short
		[ -e $uFL.$eused.applied.short ] && rm $uFL.$eused.applied.short
		[ -e $uFL.$eused.dups.short ] && rm $uFL.$eused.dups.short
		for fileList in "$eFL" "$refedFL"; do
			[ "$fileList" == "" ] && continue
			rm $fileList.short
			[ -e $fileList.missing.short ] && rm $fileList.missing.short
			[ -e $fileList.applied.short ] && rm $fileList.applied.short
			[ -e $fileList.dups.short ] && rm $fileList.dups.short
		done
	fi
else if [ "$uFL" != "" ] && [ ! -s "$uFL" ]; then
	echo "$name : Warning: $uFL file list is empty!" | tee -a $rootFS.cmpl.log
fi
fi

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60)) | tee -a $rootFS.cmpl.log

