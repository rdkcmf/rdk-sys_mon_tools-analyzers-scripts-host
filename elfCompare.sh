#!/bin/bash
#

# $0 : elfCompare.sh is a Linux Host based script that compares 2 ELF binaries/objects.

# Function: usage
function usage()
{
	echo "${name}# Usage : `basename $0 .sh` [-1 elf1 -2 elf2 [-3 elf-diff]] | [-h]"
	echo "${name}# Compare two ELF objects"
	echo "${name}# -1    : an ELF object #1"
	echo "${name}# -2    : an ELF object #2"
	echo "${name}# -3    : an output of comparison between ELF objects #1 & #2"
	echo "${name}# -V    : validate produced data"
	echo "${name}# -h    : display this help and exit"
}

# Function: eshTotalLog
# $1: eshFile	- "elf section header" file
# $2: eshDescr	- "elf section header" file descriptor
# $3: eshType	- "elf section header" object type
# $4: eshLog	- log file
#elf1Total=$(eshTotalLog ${elf1}.esh "ELF #1 =  total   " "sections" ${name}.log)
function eshTotalLog()
{
	if [ -s $1 ]; then
		awk -v eshFile="$1" -v eshDescr="$2" -v eshType="$3" '{total += strtonum("0x"$5)} END { printf "%-12s : %6d %s : %9d B / %8.2f KB / %5.2f MB\n", eshDescr, NR, eshType, total, total/1024, total/(1024*1024)}' "$1" | tee -a $4
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
		awk -v eshFile="$1" -v eshSize="$2" -v eshDescr="$3" -v eshType="$4" 'BEGIN {FS="\t"}; {total += $eshSize; } END { printf "%-12s : %6d %s : %9d B / %8.2f KB / %5.2f MB : %s\n", eshDescr, NR, eshType, total, total/1024, total/(1024*1024), eshFile}' "$1" | tee -a $5
	else
		printf "%-12s : %6d %s : %9d B / %8.2f KB / %5.2f MB : %s\n" "$3" 0 "$4" 0 0 0 "$1" | tee -a $5
	fi
}

# $1: eshFile	- a file with ELF sections: "size funcName" to validate
# $2: eshSizeT  - size validation value
# $3: eshLog	- log file
function eshFileValidation()
{
	local _eshFileMetrics_=$(awk 'BEGIN {FS="\t"}; {total += $3} END { printf "%d\n", total}' $1)
	if [ $2 -ne $_eshFileMetrics_ ]; then
		echo "$name# WARN : file validation failed for elfSizeTotal: $2 != $_eshFileMetrics_) : $1" | tee -a $3
	else
		echo "$name# : file validation success : $1" | tee -a $3
	fi
}

# $1: eshFile	- a file with ELF sections: "size#1 size#2 size#1-size#2 funcName" to validate
# $2: esh1SizeT - size#1 validation value
# $3: esh2SizeT - size#2 validation value
# $4: esh2SizeD - size#1-size#2 validation value
# $5: eshLog	- log file
function eshFileValidation2()
{
	local _eshFileMetrics_=$(awk 'BEGIN {FS="\t"}; {total1 += $3; total2 += $4; totald += $5; } END { printf "%d\t%d\t%d\n", total1, total2, totald}' $1)
	if [ $2 -ne $(echo "$_eshFileMetrics_" | cut -f1) ]; then
		echo "$name# WARN : file validation failed for elf1SizeTotal: $2 != $(echo "$_eshFileMetrics_" | cut -f1) : $1" | tee -a $5
	elif [ $3 -ne $(echo "$_eshFileMetrics_" | cut -f2) ]; then
		echo "$name# WARN : file validation failed for elf2SizeTotal: $3 != $(echo "$_eshFileMetrics_" | cut -f2) : $1" | tee -a $5
	elif [ $4 -ne $(echo "$_eshFileMetrics_" | cut -f3) ]; then
		echo "$name# WARN : file validation failed for diffSizeTotal: $4 != $(echo "$_eshFileMetrics_" | cut -f3) : $1" | tee -a $5
	else
		echo "$name# : file validation success : $1" | tee -a $5
	fi
}


# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
echo "$cmdline" > ${name}.log

path=$0
path=${path%/*}
source ${path}/elfHeaders.sh

#NA="N/A"

elf1=
elf2=
of=
sections=
objdump1=
objdump2=
validation=
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
		-s )
				sections=$1
				;;
		-od1 )  shift
				objdump1=$1
				;;
		-od2 )  shift
				objdump2=$1
				;;
		-V )		validation=-V
				;;
		-h | --help )   usage
				exit
				;;
		* )             echo "${name}# ERROR : unknown parameter \"$1\" in the command argument list!" | tee -a ${name}.log
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
		echo "${name} : ERROR  : ${elf} file doesn't exist!" | tee -a ${name}.log
		usage
		exit 2
	fi
	isElf="$(file -b "$elf" | grep "^ELF ")"
	if [ -z "$isElf" ]; then
		echo "${name} : ERROR  : ${elf} is NOT an ELF file!" | tee -a ${name}.log
		exit 3
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
join -j 1 ${elf1}.esh ${elf2}.esh -o 1.1,1.2,1.5,2.5 | awk '{s1=strtonum("0x" $3); s2=strtonum("0x" $4); printf "%-20s\t%-14s\t%09d\t%09d\t%08d\n", $1, $2, s1, s2, s1-s2}' > ${of}.common
join -v1 -j 1 ${elf1}.esh ${elf2}.esh -o 1.1,1.2,1.5 | awk '{printf "%-20s\t%-14s\t%09d\n", $1, $2, strtonum("0x" $3)}' > ${of}.specific1
join -v2 -j 1 ${elf1}.esh ${elf2}.esh -o 2.1,2.2,2.5 | awk '{printf "%-20s\t%-14s\t%09d\n", $1, $2, strtonum("0x" $3)}' > ${of}.specific2
cat ${of}.common <(awk -v NA=$NA '{printf "%-20s\t%-14s\t%09s\t%09s\t%08d\n", $1, $2, $3, NA, $3}' ${of}.specific1) <(awk -v NA=$NA '{printf "%-20s\t%-14s\t%09s\t%09s\t%08d\n", $1, $2, NA, $3, -$3}' ${of}.specific2) | sort -k1,1 -o ${of}
sort -t$'\t' -rnk5 ${of} -o ${of}.rnk5

# total/common/specific section analysis of the original ELF files
printf "ELF #1,#2 total/common/specific section analysis                             : %s %s\n" ${of} ${of}.rnk5 | tee -a ${name}.log
objType="sections "
elf1Total=$(eshTotalLog ${elf1}.esh "ELF #1 =  total   " "$objType" ${name}.log)
elf2Total=$(eshTotalLog ${elf2}.esh "ELF #2 =  total   " "$objType" ${name}.log)
elf1Common=$(eshLog ${of}.common 3 "ELF #1 =  common  " "$objType" ${name}.log)
elf2Common=$(eshLog ${of}.common 4 "ELF #2 =  common  " "$objType" ${name}.log)
elf1Specific=$(eshLog ${of}.specific1  3 "ELF #1 =  specific" "$objType" ${name}.log)
elf2Specific=$(eshLog ${of}.specific2  3 "ELF #2 =  specific" "$objType" ${name}.log)

echo "$elf1Total"
echo "$elf2Total"
echo "$elf1Common"
echo "$elf2Common"
echo "$elf1Specific"
echo "$elf2Specific"

# total/common/specific section analysis of the differences between the original ELF files
printf "ELF #1-#2 total/common/specific section analysis:\n" | tee -a ${name}.log
#ELF #1 and #2 total section and size differencies
elf1SecsTotal=$(echo "$elf1Total" | tr -s ' ' | cut -d ' ' -f6)
elf1SizeTotal=$(echo "$elf1Total" | tr -s ' ' | cut -d ' ' -f9)
elf2SecsTotal=$(echo "$elf2Total" | tr -s ' ' | cut -d ' ' -f6)
elf2SizeTotal=$(echo "$elf2Total" | tr -s ' ' | cut -d ' ' -f9)
diffSizeTotal=$((elf1SizeTotal-elf2SizeTotal))
printf "ELF #1-#2 total    : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elf1SecsTotal-elf2SecsTotal)) "$objType" $diffSizeTotal $((diffSizeTotal/1024)) $((diffSizeTotal/(1024*1024))) | tee -a ${name}.log

#ELF #1 and #2 common section and size differencies
elf1SecsCommon=$(echo "$elf1Common" | tr -s ' ' | cut -d ' ' -f6)
elf1SizeCommon=$(echo "$elf1Common" | tr -s ' ' | cut -d ' ' -f9)
elf2SecsCommon=$(echo "$elf2Common" | tr -s ' ' | cut -d ' ' -f6)
elf2SizeCommon=$(echo "$elf2Common" | tr -s ' ' | cut -d ' ' -f9)
diffSizeCommon=$((elf1SizeCommon-elf2SizeCommon))
printf "ELF #1-#2 common   : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elf1SecsCommon-elf2SecsCommon)) "$objType" $diffSizeCommon $((diffSizeCommon/1024)) $((diffSizeCommon/(1024*1024))) | tee -a ${name}.log

#ELF #1 and #2 specific section and size differencies
elf1SecsSpecific=$(echo "$elf1Specific" | tr -s ' ' | cut -d ' ' -f6)
elf1SizeSpecific=$(echo "$elf1Specific" | tr -s ' ' | cut -d ' ' -f9)
elf2SecsSpecific=$(echo "$elf2Specific" | tr -s ' ' | cut -d ' ' -f6)
elf2SizeSpecific=$(echo "$elf2Specific" | tr -s ' ' | cut -d ' ' -f9)
diffSizeSpecific=$((elf1SizeSpecific-elf2SizeSpecific))
printf "ELF #1-#2 specific : %6d %s : %9d B / %8.2f KB / %5.2f MB\n" $((elf1SecsSpecific-elf2SecsSpecific)) "$objType" $diffSizeSpecific $((diffSizeSpecific/1024)) $((diffSizeSpecific/(1024*1024))) | tee -a ${name}.log

# compare sections if requested
if [ ! -z $sections ]; then
	[ ! -z "$objdump1" ] && objdump1p="-od $objdump1"
	${path}/elfSectionAnalyzer.sh -e ${elf1} $objdump1p $validation > /dev/null
	_err_=$?
	if [ $_err_ != 0 ]; then
		echo "${name}: Error=$_err_ executing \"${path}/elfSectionAnalyzer.sh -e ${elf1} $objdump1p $validation. Exit.\"" | tee -a ${name}.log
		exit 4
	fi
	[ ! -z "$objdump2" ] && objdump2p="-od $objdump2"
	${path}/elfSectionAnalyzer.sh -e ${elf2} $objdump2p $validation > /dev/null
	_err_=$?
	if [ $_err_ != 0 ]; then
		echo "${name}: Error=$_err_ executing \"${path}/elfSectionAnalyzer.sh -e ${elf2} $objdump2p $validation. Exit.\"" | tee -a ${name}.log
		exit 5
	fi
	${path}/elfSectionCompare.sh -1 ${elf1}.ax -2 ${elf2}.ax -3 ${of}.ax $validation #> /dev/null
fi

if [ ! -z "$validation" ]; then
	if [ $elf1SecsTotal -ne $((elf1SecsCommon+elf1SecsSpecific)) ]; then
		echo "$name# WARN : data validation failed for elf1SecsTotal: $elf1SecsTotal != $((elf1SecsCommon+elf1SecsSpecific))" | tee -a ${name}.log
	elif [ $elf2SecsTotal -ne $((elf2SecsCommon+elf2SecsSpecific)) ]; then
		echo "$name# WARN : data validation failed for elf2SecsTotal: $elf2SecsTotal != $((elf2SecsCommon+elf2SecsSpecific))" | tee -a ${name}.log
	elif [ $elf1SizeTotal -ne $((elf1SizeCommon+elf1SizeSpecific)) ]; then
		echo "$name# WARN : data validation failed for elf1SizeTotal: $elf1SizeTotal != $((elf1SizeCommon+elf1SizeSpecific))" | tee -a ${name}.log
	elif [ $elf2SizeTotal -ne $((elf2SizeCommon+elf2SizeSpecific)) ]; then
		echo "$name# WARN : data validation failed for elf2SizeTotal: $elf2SizeTotal != $((elf2SizeCommon+elf2SizeSpecific))" | tee -a ${name}.log
	else
		echo "$name# : data validation success" | tee -a ${name}.log
	fi

	eshFileValidation2 ${of} $elf1SizeTotal $elf2SizeTotal $diffSizeTotal ${name}.log
	eshFileValidation2 ${of}.rnk5 $elf1SizeTotal $elf2SizeTotal $diffSizeTotal ${name}.log
	eshFileValidation2 ${of}.common $elf1SizeCommon $elf2SizeCommon $diffSizeCommon ${name}.log

	eshFileValidation ${of}.specific1 $elf1SizeSpecific ${name}.log
	eshFileValidation ${of}.specific2 $elf2SizeSpecific ${name}.log
fi

# add headers
sed -i "1i$ESH_HEADER_2" ${of}
sed -i "1i$ESH_HEADER_2" ${of}.common
sed -i "1i$ESH_HEADER_2" ${of}.rnk5
[ -s ${of}.specific1 ] && sed -i "1i$ESH_HEADER_1" ${of}.specific1
[ -s ${of}.specific2 ] && sed -i "1i$ESH_HEADER_1" ${of}.specific2

# Cleanup
rm -f ${elf1}.esh ${elf2}.esh

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "${name}: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

