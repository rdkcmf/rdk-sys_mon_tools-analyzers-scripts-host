#!/bin/bash
#

# $0 : elfSectionCompare.sh is a Linux Host based script that compares 2 ELF object sections.

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-1 elfs1 -2 elfs2 [-3 elfs-diff]] | [-h]"
	echo "$name# Compare two ELF sections"
	echo "$name# -1    : an ELF section #1"
	echo "$name# -2    : an ELF section #2"
	echo "$name# -3    : an output of comparison between ELF section #1 & #2"
	echo "$name# -h    : display this help and exit"
#	echo "$name#       : USE_SYSRES_PLATFORM { ARM | MIPS | x86 } = $([ ! -z "$USE_SYSRES_PLATFORM" ] && echo $USE_SYSRES_PLATFORM || echo "?")" 
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

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
echo "$cmdline" > ${name}.log

path=$0
path=${path%/*}
source $path/elfHeaders.sh

#NA="N/A"

elfs1=
elfs2=
of=
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
		-h | --help )   usage
				exit
				;;
		* )             echo "$name# ERROR : unknown parameter in the command argument list!"
				usage
				exit 1
    esac
    shift
done

echo "ELFS #1 =  $elfs1" | tee -a ${name}.log
echo "ELFS #2 =  $elfs2" | tee -a ${name}.log
i=1
for elfs in "$elfs1" "$elfs2"
do
	if [ ! -e "$elfs" ]; then
		echo "$name : ERROR  : ${elfs} file doesn't exist!"
		usage
		exit
	fi
	i=`expr $i + 1`
done

[ -z "$of" ] && of="${elfs1%%.*}.${elfs2%%.*}.ees"
echo "ELFS #3 =  ${of}" | tee -a ${name}.log

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
sed "/$ESH_HEADER_TEXT_1/d;/$ELF_PSEC_STARTOF_TEXT/d;/$ELF_PSEC_ENDOF_TEXT/d;" ${elfs1} | sort -t $'\t' -k3,3 -o ${elfs1}.tmp
sed "/$ESH_HEADER_TEXT_1/d;/$ELF_PSEC_STARTOF_TEXT/d;/$ELF_PSEC_ENDOF_TEXT/d;" ${elfs2} | sort -t $'\t' -k3,3 -o ${elfs2}.tmp
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
printf "ELFS #1,#2 total/common/specific section analysis                             : %s %s\n" ${of} ${of}.rnk3 | tee -a ${name}.log
objType="functions"
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
elfs1Secs=$(echo "$elfs1Total" | tr -s ' ' | cut -d ' ' -f6)
elfs1Size=$(echo "$elfs1Total" | tr -s ' ' | cut -d ' ' -f9)
elfs2Secs=$(echo "$elfs2Total" | tr -s ' ' | cut -d ' ' -f6)
elfs2Size=$(echo "$elfs2Total" | tr -s ' ' | cut -d ' ' -f9)
diffSize=$((elfs1Size-elfs2Size))
printf "ELFS #1-#2 total    : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elfs1Secs-elfs2Secs)) "$objType" $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a ${name}.log

#ELFS #1 and #2 common section and size differencies
elfs1Secs=$(echo "$elfs1Common" | tr -s ' ' | cut -d ' ' -f6)
elfs1Size=$(echo "$elfs1Common" | tr -s ' ' | cut -d ' ' -f9)
elfs2Secs=$(echo "$elfs2Common" | tr -s ' ' | cut -d ' ' -f6)
elfs2Size=$(echo "$elfs2Common" | tr -s ' ' | cut -d ' ' -f9)
diffSize=$((elfs1Size-elfs2Size))
printf "ELFS #1-#2 common   : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elfs1Secs-elfs2Secs)) "$objType" $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a ${name}.log

#ELFS #1 and #2 specific section and size differencies
elfs1Secs=$(echo "$elfs1Specific" | tr -s ' ' | cut -d ' ' -f6)
elfs1Size=$(echo "$elfs1Specific" | tr -s ' ' | cut -d ' ' -f9)
elfs2Secs=$(echo "$elfs2Specific" | tr -s ' ' | cut -d ' ' -f6)
elfs2Size=$(echo "$elfs2Specific" | tr -s ' ' | cut -d ' ' -f9)
diffSize=$((elfs1Size-elfs2Size))
printf "ELFS #1-#2 specific : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elfs1Secs-elfs2Secs)) "$objType" $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a ${name}.log

# add headers
[ -s ${of} ] && sed -i "1i$ESH_HEADER_TEXT_2" ${of}
[ -s ${of}.common ] && sed -i "1i$ESH_HEADER_TEXT_2" ${of}.common
[ -s ${of}.rnk3 ] && sed -i "1i$ESH_HEADER_TEXT_2" ${of}.rnk3
[ -s ${of}.specific1 ] && sed -i "1i$ESH_HEADER_TEXT" ${of}.specific1
[ -s ${of}.specific2 ] && sed -i "1i$ESH_HEADER_TEXT" ${of}.specific2

# Cleanup
rm -f ${elfs1}.tmp ${elfs2}.tmp ${of}.common.names ${elfs1}.common ${elfs2}.common

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

