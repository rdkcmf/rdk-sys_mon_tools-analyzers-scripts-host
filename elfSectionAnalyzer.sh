#!/bin/bash
#

# Variables:
ODDSFILTER='[FO] \.text'$'\t'"\|"'O \.bss'$'\t'"\|"'O \.data'$'\t'"\|"'O \.rodata'$'\t'"\|"'O .data.rel.ro'$'\t'
ODUSFILTER='[FO ] \*UND\*'$'\t'

# Function: usage
function usage()
{
	echo "${name}# Usage : `basename $0 .sh` [-e elf [-o of]] | [-h]"
	echo "${name}# ELF object section analyzer"
	echo "${name}# -e    : an ELF object"
	echo "${name}# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "${name}# -o    : an output file base name"
	echo "${name}# -al   : append logging"
	echo "${name}# -u    : produce a list of undefined symbols"
	echo "${name}# -V    : validate produced data"
	echo "${name}# -F    : produce function file offsets - not implemented yet"
	echo "${name}# -h    : display this help and exit"
}

# Function: eshLog
# $1: eshFile	- an elf section file
# $2: eshFColumn- a column # describing object sizes
# $3: eshLog	- log file
function eshLog()
{
	if [ -s $1 ]; then
		eshDescr=${1#$elf.}
		awk -v eshFile="$1" -v eshSize="$2" -v eshDescr="$eshDescr" 'BEGIN {FS="\t"}; {total += $eshSize} END { printf "%-14s = %6d objects : %9d B / %8.2f KB / %5.2f MB : %s\n", eshDescr, NR, total, total/1024, total/(1024*1024), eshFile}' "$1" | tee -a $3
	else
		printf "%-14s = %6d objects : %9d B / %8.2f KB / %5.2f MB : %s\n" "$eshDescr" 0 0 0 0 "$1" | tee -a $3
	fi
}

# Function: sectionSize
# $1: elfFile
# $2: sectionName
function sectionSize()
{
	if [ -s "$1.readelf-S" ]; then
		grep " \.$2 " "$1.readelf-S" | tr -s '[]' ' ' | tr -s ' ' | cut -d ' ' -f7 | awk '{total += strtonum("0x"$1)} END {printf "%d\n", total}' > "$1"."O$2".space
	fi	
}

# Function: validateSection
# $1: sectionSize
# $2: sectionFile
# validateSection $(cat $file.space) $file
function validateSection()
{
	local _sectionSize_=$1
	local _sectionFile_=$2
	if [ -s "$_sectionFile_" ]; then
		local _sectionFileSize_=$(awk '{total += $2} END { printf "%d\n", total} ' $_sectionFile_)
		if [ "$_sectionSize_" -ne "$_sectionFileSize_" ]; then
			printf "space/size validation mismatch: space = %9d B : size = %9d B : space-size = %9d B : %s\n" $_sectionSize_ $_sectionFileSize_ $((_sectionSize_-_sectionFileSize_)) $_sectionFile_ | tee -a ${name}.log
		else
			printf "space/size validation success : space/size = %9d B : %s\n" $_sectionSize_ $_sectionFile_ | tee -a ${name}.log
		fi
	fi	
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/elfHeaders.sh

of=
elf=
funcFO=
objdump=
validation=
appendLog=
undSymbols=
while [ "$1" != "" ]; do
	case $1 in
		-e )   shift
				elf=$1
				;;
		-o )   shift
				of=$1
				;;
		-od )  shift
				objdump=$1
				;;
		-al )		appendLog=y
				;;
		-u )		undSymbols=y
				;;
		-V )		validation=y
				;;
		-F )		funcFO=y
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

[ -z "$appendLog" ] && echo "$cmdline" > ${name}.log || echo "$cmdline" >> ${name}.log

# Check if an elf object
isElf="$(file -b "$elf" | grep "^ELF ")"
if [ -z "$isElf" ]; then
	echo "${name} : ERROR  : ${elf} is NOT an ELF file!" | tee -a ${name}.log
	usage
	exit 2
fi

# Check if a supported ELF object architechture
elfArch=$(echo "$isElf" | cut -d, -f2)
if [ ! -z "$(echo "$elfArch" | grep "MIPS")" ]; then
	[ -z ${objdump} ] && objdump=mipsel-linux-objdump
elif [ ! -z "$(echo "$elfArch" | grep "Intel .*86")" ]; then
	[ -z ${objdump} ] && objdump=i686-cm-linux-objdump
elif [ ! -z "$(echo "$elfArch" | grep "ARM")" ]; then
	[ -z ${objdump} ] && objdump=armeb-rdk-linux-uclibceabi-objdump
else
	echo "${name}# ERROR : unsupported architechture : $elfArch" | tee -a ${name}.log
	echo "${name}# ERROR : supported architechtures  = {ARM | MIPS | x86}" | tee -a ${name}.log
	usage
	exit 3
fi

# Check if PATH to $objdump is set
if [ "$(which ${objdump})" == "" ]; then
	echo "${name}# ERROR : Path to ${objdump} is not set!" | tee -a ${name}.log
	usage
	exit 4
fi

[ -z "$of" ] && of=${elf}

readelf -S ${elf} > ${of}.readelf-S
elfSymbols=$(grep " .debug_\| .pdr\| .comment\| .symtab\| .strtab" ${of}.readelf-S)
if [ -z "$elfSymbols" ]; then
	elfSymbols="stripped"
else
	elfSymbols="not stripped sections : "$(printf "%s\n" "${elfSymbols}" | tr -s '[]' ' ' | tr -s ' ' | cut -d ' ' -f3 | sed 's/.debug_.*/.dbg/g' | sort | uniq | tr -d '\n' | awk '{print $0}')
fi

echo "elf = ${elf}" : "${elfSymbols}" | tee -a ${name}.log
echo "out = ${of}" | tee -a ${name}.log
echo "od  = ${objdump}" | tee -a ${name}.log

# create "start/end of executable sections" file
grep " AX " ${of}.readelf-S | tr -s '[]' ' ' | tr -s ' ' | cut -d ' ' -f3,5,7 | awk '{printf "0x%s\t%09d\t%s\n", $2, strtonum("0x"$3), $1}' > ${of}.ax-secs
endst=$(tail -1 ${of}.ax-secs | cut -f1)
endsi=$(tail -1 ${of}.ax-secs | cut -f2 | awk '{printf "0x%x\n", $1}')
start=$(head -1 ${of}.ax-secs | cut -f1)
end=$((endst + endsi - 1))

notStripped=$(echo $isElf | grep "not stripped$")
if [ -z "$notStripped" ]; then
	# stripped ELF binary analysis
	# create AX section map file: 1c - start address; 2c - length; (3c - function file offset) not implemented; 4c - function name
	_err_=$?
	${objdump} -dC "$elf" | grep "^[[:xdigit:]]\{8\}" | sed 's/ </ /;s/>:$//' | awk '{printf "0x%s\n", $0}' > ${of}.ax.tmp
	if [ $_err_ != 0 ]; then
		echo "${name}: Error=$_err_ executing ${objdump} ${elf}. Exit." | tee -a ${name}.log
		exit 5
	fi
	pFuncAddr=
	pFuncAttr=
	cat /dev/null > ${of}.ax
	while read -r cFuncAddr cFuncAttr
	do
		[ ! -z "$pFuncAddr" ] && printf "0x%08x\t%09d\t%s\n" $pFuncAddr $((cFuncAddr-pFuncAddr)) "$pFuncName" >> ${of}.ax
		pFuncAddr=$cFuncAddr
		pFuncName=$cFuncAttr
	done < ${of}.ax.tmp
	lastFunc=$(tail -1 ${of}.ax.tmp)
	printf "%s\t%09d\t%s\n" $(echo $lastFunc | cut -d ' ' -f1) $endsi $(echo $lastFunc | cut -d ' ' -f2-) >> ${of}.ax

	# summarize a number of ax section objects and their sizes
	printf "%-14s : %6s Objects : %s\n" "Sections" " " "Total size of objects" | tee -a ${name}.log
	eshLog ${of}.ax 2 ${name}.log

	# Cleanup
	rm -f ${of}.ax.tmp
else
	# not-stripped ELF binary analysis
	${objdump} -tC "$elf" | sort -u -o ${of}.od-tC
	grep "$ODDSFILTER" ${of}.od-tC | cut -b1-9,16,19- | tr -s ' ' | sed 's/ /\t/;s/ /\t/' | awk -F'\t' '{printf "%-10s\t0x%s\t%09d\t%s\n", $2, $1, strtonum("0x"$3), $4}' > ${of}.odds
	if [ ! -z "$undSymbols" ]; then
		grep "$ODUSFILTER" ${of}.od-tC | cut -b1-9,16,19-21,23- | tr -s ' ' | sed 's/ /\t/;s/ /\t/' | awk -F'\t' '{printf "%-10s\t0x%s\t%09d\t%s\n", $2, $1, strtonum("0x"$3), $4}' > ${of}.odus
		[ -s ${of}.odus ] && sed -i "1i$ESH_HEADER_ODDS" ${of}.odus
	fi
	printf '' | tee ${of}.Ftext ${of}.Otext ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss
	while IFS=$'\t' read section therest; do
		echo "$therest" >> ${of}.${section}
	done < ${of}.odds
	cat ${of}.Ftext <(grep -v "\.text" ${of}.ax-secs) | sort -k1,1 -o ${of}.ax

	# summarize a number of section objects and their sizes
	printf "%-14s : %6s Objects : %s\n" "Sections" " " "Total size of objects" | tee -a ${name}.log
	#for file in ${of}.Ftext ${of}.Otext ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss; do
	for file in ${of}.ax ${of}.Otext ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss; do
		if [ -s ${file} ]; then
			eshLog ${file} 2 ${name}.log
		fi
	done

	# create a formatted ${of}.ax.source file
	maxExt=$(cut -f3 ${of}.ax | wc -L | cut -f1)
	printf "%-10s\t%-9s\t%-*s\t%s\n" "Address" "Size" $maxExt "Function Name" "Function source location"> ${of}.ax.source
	cut -f1 ${of}.ax | addr2line -Cp -e ${elf} | paste ${of}.ax - | awk -v mL=$maxExt 'BEGIN {FS="\t"}; {printf "%s\t%s\t%-*s\t%s\n", $1, $2, mL, $3, $4}' >> ${of}.ax.source

	#Cleanup
	rm -f ${of}.Ftext ${of}.od-tC
fi

sort -rnk2 ${of}.ax -o ${of}.ax.rnk2

totalAXSecsSize=$(awk '{total += $2} END { printf "%d\n", total} ' ${of}.ax-secs)
totalAXSecsSpace=$((endst + endsi - start))
if [ ! -z "$validation" ]; then
	cat <(cut -f2- ${of}.odds) <(grep -v "\.text" ${of}.ax-secs) | sort -k1,1 -o ${of}.odds.all

	cat /dev/null > ${of}.Total
	for file in ${of}.ax ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss ${of}.Otext; do
		if [ -s ${file} ]; then 
			cat ${file} >> ${of}.Total
		fi
	done
	sort ${of}.Total -o ${of}.Total
	eshLog ${of}.Total 2 ${name}.log

	totalCount=$(wc -l ${of}.Total | cut -d ' ' -f1)
	totalOddsCount=$(wc -l ${of}.odds.all | cut -d ' ' -f1)
	if [ "$totalCount" -ne "$totalOddsCount" ]; then
		printf "total/individual obj mismatch : total = %9d indl = %9d : total-indl = %9d\n" $totalCount $totalOddsCount $((totalCount-totalOddsCount)) | tee -a ${name}.log
	else
		printf "total/indl obj split success  : total = %d objects\n" $totalCount | tee -a ${name}.log
	fi

	for sectionName in "data" "rodata" "data.rel.ro" "bss"; do
		sectionSize ${of} "$sectionName"
	done

	printf "%d\n" $totalAXSecsSpace > ${of}.ax.space
	for file in ${of}.ax ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss; do
		if [ -s ${file} ] && [ -s ${file}.space ]; then 
			validateSection $(cat ${file}.space) ${file}
		fi
	done

	#Cleanup
	rm ${of}.*.space ${of}.odds.all
fi

# add headers
sed -i "1i$ESH_HEADER_TEXT_1" ${of}.ax
sed -i "1i$ESH_HEADER_TEXT_1" ${of}.ax.rnk2
sed -i "1i$ESH_HEADER_AXSECS" ${of}.ax-secs
[ -s ${of}.odds ] && sed -i "1i$ESH_HEADER_ODDS" ${of}.odds
# ... and clean if needed
if [ ! -z "$notStripped" ]; then
	for file in ${of}.Otext ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss; do
		[ ! -s ${file} ] && rm ${file} || sed -i "1i$ESH_HEADER_OBJ_1" ${file}
	done
fi
printf "%10s%09d/%09d\t%s\n" " " $totalAXSecsSpace $totalAXSecsSize "Total space/size" >> ${of}.ax-secs

