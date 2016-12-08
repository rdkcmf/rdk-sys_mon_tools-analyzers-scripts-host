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
# $0 : rootFSCRAnalyzer.sh is a Linux Host based script that identifies compression ratio of all rootFS regular files

calist='gzip lzma xz bro'

# Output:

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-r folder] | [-ca -cl]] | [-h]"
	echo "$name# RootFS regular files compression ratio analyzer"
	echo "$name# -r    : a rootFS folder"
	echo "$name# -ca   : a compression algorithm : $calist"
	echo "$name# -cl   : a compression level : 0..9"
	echo "$name# -cr   : an optional compression ratio threshold output : [ <= x.y | => x.y% ] as [ <= 1.25 | >= 80% ]"
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

ca=gzip
cl=6
rfs=
crthr=
crthrstr=
while [ "$1" != "" ]; do
	case $1 in
		-r | --root )   shift
				rfs=$1
				;;
		-ca )           shift
				ca=$1
				;;
		-cl )           shift
				cl=$1
				;;
		-cr )           shift
				if [ "${1/*%/%}" == "%" ]; then
					crthr=${1/%?}
					if [ "$crthr" == "0" ]; then
						echo "$name# Error : 0 is invalid compression ratio threshold!"
						usage
						exit
					fi
					crthrstr=$crthr%
					crthr=$(bc <<< "scale=2; 100 / $crthr")
				else
					crthr=$1
					crthrstr=$1
				fi
				;;
		-h | --help )   usage
				exit
				;;
		* )		echo "$name# ERROR : unknown parameter in the command argument list!"
				usage
				exit 1
	esac
	shift
done

if [ "$rfs" == "" ]; then
	echo "$name# Error : rootFS folder is not set!"
	usage
	exit
fi

if [ ! -d "$rfs" ]; then
	echo "$name# Error : $rfs is not a folder!"
	usage
	exit
fi

if [ ! -e $rfs/version.txt ]; then
	rootFS=`basename $rfs`
	echo "$name# WARNING: $rfs/version.txt file is not present. Cannot retrieve version info. Using $rfs base name" | tee -a $rootFS.cra.$ca.$cl.log
else
	rootFS=`cat $rfs/version.txt | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
fi

cavalid=false
for cait in $calist; do
	if [ $ca == $cait ]; then
		cavalid=true
		break
	fi
done
if [ $cavalid == "false" ]; then
	echo "$name# Error : invalid compression algorithm = $ca !"
	usage
	exit
fi

if [[ ! $cl == [0-9] ]]; then
	echo "$name# Error : invalid compression level = $cl !"
	usage
	exit
fi

if [ "$(which $ca)" == "" ]; then
	echo "$name# Error : can't find $ca ! is the PATH set to $ca ?"
	usage
	exit
fi

if [ "$ca" == "gzip" ]; then 
caext=gz; caopts="-f";
else 
caext=$ca; caopts=
fi

echo "$cmdline" > $rootFS.cra.$ca.$cl.log
echo "$name : rootFS folder     = $rfs"    | tee -a $rootFS.cra.$ca.$cl.log
echo "$name : rootFS            = $rootFS" | tee -a $rootFS.cra.$ca.$cl.log
echo "$name : compression/level = $ca/$cl" | tee -a $rootFS.cra.$ca.$cl.log
[ "$crthrstr" != "" ] && echo "$name : cmpr ratio thresh = $crthrstr" | tee -a $rootFS.cra.$ca.$cl.log

rfsCompressed="./$rootFS.compressed"

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

# Create rootFS regular files list
rFL=$rootFS.cra.files.all
$path/rootFSFLBuilder.sh -r $rfs -o $rFL > /dev/null
if [ ! -s "$rFL" ]; then
	echo "$name# ERROR : $path/rootFSFLBuilder.sh failed to create $rFL !"
	exit
fi
fllo2sh $rFL $rFL.short

# Clone target rootFS
cp -rf $rfs/. $rfsCompressed

# Compress target rootFS regular files
while read -r line
do
	filename=$rfsCompressed/${line#*/}
	if [ "$ca" == "bro" ]; then
		bro -f -q $cl -i $filename -o $filename.bro 2>/dev/null
		rm $filename
	else
		$ca $caopts -$cl $filename 2>/dev/null
	fi
done < $rFL.short

# Create rootFS regular compressed file list
$path/rootFSFLBuilder.sh -r $rfsCompressed  -i $rootFS -o $rFL.$ca.$cl > /dev/null
if [ ! -s "$rFL.$ca.$cl" ]; then
	echo "$name# ERROR : $path/rootFSFLBuilder.sh failed to create $rFL.$ca.$cl !"
	exit
fi

[ "$crthrstr" != "" ] && cat /dev/null > $rFL.$ca.$cl.stats.$crthrstr

# Create rootFS regular compressed file list
sed 's/'".$caext$"'//' $rFL.$ca.$cl | sort -k9 | join -1 9 -2 9 $rFL - -o 2.5,1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9 | awk -v base=$rFL.$ca.$cl -v thrstr="$crthrstr" -v thr=$crthr \
	'{ \
		ratio=-1; \
		sizeComprTotal+=$1; sizeUnComprTotal+=$6; \
		if ($1 != 0) ratio=$6/$1; \
		if ($6 != 0) {
			printf "%5.2f %8.2f%% %9s : %s %s %s %s %9s %s %s %s %s\n", ratio, ($1/$6)*100, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10; \
		} else { \
			printf "%5.2f %8s%% %9s : %s %s %s %s %9s %s %s %s %s\n", 0, "Inf", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10; \
		}
		if (thrstr != "" && ratio <= thr) {
			selected++; sizeComprSelected+=$1; sizeUnComprSelected+=$6; \
			if ($6 != 0) {
				printf "%5.2f %8.2f%% %9s : %s %s %s %s %9s %s %s %s %s\n", ratio, ($1/$6)*100, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10 >> base".stats."thrstr; \
			} else { \
				printf "%5.2f %8s%% %9s : %s %s %s %s %9s %s %s %s %s\n", 0, "Inf", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10 >> base".stats."thrstr; \
			}
		}
	} \
	END { \
		ratio=-1; \
		if (sizeComprTotal != 0) ratio=sizeUnComprTotal/sizeComprTotal; \
		if (sizeUnComprTotal != 0) { \
			printf "%d %5.2f %8.2f%% %9d %9d\n", NR, ratio, (sizeComprTotal/sizeUnComprTotal)*100, sizeComprTotal, sizeUnComprTotal > base".stats.total" \
		} else {
			printf "%d %5.2f %8s%% %9d %9d\n", NR, 0, "Inf", sizeComprTotal, 0 > base".stats.total" \
		}
		if (thrstr != "") {
			if (sizeComprSelected != 0) ratio=sizeUnComprSelected/sizeComprSelected; \
			if (sizeUnComprSelected != 0) { \
				printf "%d %5.2f %8.2f%% %9d %9d\n", selected, ratio, (sizeComprSelected/sizeUnComprSelected)*100, sizeComprSelected, sizeUnComprSelected > base".stats."thrstr".total" \
			} else {
				printf "%d %5.2f %8s%% %9d %9d\n", selected, 0, "Inf", sizeComprSelected, 0 > base".stats."thrstr".total" \
			}
		}
	}' >  $rFL.$ca.$cl.stats

# General numeric reverse sort in descending order by compressed/uncompressed value
sort -rg -k2,3 $rFL.$ca.$cl.stats -o $rFL.$ca.$cl.stats.rgk23
if [ "$crthrstr" != "" ]; then
	sort -rn -k3,3 $rFL.$ca.$cl.stats.$crthrstr -o $rFL.$ca.$cl.stats.$crthrstr
fi

awk -v base=$name '{ printf "%s : output            = files | unc/cmpr | cmpr/unc  |        compressed size        |        uncompressed size\n", base; \
		     printf "%s : compr stats total = %5d | %8.2f | %8.2f%% | %9dB / %7.1fK / %4.1fM | %9dB / %8.1fK / %5.1fM\n", \
		     base, $1, $2, $3, $4, $4/1024, $4/(1024*1024), $5, $5/1024, $5/(1024*1024) }' $rFL.$ca.$cl.stats.total | tee -a $rootFS.cra.$ca.$cl.log

if [ "$crthrstr" != "" ]; then
	awk -v base=$name -v thrstr="$crthrstr" '{ printf "%s : compr stats %5s = %5d | %8.2f | %8.2f%% | %9dB / %7.1fK / %4.1fM | %9dB / %8.1fK / %5.1fM\n", \
		     base, thrstr, $1, $2, $3, $4, $4/1024, $4/(1024*1024), $5, $5/1024, $5/(1024*1024) }' $rFL.$ca.$cl.stats.$crthrstr.total | tee -a $rootFS.cra.$ca.$cl.log
	rm $rFL.$ca.$cl.stats.$crthrstr.total
fi

#Clean up
rm -rf $rfsCompressed
rm $rFL.$ca.$cl $rFL.short $rootFS.flb.log
rm $rFL.$ca.$cl.stats.total

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

