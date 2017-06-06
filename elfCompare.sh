#!/bin/bash
#

# $0 : elfCompare.sh is a Linux Host based script that compares 2 ELF binaries/objects.

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-1 elf1 -2 elf2 [-3 elf-diff]] | [-h]"
	echo "$name# Compare two ELF objects"
	echo "$name# -1    : an ELF object #1"
	echo "$name# -2    : an ELF object #2"
	echo "$name# -3    : an output of comparison between ELF objects #1 & #2"
	echo "$name# -h    : display this help and exit"
#	echo "$name#       : USE_SYSRES_PLATFORM { ARM | MIPS | x86 } = $([ ! -z "$USE_SYSRES_PLATFORM" ] && echo $USE_SYSRES_PLATFORM || echo "?")" 
}

# Function: eshTotalLog
# $1: eshFile	- "elf section header" file
# $2: eshDescr	- "elf section header" file descriptor
# $3: eshLog	- log file
function eshTotalLog()
{
	if [ -s $1 ]; then
		awk -v eshFile="$1" -v eshDescr="$2" '{total += strtonum("0x"$5)} END { printf "%-12s : %3d sections : %9d B / %6.2f KB / %3.2f MB\n", eshDescr, NR, total, total/1024, total/(1024*1024)}' "$1" | tee -a $3
	fi
}

# Function: eshLog
# $1: eshFile	- common "elf section header" file
# $2: eshFile	- a column number in common "elf section header" file that describes section sizes
# $3: eshDescr	- common "elf section header" file descriptor
# $4: eshLog	- log file
function eshLog()
{
	if [ -s $1 ]; then
		awk -v eshFile="$1" -v eshSize="$2" -v eshDescr="$3" 'BEGIN {FS="\t"}; {total += strtonum($eshSize); } END { printf "%-12s : %3d sections : %9d B / %6.2f KB / %3.2f MB : %s\n", eshDescr, NR, total, total/1024, total/(1024*1024), eshFile}' "$1" | tee -a $4
	else
		printf "%-12s : %3d sections : %9d B / %6.2f KB / %3.2f MB : %s\n" "$3" 0 0 0 0 "$1" | tee -a $4
	fi
}


# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
echo "$cmdline" > ${name}.log

#NA="N/A"

elf1=
elf2=
of=
while [ "$1" != "" ]; do
	case $1 in
		-1 )   shift
				elf1=$1
				;;
		-2 )   shift
				elf2=$1
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

echo "ELF #1 =  $elf1" | tee -a ${name}.log
echo "ELF #2 =  $elf2" | tee -a ${name}.log
i=1
for elf in "$elf1" "$elf2"
do
	if [ ! -e "$elf" ]; then
		echo "$name : ERROR  : ${elf} file doesn't exist!"
		usage
		exit
	fi
	isElf="$(file -b "$elf" | grep "^ELF ")"
	if [ -z "$isElf" ]; then
		echo "$name : ERROR  : ${elf} is NOT an ELF file!"
		exit
	fi
	i=`expr $i + 1`
done

[ -z "$of" ] && of="${elf1%%.*}.${elf2%%.*}.esh"
echo "ELF #3 =  $of" | tee -a ${name}.log

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

# create elf section header files #1 & #2
readelf -S ${elf1} | tee ${elf1}.readelf-S | sed 's/^ *//' | cut -b6- | grep "^\." | tr -s ' ' | sort -k1,1 -o ${elf1}.esh
readelf -S ${elf2} | tee ${elf2}.readelf-S | sed 's/^ *//' | cut -b6- | grep "^\." | tr -s ' ' | sort -k1,1 -o ${elf2}.esh

# find common and specific elf sections
join -j 1 ${elf1}.esh ${elf2}.esh -o 1.1,1.2,1.5,2.5 | awk '{printf "%-20s\t%-14s\t0x%06s\t0x%06s\t%08d\n", $1, $2, $3, $4, strtonum("0x" $3) - strtonum("0x" $4)}' > $of.common
join -v1 -j 1 ${elf1}.esh ${elf2}.esh -o 1.1,1.2,1.5 | awk '{printf "%-20s\t%-14s\t0x%06s\t%08d\n", $1, $2, $3, strtonum("0x" $3)}' > $of.spec1
join -v2 -j 1 ${elf1}.esh ${elf2}.esh -o 1.1,2.2,2.5 | awk '{printf "%-20s\t%-14s\t0x%06s\t%08d\n", $1, $2, $3, strtonum("0x" $3)}' > $of.spec2
cat $of.common <(awk -v NA=$NA '{printf "%-20s\t%-14s\t%06s\t%08s\t%08d\n", $1, $2, $3, NA, $4}' $of.spec1) <(awk -v NA=$NA '{printf "%-20s\t%-14s\t%08s\t%06s\t%08d\n", $1, $2, NA, $3, $4}' $of.spec2) | sort -k1 -o $of
sort -t$'\t' -rnk5 $of -o $of.rnk5

# total/common/specific section analysis of the original ELF files
printf "ELF #1,#2 total/common/specific section analysis                      : %s\n" $of | tee -a ${name}.log
elf1Total=$(eshTotalLog ${elf1}.esh "ELF #1 =  total   " ${name}.log)
elf2Total=$(eshTotalLog ${elf2}.esh "ELF #2 =  total   " ${name}.log)
elf1Common=$(eshLog $of.common 3 "ELF #1 =  common  " ${name}.log)
elf2Common=$(eshLog $of.common 4 "ELF #2 =  common  " ${name}.log)
elf1Specific=$(eshLog $of.spec1  3 "ELF #1 =  specific" ${name}.log)
elf2Specific=$(eshLog $of.spec2  3 "ELF #2 =  specific" ${name}.log)

echo "$elf1Total"
echo "$elf2Total"
echo "$elf1Common"
echo "$elf2Common"
echo "$elf1Specific"
echo "$elf2Specific"

# total/common/specific section analysis of the differences between the original ELF files
printf "ELF #1-#2 total/common/specific section analysis:\n" | tee -a ${name}.log
#ELF #1 and #2 total section and size differencies
elf1Secs=$(echo "$elf1Total" | tr -s ' ' | cut -d ' ' -f6)
elf1Size=$(echo "$elf1Total" | tr -s ' ' | cut -d ' ' -f9)
elf2Secs=$(echo "$elf2Total" | tr -s ' ' | cut -d ' ' -f6)
elf2Size=$(echo "$elf2Total" | tr -s ' ' | cut -d ' ' -f9)
diffSize=$((elf1Size-elf2Size))
printf "ELF #1-#2 total    : %3d sections : %9d B / %6.2f KB / %3.2f MB\n" $((elf1Secs-elf2Secs)) $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a ${name}.log

#ELF #1 and #2 common section and size differencies
elf1Secs=$(echo "$elf1Common" | tr -s ' ' | cut -d ' ' -f6)
elf1Size=$(echo "$elf1Common" | tr -s ' ' | cut -d ' ' -f9)
elf2Secs=$(echo "$elf2Common" | tr -s ' ' | cut -d ' ' -f6)
elf2Size=$(echo "$elf2Common" | tr -s ' ' | cut -d ' ' -f9)
diffSize=$((elf1Size-elf2Size))
printf "ELF #1-#2 common   : %3d sections : %9d B / %6.2f KB / %3.2f MB\n" $((elf1Secs-elf2Secs)) $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a ${name}.log

#ELF #1 and #2 specific section and size differencies
elf1Secs=$(echo "$elf1Specific" | tr -s ' ' | cut -d ' ' -f6)
elf1Size=$(echo "$elf1Specific" | tr -s ' ' | cut -d ' ' -f9)
elf2Secs=$(echo "$elf2Specific" | tr -s ' ' | cut -d ' ' -f6)
elf2Size=$(echo "$elf2Specific" | tr -s ' ' | cut -d ' ' -f9)
diffSize=$((elf1Size-elf2Size))
printf "ELF #1-#2 specific : %3d sections : %9d B / %6.2f KB / %3.2f MB\n" $((elf1Secs-elf2Secs)) $diffSize $((diffSize/1024)) $((diffSize/(1024*1024))) | tee -a ${name}.log

# Cleanup
rm ${elf1}.esh ${elf2}.esh

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

