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

# $0 : elfSectionCompare.sh is a Linux Host based script that compares 2 ELF object sections.

# Function: usage
function usage()
{
	echo "${name}# Usage : `basename $0 .sh` [-1 elfs1 -2 elfs2 [-3 elfs-diff]] | [-h]"
	echo "${name}# Compare two ELF sections"
	echo "${name}# -1    : an ELF section #1"
	echo "${name}# -2    : an ELF section #2"
	echo "${name}# -3    : an output of comparison between ELF section #1 & #2"
	echo "${name}# -al   : append logging"
	echo "${name}# -V    : validate produced data"
	echo "${name}# -h    : display this help and exit"
#	echo "${name}#       : USE_SYSRES_PLATFORM { ARM | MIPS | x86 } = $([ ! -z "$USE_SYSRES_PLATFORM" ] && echo $USE_SYSRES_PLATFORM || echo "?")" 
}

# Function: eshTotalLog
# $1: eshFile	- "elf section header" file
# $2: eshDescr	- "elf section header" file descriptor
# $3: eshType	- "elf section header" object type
# $4: eshLog	- log file
function eshTotalLog()
{
	if [ -s $1 ]; then
		awk -v eshFile="$1" -v eshDescr="$2" -v eshType="$3" 'BEGIN {FS="\t"}; {total += $2} END { printf "%-12s : %6d %s : %9d B / %8.2f KB / %5.2f MB\n", eshDescr, NR, eshType, total, total/1024, total/(1024*1024)}' "$1" | tee -a $4
	fi
}


# Function: eshLog
# $1: eshFile	- common "elf section header" file
# $2: eshFile	- a column number in common "elf section header" file that describes section sizes
# $3: eshDescr	- common "elf section header" file descriptor
# $4: eshType	- "elf section header" object type
# $5: eshLog	- log file
function eshLog()
{
	if [ -s $1 ]; then
		#awk -v eshFile="$1" -v eshSize="$2" -v eshDescr="$3" -v eshType="$4" 'BEGIN {FS="\t"}; {total += $eshSize; printf "%d\n", $eshSize; } END { printf "%-12s : %6d %s : %9d B / %8.2f KB / %5.2f MB : %s\n", eshDescr, NR, eshType, total, total/1024, total/(1024*1024), eshFile}' "$1" | tee -a $5
		awk -v eshFile="$1" -v eshSize="$2" -v eshDescr="$3" -v eshType="$4" 'BEGIN {FS="\t"}; {total += $eshSize} END { printf "%-12s : %6d %s : %9d B / %8.2f KB / %5.2f MB : %s\n", eshDescr, NR, eshType, total, total/1024, total/(1024*1024), eshFile}' "$1" | tee -a $5
	else
		printf "%-12s : %6d %s : %9d B / %8.2f KB / %5.2f MB : %s\n" "$3" 0 "$4" 0 0 0 "$1" | tee -a $5
	fi
}

# $1: eshFile	- a file with ELF sections: "size funcName" to validate
# $2: eshSizeT  - size validation value
# $3: eshLog	- log file
function eshFileValidation()
{
	local _eshFileMetrics_=$(awk 'BEGIN {FS="\t"}; {total += $1} END { printf "%d\n", total}' $1)
	if [ $2 -ne $_eshFileMetrics_ ]; then
		echo "${name}# WARN : file validation failed for elfsSizeTotal: $2 != $_eshFileMetrics_) : $1" | tee -a $3
	else
		echo "${name}# : file validation success : $1" | tee -a $3
	fi
}

# $1: eshFile	- a file with ELF sections: "size#1 size#2 size#1-size#2 funcName" to validate
# $2: esh1SizeT - size#1 validation value
# $3: esh2SizeT - size#2 validation value
# $4: esh2SizeD - size#1-size#2 validation value
# $5: eshLog	- log file
function eshFileValidation2()
{
	local _eshFileMetrics_=$(awk 'BEGIN {FS="\t"}; {total1 += $1; total2 += $2; totald += $3; } END { printf "%d\t%d\t%d\n", total1, total2, totald}' $1)
	if [ $2 -ne $(echo "$_eshFileMetrics_" | cut -f1) ]; then
		echo "${name}# WARN : file validation failed for elfs1SizeTotal: $2 != $(echo "$_eshFileMetrics_" | cut -f1) : $1" | tee -a $5
	elif [ $3 -ne $(echo "$_eshFileMetrics_" | cut -f2) ]; then
		echo "${name}# WARN : file validation failed for elfs2SizeTotal: $3 != $(echo "$_eshFileMetrics_" | cut -f2) : $1" | tee -a $5
	elif [ $4 -ne $(echo "$_eshFileMetrics_" | cut -f3) ]; then
		echo "${name}# WARN : file validation failed for diffSizeTotal: $4 != $(echo "$_eshFileMetrics_" | cut -f3) : $1" | tee -a $5
	else
		echo "${name}# : file validation success : $1" | tee -a $5
	fi
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/elfHeaders.sh

#NA="N/A"

elfs1=
elfs2=
of=
validation=
appendLog=
while [ "$1" != "" ]; do
	case $1 in
		-1 )   shift
				elfs1=$1
				;;
		-2 )   shift
				elfs2=$1
				;;
		-3 )   shift
				of=$1
				;;
		-al )		appendLog=y
				;;
		-V )		validation="y"
				;;
		-h | --help )   usage
				exit
				;;
		* )             echo "${name}# ERROR : unknown parameter \"$1\" in the command argument list!"
				usage
				exit 1
    esac
    shift
done

[ -z "$appendLog" ] && echo "$cmdline" > ${name}.log || echo "$cmdline" >> ${name}.log

echo "ELFS #1 =  $elfs1" | tee -a ${name}.log
echo "ELFS #2 =  $elfs2" | tee -a ${name}.log
i=1
for elfs in "$elfs1" "$elfs2"
do
	if [ ! -e "$elfs" ]; then
		echo "${name} : ERROR  : ${elfs} file doesn't exist!"
		usage
		exit 2
	fi
	i=`expr $i + 1`
done

ofExt=${elfs1##*.}
[ -z "$of" ] && of="${elfs1%.*}-${elfs2%.*}.${ofExt}"
echo "ELFS #3 =  ${of}" | tee -a ${name}.log

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
sed "/$ESH_HEADER_TEXT_1/d;/$ESH_HEADER_OBJ_1/d" ${elfs1} | sort -t $'\t' -k3,3 -o ${elfs1}.tmp
sed "/$ESH_HEADER_TEXT_1/d;/$ESH_HEADER_OBJ_1/d" ${elfs2} | sort -t $'\t' -k3,3 -o ${elfs2}.tmp
comm -12 <(cut -f3 ${elfs1}.tmp | sort -u) <(cut -f3 ${elfs2}.tmp | sort -u) > ${of}.common.names

# find common and specific elf section objects
join -1 1 -2 3 -t $'\t' ${of}.common.names ${elfs1}.tmp -o 2.2,1.1 | awk 'BEGIN {FS="\t"}; {printf "%s\t%s\n", $1, $2}' > ${elfs1}.common
join -1 1 -2 3 -t $'\t' ${of}.common.names ${elfs2}.tmp -o 2.2,1.1 | awk 'BEGIN {FS="\t"}; {printf "%s\t%s\n", $1, $2}' > ${elfs2}.common
if [ "$(cut -f2 ${elfs1}.common | md5sum | cut -d ' ' -f1)" == "$(cut -f2 ${elfs2}.common | md5sum | cut -d ' ' -f1)" ]; then
	paste ${elfs1}.common ${elfs2}.common | awk 'BEGIN {FS="\t"}; {printf "%s\t%s\t%09d\t%s\n", $1, $3, $1-$3, $2}' > ${of}.common
fi

join -v2 -1 1 -2 3  -t $'\t' ${of}.common.names ${elfs1}.tmp -o 2.2,2.3 | awk 'BEGIN {FS="\t"}; {printf "%s\t%s\n", $1, $2}' > ${of}.specific1
join -v2 -1 1 -2 3  -t $'\t' ${of}.common.names ${elfs2}.tmp -o 2.2,2.3 | awk 'BEGIN {FS="\t"}; {printf "%s\t%s\n", $1, $2}' > ${of}.specific2

if [ -f ${of}.common ]; then
	cat ${of}.common <(awk -v NA=$NA 'BEGIN {FS="\t"}; {printf "%09d\t%09s\t%09d\t%s\n", $1, NA, $1, $2}' ${of}.specific1) <(awk -v NA=$NA 'BEGIN {FS="\t"}; {printf "%09s\t%09d\t%09d\t%s\n", NA, $1, -$1, $2}' ${of}.specific2) | sort -t$'\t' -k4,4 -o ${of}
	sort -t$'\t' -rnk3 ${of} -o ${of}.rnk3
fi

# total/common/specific section analysis
printf "%-75s : %s %s\n" "ELFS #1,#2 total/common/specific section analysis" ${of} ${of}.rnk3 | tee -a ${name}.log
objType="objects"
elfs1Total=$(eshTotalLog ${elfs1}.tmp "ELFS #1 =  total   " "$objType" ${name}.log)
elfs2Total=$(eshTotalLog ${elfs2}.tmp "ELFS #2 =  total   " "$objType" ${name}.log)
elfs1Common=$(eshLog ${of}.common 1 "ELFS #1 =  common  " "$objType" ${name}.log)
elfs2Common=$(eshLog ${of}.common 2 "ELFS #2 =  common  " "$objType" ${name}.log)
elfs1Specific=$(eshLog ${of}.specific1  1 "ELFS #1 =  specific" "$objType" ${name}.log)
elfs2Specific=$(eshLog ${of}.specific2  1 "ELFS #2 =  specific" "$objType" ${name}.log)

echo "$elfs1Total"
echo "$elfs2Total"
echo "$elfs1Common"
echo "$elfs2Common"
echo "$elfs1Specific"
echo "$elfs2Specific"

# total/common/specific section analysis of differences between ELF files
printf "ELFS #1-#2 total/common/specific section analysis:\n" | tee -a ${name}.log
#ELFS #1 and #2 total section and size differencies
elfs1SecsTotal=$(echo "$elfs1Total" | tr -s ' ' | cut -d ' ' -f6)
elfs1SizeTotal=$(echo "$elfs1Total" | tr -s ' ' | cut -d ' ' -f9)
elfs2SecsTotal=$(echo "$elfs2Total" | tr -s ' ' | cut -d ' ' -f6)
elfs2SizeTotal=$(echo "$elfs2Total" | tr -s ' ' | cut -d ' ' -f9)
diffSizeTotal=$((elfs1SizeTotal-elfs2SizeTotal))
printf "ELFS #1-#2 total    : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elfs1SecsTotal-elfs2SecsTotal)) "$objType" $diffSizeTotal $((diffSizeTotal/1024)) $((diffSizeTotal/(1024*1024))) | tee -a ${name}.log

#ELFS #1 and #2 common section and size differencies
elfs1SecsCommon=$(echo "$elfs1Common" | tr -s ' ' | cut -d ' ' -f6)
elfs1SizeCommon=$(echo "$elfs1Common" | tr -s ' ' | cut -d ' ' -f9)
elfs2SecsCommon=$(echo "$elfs2Common" | tr -s ' ' | cut -d ' ' -f6)
elfs2SizeCommon=$(echo "$elfs2Common" | tr -s ' ' | cut -d ' ' -f9)
diffSizeCommon=$((elfs1SizeCommon-elfs2SizeCommon))
printf "ELFS #1-#2 common   : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elfs1SecsCommon-elfs2SecsCommon)) "$objType" $diffSizeCommon $((diffSizeCommon/1024)) $((diffSizeCommon/(1024*1024))) | tee -a ${name}.log

#ELFS #1 and #2 specific section and size differencies
elfs1SecsSpecific=$(echo "$elfs1Specific" | tr -s ' ' | cut -d ' ' -f6)
elfs1SizeSpecific=$(echo "$elfs1Specific" | tr -s ' ' | cut -d ' ' -f9)
elfs2SecsSpecific=$(echo "$elfs2Specific" | tr -s ' ' | cut -d ' ' -f6)
elfs2SizeSpecific=$(echo "$elfs2Specific" | tr -s ' ' | cut -d ' ' -f9)
diffSizeSpecific=$((elfs1SizeSpecific-elfs2SizeSpecific))
printf "ELFS #1-#2 specific : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elfs1SecsSpecific-elfs2SecsSpecific)) "$objType" $diffSizeSpecific $((diffSizeSpecific/1024)) $((diffSizeSpecific/(1024*1024))) | tee -a ${name}.log

if [ "$validation" == "y" ]; then
	if [ $elfs1SecsTotal -ne $((elfs1SecsCommon+elfs1SecsSpecific)) ]; then
		echo "${name}# WARN : data validation failed for elfs1SecsTotal: $elfs1SecsTotal != $((elfs1SecsCommon+elfs1SecsSpecific))" | tee -a ${name}.log
	elif [ $elfs2SecsTotal -ne $((elfs2SecsCommon+elfs2SecsSpecific)) ]; then
		echo "${name}# WARN : data validation failed for elfs2SecsTotal: $elfs2SecsTotal != $((elfs2SecsCommon+elfs2SecsSpecific))" | tee -a ${name}.log
	elif [ $elfs1SizeTotal -ne $((elfs1SizeCommon+elfs1SizeSpecific)) ]; then
		echo "${name}# WARN : data validation failed for elfs1SizeTotal: $elfs1SizeTotal != $((elfs1SizeCommon+elfs1SizeSpecific))" | tee -a ${name}.log
	elif [ $elfs2SizeTotal -ne $((elfs2SizeCommon+elfs2SizeSpecific)) ]; then
		echo "${name}# WARN : data validation failed for elfs2SizeTotal: $elfs2SizeTotal != $((elfs2SizeCommon+elfs2SizeSpecific))" | tee -a ${name}.log
	else
		echo "${name}# : data validation success" | tee -a ${name}.log
	fi

	eshFileValidation2 ${of} $elfs1SizeTotal $elfs2SizeTotal $diffSizeTotal ${name}.log
	eshFileValidation2 ${of}.rnk3 $elfs1SizeTotal $elfs2SizeTotal $diffSizeTotal ${name}.log
	eshFileValidation2 ${of}.common $elfs1SizeCommon $elfs2SizeCommon $diffSizeCommon ${name}.log

	eshFileValidation ${of}.specific1 $elfs1SizeSpecific ${name}.log
	eshFileValidation ${of}.specific2 $elfs2SizeSpecific ${name}.log
fi

# add headers
if [ "$ofExt" == "ax" ]; then
	ESH_HEADER=${ESH_HEADER_TEXT}
	ESH_HEADER_2=${ESH_HEADER_TEXT_2}
else
	ESH_HEADER=${ESH_HEADER_OBJ_1}
	ESH_HEADER_2=${ESH_HEADER_OBJ_2}
fi

[ -s ${of} ] && sed -i "1i$ESH_HEADER_2" ${of}
[ -s ${of}.common ] && sed -i "1i$ESH_HEADER_2" ${of}.common
[ -s ${of}.rnk3 ] && sed -i "1i$ESH_HEADER_2" ${of}.rnk3
[ -s ${of}.specific1 ] && sed -i "1i$ESH_HEADER" ${of}.specific1
[ -s ${of}.specific2 ] && sed -i "1i$ESH_HEADER" ${of}.specific2

# Cleanup
rm -f ${elfs1}.tmp ${elfs2}.tmp ${of}.common.names ${elfs1}.common ${elfs2}.common

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "${name}: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

