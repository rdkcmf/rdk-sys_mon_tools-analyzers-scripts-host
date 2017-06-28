#!/bin/bash
#

# Variables:
ODDSFILTER='F \.text'$'\t'"\|"'O .text'$'\t'"\|"'O \.bss'$'\t'"\|"'O \.data'$'\t'"\|"'O \.rodata'$'\t'"\|"'O .data.rel.ro'$'\t'

# Function: usage
function usage()
{
	echo "${name}# Usage : `basename $0 .sh` [-e elf [-o of]] | [-h]"
	echo "${name}# ELF object section analyzer"
	echo "${name}# -e    : an ELF object"
	echo "${name}# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "${name}# -o    : an output file base name"
	echo "${name}# -al   : append logging"
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
		-V )		validation="y"
				;;
		-F )   shift
				funcFO=y
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

	# Cleanup
	rm -f ${of}.ax.tmp
else
	${objdump} -tC "$elf" | sort -u | grep "$ODDSFILTER" | tr -s ' ' | cut -d ' ' -f1,3- | sed 's/F ./F/;s/O ./O/;s/\t/ /;s/ /\t/;s/ /\t/;s/ /\t/' | awk -F'\t' '{printf "%-10s\t0x%s\t%09d\t%s\n", $2, $1, strtonum("0x"$3), $4}' > ${of}.odds
	printf '' | tee ${of}.Ftext ${of}.Otext ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss
	while IFS=$'\t' read section therest; do
		echo "$therest" >> ${of}.${section}
	done < ${of}.odds
	cat ${of}.Ftext <(grep -v "\.text" ${of}.ax-secs) | sort -k1,1 -o ${of}.ax

	# calculate a number of section objects and their sizes
	for file in ${of}.Ftext ${of}.Otext ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss; do
		if [ -s ${file} ]; then
			eshLog ${file} 2 ${name}.log
		fi
	done

	# create a formatted ${of}.ax.source file
	maxExt=$(cut -f3 ${of}.ax | wc -L | cut -f1)
	printf "%-10s\t%-9s\t%-*s\t%s\n" "Address" "Size" $maxExt "Function Name" "Function source location"> ${of}.ax.source
	cut -f1 ${of}.ax | addr2line -Cp -e ${elf} | paste ${of}.ax - | awk -v mL=$maxExt 'BEGIN {FS="\t"}; {printf "%s\t%s\t%-*s\t%s\n", $1, $2, mL, $3, $4}' >> ${of}.ax.source

	#Cleanup
#	rm -f ${of}.odds
	for file in ${of}.Ftext ${of}.Otext ${of}.Odata ${of}.Orodata ${of}.Odata.rel.ro ${of}.Obss; do
		[ ! -s ${file} ] && rm ${file} || sed -i "1i$ESH_HEADER_OBJ_1" ${file}
	done
fi

sort -rnk2 ${of}.ax -o ${of}.ax.rnk2

totalAXSecsSize=$(awk '{total += $2} END { printf "%d\n", total} ' ${of}.ax-secs)
totalAXSecsSpace=$((endst + endsi - start))
if [ "$validation" == "y" ]; then
	totalAXSecsSizeFile=$(awk '{total += $2} END { printf "%d\n", total} ' ${of}.ax)
	totalAXSecsSizeRnk2File=$(awk '{total += $2} END { printf "%d\n", total} ' ${of}.ax.rnk2)
	if [ "$totalAXSecsSpace" -ne "$totalAXSecsSizeFile" ]; then
		echo "${name}# total AX sections size/space mismatch for ${of}.ax : size = $totalAXSecsSizeFile : space = $totalAXSecsSpace : size - space = $((totalAXSecsSizeFile-totalAXSecsSpace))" | tee -a ${name}.log
	elif [ "$totalAXSecsSpace" -ne "$totalAXSecsSizeRnk2File" ]; then
		echo "${name}# total AX sections size/space mismatch for ${of}.ax.rnk2: size = $totalAXSecsSizeRnk2File : space = $totalAXSecsSpace : size - space = $((totalAXSecsSizeFile-totalAXSecsSpace))" | tee -a ${name}.log
	else
		echo "${name}# : validation success : total AX secs size/space = $totalAXSecsSpace : ${of}.ax ${of}.ax.rnk2" | tee -a ${name}.log
	fi
fi

# add headers
sed -i "1i$ESH_HEADER_TEXT_1" ${of}.ax
sed -i "1i$ESH_HEADER_TEXT_1" ${of}.ax.rnk2
sed -i "1i$ESH_HEADER_AXSECS" ${of}.ax-secs
[ -s ${of}.odds ] && sed -i "1i$ESH_HEADER_ODDS" ${of}.odds
printf "%10s%09d/%09d\t%s\n" " " $totalAXSecsSpace $totalAXSecsSize "Total space/size" >> ${of}.ax-secs

