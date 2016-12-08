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
# $0 : rootFSCompare.sh is a Linux Host based script that compares 2 rootFS given as 2 folders or file lists.

# Output:

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-r1 folder/file -r2 folder/file] | [-i] | [-h]"
	echo "$name# Two target RootFS comparison"
	echo "$name# -r1   : a 1st rootFS descriptor: a folder or a file list"
	echo "$name# -r2   : a 2nd rootFS descriptor: a folder or a file list"
	echo "$name# -i    : an optional md5sum-based identical file analysis between rootFS1 & rootFS2 "
	echo "$name# -h    : display this help and exit"
}

# Function: flLog
# $1: fileName	- file list to print
# $2: fileDescr	- 
# $3: logFile	- log file
function flPrint()
{
	if [ -s $1 ]; then
		cat $1 | awk -v fileName="$1" -v fileDescr="$2" '{total += $5} END { printf "%-16s : %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", fileDescr, NR, total, total/1024, total/(1024*1024), fileName }' | tee -a $3
	else
		printf "%-16s : %5d files / %9d Bytes / %6d KB / %3d MB :\n" "$2" 0 0 0 0 | tee -a $3
	fi
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/rootFSCommon.sh

identicalFileAnalysis=
while [ "$1" != "" ]; do
	case $1 in
		-r1| --root )   shift
				if [ -d "$1" ]; then
					rfs1="folder"
				else
					rfs1="file"
				fi
				rfsDescr1=$1
				;;
		-r2| --root )   shift
				if [ -d "$1" ]; then
					rfs2="folder"
				else
					rfs2="file"
				fi
				rfsDescr2=$1
				;;
		-i | --ident )  shift
				identicalFileAnalysis="y"
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

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

i=1
for rfs in "$rfs1" "$rfs2"
do
	if [ "$rfs" == "" ]; then
		echo "$name# ERROR : rootFS$i is not set!"
		usage
		exit
	fi
	i=`expr $i + 1`
done

i=1
for rfsDescr in "$rfsDescr1" "$rfsDescr2"
do
	if [ ! -e "$rfsDescr" ]; then
		echo "$name# ERROR : rootFS$i descriptor doesn't exist!"
		usage
		exit
	fi
	i=`expr $i + 1`
done

if [ "$rfs1" != "folder" ] || [ "$rfs2" != "folder" ] && [ "$identicalFileAnalysis" == "y" ]; then
	echo "$name# WARNING: $rfsDescr1 or $rfsDescr2 is not a rootFS folder! Cannot conduct identical file analysis!" 
	identicalFileAnalysis=
fi

rootFS1pstf=1.files.all
rootFS1=$(rootFSFLBV $rfs1 $rfsDescr1 "$rootFS1pstf")
rootFS2pstf=2.files.all
rootFS2=$(rootFSFLBV $rfs2 $rfsDescr2 "$rootFS2pstf")

if [ "$rootFS1" == "$rootFS2" ]; then
	rootFS1=$rootFS1.1
	rootFS2=$rootFS2.2
else
	[ -e $rootFS1.$rootFS1pstf ] && mv $rootFS1.$rootFS1pstf $rootFS1.files.all
	[ -e $rootFS2.$rootFS2pstf ] && mv $rootFS2.$rootFS2pstf $rootFS2.files.all
fi

[ "$rfs1" == "folder" ] && rFL1=$rootFS1.files.all || rFL1=$rfsDescr1
[ "$rfs2" == "folder" ] && rFL2=$rootFS2.files.all || rFL2=$rfsDescr2

[ "$identicalFileAnalysis" == "y" ] && echo "identical File Analysis = y"
echo "$cmdline" > $rootFS1.$rootFS2.cmp.log
i=1
for rootFS in "$rootFS1" "$rootFS2"
do
	echo "rootFS #$i : $rootFS" | tee -a $rootFS1.$rootFS2.cmp.log
	i=`expr $i + 1`
done

fllo2sh $rFL1 $rFL1.short
fllo2sh $rFL2 $rFL2.short

rootFSTotal1=$(flPrint $rFL1 "rootFS #1 total   " $rootFS1.$rootFS2.cmp.log)
rootFSTotal2=$(flPrint $rFL2 "rootFS #2 total   " $rootFS1.$rootFS2.cmp.log)
echo "$rootFSTotal1"
echo "$rootFSTotal2"

comm -12 $rFL1.short $rFL2.short > $rootFS1.$rootFS2.comm.short
flsh2lo $rootFS1.$rootFS2.comm.short $rFL1 $rootFS1.$rootFS2.comm.1
flsh2lo $rootFS1.$rootFS2.comm.short $rFL2 $rootFS1.$rootFS2.comm.2

comm -23 $rFL1.short $rFL2.short > $rootFS1.$rootFS2.spec.1.short
flsh2lo $rootFS1.$rootFS2.spec.1.short $rFL1 $rootFS1.$rootFS2.spec.1

comm -13 $rFL1.short $rFL2.short > $rootFS1.$rootFS2.spec.2.short
flsh2lo $rootFS1.$rootFS2.spec.2.short $rFL2 $rootFS1.$rootFS2.spec.2

rootFSComm1=$(flPrint $rootFS1.$rootFS2.comm.1 "rootFS #1 common  " $rootFS1.$rootFS2.cmp.log)
rootFSComm2=$(flPrint $rootFS1.$rootFS2.comm.2 "rootFS #2 common  " $rootFS1.$rootFS2.cmp.log)
echo "$rootFSComm1"
echo "$rootFSComm2"

rootFSSpec1=$(flPrint $rootFS1.$rootFS2.spec.1 "rootFS #1 specific" $rootFS1.$rootFS2.cmp.log)
rootFSSpec2=$(flPrint $rootFS1.$rootFS2.spec.2 "rootFS #2 specific" $rootFS1.$rootFS2.cmp.log)
echo "$rootFSSpec1"
echo "$rootFSSpec2"

echo "rootFS #1-#2 total/common/specific file analysis :" | tee -a $rootFS1.$rootFS2.cmp.log
# RootFS #1 and #2 total file and size differencies
rootFS1File=$(echo $rootFSTotal1 | tr -s ' ' | cut -d ' ' -f5)
rootFS1Size=$(echo $rootFSTotal1 | tr -s ' ' | cut -d ' ' -f8)
rootFS2File=$(echo $rootFSTotal2 | tr -s ' ' | cut -d ' ' -f5)
rootFS2Size=$(echo $rootFSTotal2 | tr -s ' ' | cut -d ' ' -f8)

diffSize=$((rootFS1Size-rootFS2Size))
printf "rootFS #1-#2 total : %5d files / %9d Bytes / %6d KB / %3d MB\n" $((rootFS1File-rootFS2File)) $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a $rootFS1.$rootFS2.cmp.log

# RootFS #1 and #2 common file and size differencies
rootFS1File=$(echo $rootFSComm1 | tr -s ' ' | cut -d ' ' -f5)
rootFS1Size=$(echo $rootFSComm1 | tr -s ' ' | cut -d ' ' -f8)
rootFS2File=$(echo $rootFSComm2 | tr -s ' ' | cut -d ' ' -f5)
rootFS2Size=$(echo $rootFSComm2 | tr -s ' ' | cut -d ' ' -f8)

diffSize=$((rootFS1Size-rootFS2Size))
printf "rootFS #1-#2 comm  : %5d files / %9d Bytes / %6d KB / %3d MB\n" $((rootFS1File-rootFS2File)) $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a $rootFS1.$rootFS2.cmp.log

# RootFS #1 and #2 specific file and size differencies
rootFS1File=$(echo $rootFSSpec1 | tr -s ' ' | cut -d ' ' -f5)
rootFS1Size=$(echo $rootFSSpec1 | tr -s ' ' | cut -d ' ' -f8)
rootFS2File=$(echo $rootFSSpec2 | tr -s ' ' | cut -d ' ' -f5)
rootFS2Size=$(echo $rootFSSpec2 | tr -s ' ' | cut -d ' ' -f8)

diffSize=$((rootFS1Size-rootFS2Size))
printf "rootFS #1-#2 spec  : %5d files / %9d Bytes / %6d KB / %3d MB\n" $((rootFS1File-rootFS2File)) $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a $rootFS1.$rootFS2.cmp.log

echo "rootFS #1-#2 common changed/not-changed file analysis :" | tee -a $rootFS1.$rootFS2.cmp.log
paste $rootFS1.$rootFS2.comm.1 $rootFS1.$rootFS2.comm.2 | awk -v r1=$rootFS1 -v r2=$rootFS2 '{diff = $5-$14} \
{ if (diff != 0) \
        { \
		printf "%9d B / %6d KB / %3d MB : %8.5f : %s %s %s %s %8d %s %s %s : %s %s %s %s %8d %s %s %s : %s\n", \
		diff, diff/1024, diff/(1024*1024), $5/$14, $1, $2, $3, $4, $5, $6, $7, $8, $10, $11, $12, $13, $14, $15, $16, $17, $9 | "sort -k1 -rn -o comm.1-2.change.diff"; \
		printf "%s %s %s %s %8d %s %s %s %s\n", $1,   $2,  $3,  $4,  $5,  $6,  $7,  $8,  $9 > "comm.1-2.change.1"; \
		printf "%s %s %s %s %8d %s %s %s %s\n", $10, $11, $12, $13, $14, $15, $16, $17, $18 > "comm.1-2.change.2"  \
	} \
  else \
        { \
		printf "%s %s %s %s %8d %s %s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 | "sort -k9 -o comm.1-2.eql" \
	} \
}'

if [ -e comm.1-2.change.diff ]; then
	mv comm.1-2.change.diff $rootFS1.$rootFS2.comm.1-2.change.diff
	mv comm.1-2.change.1 $rootFS1.$rootFS2.comm.1-2.change.1
	mv comm.1-2.change.2 $rootFS1.$rootFS2.comm.1-2.change.2
	cat $rootFS1.$rootFS2.comm.1-2.change.diff | awk -v file="$rootFS1.$rootFS2.comm.1-2.change.diff" '{total += $1} END { printf "rootFS #1-#2 diff  : %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", NR, total, total/1024, total/(1024*1024), file }' | tee -a $rootFS1.$rootFS2.cmp.log
	flPrint $rootFS1.$rootFS2.comm.1-2.change.1    "rootFS #1-#2 ch #1" $rootFS1.$rootFS2.cmp.log
	flPrint $rootFS1.$rootFS2.comm.1-2.change.2    "rootFS #1-#2 ch #2" $rootFS1.$rootFS2.cmp.log
fi
if [ -e comm.1-2.eql ]; then
	mv comm.1-2.eql $rootFS1.$rootFS2.comm.1-2.eql
	flPrint $rootFS1.$rootFS2.comm.1-2.eql   "rootFS #1-#2 eqlen" $rootFS1.$rootFS2.cmp.log
fi

# identical file analysis
if [ "$identicalFileAnalysis" == "y" ]; then
	fllo2sh $rootFS1.$rootFS2.comm.1-2.eql $rootFS1.$rootFS2.comm.1-2.eql.short
	
	i=1
	for rfsDescr in "$rfsDescr1" "$rfsDescr2"
	do
		rfsFolderPath=${rfsDescr%/}
		[ -e $rootFS1.$rootFS2.comm.1-2.eql.$i.md5sum ] && rm $rootFS1.$rootFS2.comm.1-2.eql.$i.md5sum
		cat $rootFS1.$rootFS2.comm.1-2.eql.short | while read line
		do
			line=${line#*/}
			md5sum "$rfsFolderPath/$line" | cut -d ' ' -f1 >> $rootFS1.$rootFS2.comm.1-2.eql.$i.md5sum
		done
		paste -d ' ' $rootFS1.$rootFS2.comm.1-2.eql.$i.md5sum $rootFS1.$rootFS2.comm.1-2.eql.short > $rootFS1.$rootFS2.comm.1-2.eql.$i.md5sum.short

		i=`expr $i + 1`
	done

	cat $rootFS1.$rootFS2.comm.1-2.eql.1.md5sum.short $rootFS1.$rootFS2.comm.1-2.eql.2.md5sum.short | sort -n | uniq -d > $rootFS1.$rootFS2.comm.1-2.eql.md5sum.short
	cat $rootFS1.$rootFS2.comm.1-2.eql.md5sum.short | cut -d ' ' -f2 | sort -o $rootFS1.$rootFS2.comm.1-2.eql.ident.short
	flsh2lo $rootFS1.$rootFS2.comm.1-2.eql.ident.short $rFL1 $rootFS1.$rootFS2.comm.1-2.eql.ident
	flPrint $rootFS1.$rootFS2.comm.1-2.eql.ident "rootFS #1-#2 ident" $rootFS1.$rootFS2.cmp.log
	
	comm -23 $rootFS1.$rootFS2.comm.1-2.eql.short $rootFS1.$rootFS2.comm.1-2.eql.ident.short > $rootFS1.$rootFS2.comm.1-2.eql.diff.short
	flsh2lo $rootFS1.$rootFS2.comm.1-2.eql.diff.short $rFL1 $rootFS1.$rootFS2.comm.1-2.eql.diff
	flPrint $rootFS1.$rootFS2.comm.1-2.eql.diff  "rootFS #1-#2 diff " $rootFS1.$rootFS2.cmp.log
	
	rm $rootFS1.$rootFS2.comm.1-2.eql.short $rootFS1.$rootFS2.comm.1-2.eql.md5sum.short
	rm $rootFS1.$rootFS2.comm.1-2.eql.[1-2].md5sum* $rootFS1.$rootFS2.comm.1-2.eql.ident.short $rootFS1.$rootFS2.comm.1-2.eql.diff.short
fi

# clean up
rm $rFL1.short $rFL2.short
rm $rootFS1.$rootFS2.comm.short $rootFS1.$rootFS2.spec.1.short $rootFS1.$rootFS2.spec.2.short
[ ! -s $rootFS1.$rootFS2.spec.1 ] && rm $rootFS1.$rootFS2.spec.1
[ ! -s $rootFS1.$rootFS2.spec.2 ] && rm $rootFS1.$rootFS2.spec.2
if [ -e comm.1-2.change.diff ]; then
	[ ! -s $rootFS1.$rootFS2.comm.1-2.change.1  ] && rm $rootFS1.$rootFS2.comm.1-2.change.1
	[ ! -s $rootFS1.$rootFS2.comm.1-2.change.2  ] && rm $rootFS1.$rootFS2.comm.1-2.change.2
fi
if [ -e comm.1-2.eql ]; then
	[ ! -s $rootFS1.$rootFS2.comm.1-2.eql ] && rm $rootFS1.$rootFS2.comm.1-2.eql
fi

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

