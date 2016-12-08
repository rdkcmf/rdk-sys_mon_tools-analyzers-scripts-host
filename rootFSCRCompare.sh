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
# $0 : rootFSCRCompare.sh is a Linux Host based script that compares rootFS regular files compression schemes

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-r folder] [-cs1 -cs2] | [-h]"
	echo "$name# RootFS regular files compression scheme comparator"
	echo "$name# -r    : a rootFS folder"
	echo "$name# -cs1  : a compression scheme #1 in a format compression algorithm.level: -ca.cl"
	echo "$name# -cs2  : a compression scheme #2 in a format compression algorithm.level: -ca.cl"
	echo "$name# -crt  : a threshold for a ratio of cs1/cs2 compression ratios in a format : -x.y"
	echo "$name# -h    : display this help and exit"
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/rootFSCommon.sh

crt=
while [ "$1" != "" ]; do
	case $1 in
		-r | --root )	shift
				rfs=$1
				;;
		-cs1 )		shift
				cs1=$1
				;;
		-cs2 )		shift
				cs2=$1
				;;
		-crt )		shift
				crt=$1
				;;
		-h | --help )	usage
				exit
				;;
		* )		echo "$name# ERROR : unknown parameter in the command argument list!"
				usage
				exit 1
	esac
	shift
done

if [ ! -e $rfs/version.txt ]; then
	rootFS=`basename $rfs`
	echo "$name# WARNING: $rfs/version.txt file is not present. Cannot retrieve version info. Using $rfs base name" | tee -a $rootFS.crc.log
else
	rootFS=`cat $rfs/version.txt | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
fi

echo "$cmdline" > $rootFS.crc.$cs1.$cs2.log
echo "$name   : rootFS folder     = $rfs"    | tee -a $rootFS.crc.$cs1.$cs2.log
echo "$name   : rootFS            = $rootFS" | tee -a $rootFS.crc.$cs1.$cs2.log
echo "$name   : compression #1    = $cs1" | tee -a $rootFS.crc.$cs1.$cs2.log
echo "$name   : compression #2    = $cs2" | tee -a $rootFS.crc.$cs1.$cs2.log
[ "$crt" != "" ] && echo "$name   : cr#1 / cr#2 thold = $crt" | tee -a $rootFS.crc.$cs1.$cs2.log
startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

i=1
rFL=$rootFS.cra.files.all
for cs in "$cs1" "$cs2"
do
	ca=${cs%.*}
	cl=${cs#*.}
	if [ "$ca" == "" ] || [ "$cl" == "" ]; then
		echo "$name# ERROR : Compression #$i $ca/$cl is not set!"
		usage
		exit
	else
		$path/rootFSCRAnalyszer.sh -r $rfs -ca $ca -cl $cl > /dev/null
		if [ ! -s "$rFL.$cs.stats" ]; then
			echo "$name# ERROR : $path/rootFSCRAnalyszer.sh failed to create $rFL.$cs.stats !"
			exit
		fi
		sed 's/^ *//' $rFL.$cs.stats | tr -s ' ' > $rFL.$cs.stats.tmp
	fi
	i=`expr $i + 1`
done

if [ $crt != "" ]; then
	: > $rFL.$cs1.$cs2.stats.greater.$crt
	: > $rFL.$cs1.$cs2.stats.less.$crt
	: > $rFL.$cs1.$cs2.stats.equal.$crt
fi
join -j 13 $rFL.$cs1.stats.tmp $rFL.$cs2.stats.tmp -o 1.1,1.2,1.3,1.4,2.1,2.2,2.3,2.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11,1.12,1.13 | awk -v base=$rFL.$cs1.$cs2.stats -v thr=$crt '\
	{ \
		if (thr != "") {
			crt= $7/$3; \
			if (crt > thr) {
				lengthGreater++; sizeGreaterComprTotal+=$3; sizeGreaterUnComprTotal+=$7; \
				printf "%5.4f %8d : %5s %8s %9s %s %5s %8s %9s %s %s %s %s %s %9s %s %s %s %s\n", crt, $7-$3, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17 >> base".greater."thr; \
			} else if (crt < thr) {
				lengthLess++; sizeLessComprTotal+=$3; sizeLessUnComprTotal+=$7; \
				printf "%5.4f %8d : %5s %8s %9s %s %5s %8s %9s %s %s %s %s %s %9s %s %s %s %s\n", crt, $3-$7, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17 >> base".less."thr; \
			} else {
				lengthEqual++; sizeEqualComprTotal+=$3; sizeEqualUnComprTotal+=$7; \
				printf "%5.4f %8d : %5s %8s %9s %s %5s %8s %9s %s %s %s %s %s %9s %s %s %s %s\n", crt, 0, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17 >> base".equal."thr; \
			}
		}
		printf "%5s %8s %9s %s %5s %8s %9s %s %s %s %s %s %9s %s %s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17; \
	}
	function total (len, sizeComprTotal, sizeUnComprTotal, filename) {
		ratio=-1; \
		if (sizeComprTotal != 0) ratio=sizeUnComprTotal/sizeComprTotal; \
		if (sizeUnComprTotal != 0) { \
			printf "%d %5.2f %8.2f%% %9d %9d\n", len, ratio, (sizeComprTotal/sizeUnComprTotal)*100, sizeComprTotal, sizeUnComprTotal > filename".total"; \
		} else {
			printf "%d %5.2f %8s%% %9d %9d\n", len, 0, "Inf", sizeComprTotal, 0 > filename".total"; \
		}
	}
	END { \
		total(lengthGreater, sizeGreaterComprTotal, sizeGreaterUnComprTotal, base".greater."thr); \
		total(lengthLess, sizeLessComprTotal, sizeLessUnComprTotal, base".less."thr); \
		total(lengthEqual, sizeEqualComprTotal, sizeEqualComprTotal, base".equal."thr); \
	}' > $rFL.$cs1.$cs2.stats

# General numeric reverse sort in descending order by compressed/uncompressed value
sort -rg -k2,3 $rFL.$cs1.$cs2.stats -o $rFL.$cs1.$cs2.stats.rgk23

# Output
grep -v rootFSCRAnalyszer.sh $rootFS.cra.$cs1.log | grep -v "rootFS " | tee -a $rootFS.crc.$cs1.$cs2.log
grep -v rootFSCRAnalyszer.sh $rootFS.cra.$cs2.log | grep -v "rootFS " | tee -a $rootFS.crc.$cs1.$cs2.log

if [ $crt != "" ]; then
	sort -rgk1,1 $rFL.$cs1.$cs2.stats.greater.$crt -o $rFL.$cs1.$cs2.stats.greater.$crt
	sort -rgk1,1 $rFL.$cs1.$cs2.stats.less.$crt -o $rFL.$cs1.$cs2.stats.less.$crt
	sort -rgk5,5 $rFL.$cs1.$cs2.stats.equal.$crt -o $rFL.$cs1.$cs2.stats.equal.$crt
	sort -rnk2,2 $rFL.$cs1.$cs2.stats.greater.$crt -o $rFL.$cs1.$cs2.stats.greater.$crt.rnk2

	printf "%s   : %6s vs %6s\n" $name $cs1 $cs2 | tee -a $rootFS.crc.$cs1.$cs2.log
	printf "%s   : output            = files |cr#1/cr#2 |cr#2/cr#1,%%|  %6s   compressed size     |  %6s   compressed size     \n" $name $cs1 $cs2 | tee -a $rootFS.crc.$cs1.$cs2.log
	awk -v base=$name '\
		{ printf "%s   : %-17s = %5d | %8.2f | %8.2f%% | %9dB / %7.1fK / %4.1fM | %9dB / %8.1fK / %5.1fM\n", \
		  base, "greater threshold", $1, $2, $3, $4, $4/1024, $4/(1024*1024), $5, $5/1024, $5/(1024*1024); \
		}' $rFL.$cs1.$cs2.stats.greater.$crt.total | tee -a $rootFS.crc.$cs1.$cs2.log
	awk -v base=$name '\
		{ printf "%s   : %-17s = %5d | %8.2f | %8.2f%% | %9dB / %7.1fK / %4.1fM | %9dB / %8.1fK / %5.1fM\n", \
		  base, "less threshold", $1, $2, $3, $4, $4/1024, $4/(1024*1024), $5, $5/1024, $5/(1024*1024); \
		}' $rFL.$cs1.$cs2.stats.less.$crt.total | tee -a $rootFS.crc.$cs1.$cs2.log
	awk -v base=$name '\
		{ printf "%s   : %-17s = %5d | %8.2f | %8.2f%% | %9dB / %7.1fK / %4.1fM | %9dB / %8.1fK / %5.1fM\n", \
		  base, "equal threshold", $1, $2, $3, $4, $4/1024, $4/(1024*1024), $5, $5/1024, $5/(1024*1024); \
		}' $rFL.$cs1.$cs2.stats.equal.$crt.total | tee -a $rootFS.crc.$cs1.$cs2.log

	rm $rFL.$cs1.$cs2.stats.greater.$crt.total $rFL.$cs1.$cs2.stats.less.$crt.total $rFL.$cs1.$cs2.stats.equal.$crt.total
fi

#Clean up
rm $rFL.$cs1.stats.tmp $rFL.$cs2.stats.tmp

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name   : Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

