#!/bin/bash
#

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-e elf [-o of]] | [-h]"
	echo "$name# ELF object section analyzer"
	echo "$name# -e    : an ELF object"
	echo "$name# -od   : an objdump to use instead of default: {armeb-rdk-linux-uclibceabi-objdump | mipsel-linux-objdump | i686-cm-linux-objdump}"
	echo "$name# -o    : an output file base name"
	echo "$name# -s    : add source code locations to output"
	echo "$name# -V    : validate produced data"
	echo "$name# -F    : produce function file offsets - not implemented yet"
	echo "$name# -h    : display this help and exit"
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
echo "$cmdline" >> ${name}.log

path=$0
path=${path%/*}
source $path/elfHeaders.sh

of=
elf=
funcFO=
objdump=
source=
validation=
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
		-V )		validation="y"
				;;
		-s )		source=y
				;;
		-F )   shift
				funcFO=y
				;;
		-h | --help )   usage
				exit
				;;
		* )             echo "$name# ERROR : unknown parameter \"$1\" in the command argument list!" | tee -a ${name}.log
				usage
				exit 1
    esac
    shift
done

# Check if an elf object
isElf="$(file -b "$elf" | grep "^ELF ")"
if [ -z "$isElf" ]; then
	echo "$name : ERROR  : ${elf} is NOT an ELF file!" | tee -a ${name}.log
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
	echo "$name# ERROR : unsupported architechture : $elfArch" | tee -a ${name}.log
	echo "$name# ERROR : supported architechtures  = {ARM | MIPS | x86}" | tee -a ${name}.log
	usage
	exit 3
fi

# Check if PATH to $objdump is set
if [ "$(which ${objdump})" == "" ]; then
	echo "$name# ERROR : Path to ${objdump} is not set!" | tee -a ${name}.log
	usage
	exit 4
fi

[ -z "$of" ] && of=${elf}

echo "ELF = ${elf}" | tee -a ${name}.log
echo "out = ${of}" | tee -a ${name}.log
echo "od  = ${objdump}" | tee -a ${name}.log

# create "start/end of executable sections" file
readelf -S "$elf" | grep " AX " | tr -s '[]' ' ' | tr -s ' ' | cut -d ' ' -f3,5,7 | awk '{printf "0x%s\t%09d\t%s\n", $2, strtonum("0x"$3), $1}' > ${of}.ax-secs
endst=$(tail -1 ${of}.ax-secs | cut -f1)
endsi=$(tail -1 ${of}.ax-secs | cut -f2 | awk '{printf "0x%x\n", $1}')
start=$(head -1 ${of}.ax-secs | cut -f1)
end=$((endst + endsi - 1))

# create function map file: 1c - start address; 2c - length; 3c - function file offset; 4c - function name
_err_=$?
${objdump} -dC "$elf" | grep "^[[:xdigit:]]\{8\}" | awk '{printf "0x%s\n", $0}' > ${of}.ax.tmp
if [ $_err_ != 0 ]; then
	echo "$name: Error=$_err_ executing ${objdump} ${elf}. Exit." | tee -a ${name}.log
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
if [ ! -z "$source" ]; then
	if [ ! -z "$(echo $isElf | grep "not stripped$")" ]; then
		maxExt=$(cut -f3 ${of}.ax | wc -L | cut -f1)
		printf "%-10s\t%-9s\t%-*s\t%s\n" "Address" "Size" $maxExt "Function Name" "Function source location"> ${of}.ax.source
		cut -f1 ${of}.ax | addr2line -Cp -e ${elf} | paste ${of}.ax - | awk -v mL=$maxExt 'BEGIN {FS="\t"}; {printf "%s\t%s\t%-*s\t%s\n", $1, $2, mL, $3, $4}' >> ${of}.ax.source
	else
		echo "$name# WARN : ELF ${elf} is stripped, no symbols"
	fi
fi
sort -rnk2 ${of}.ax -o ${of}.ax.rnk2

totalAXSecsSize=$(awk '{total += $2} END { printf "%d\n", total} ' ${of}.ax-secs)
totalAXSecsSpace=$((endst + endsi - start))
if [ "$validation" == "y" ]; then
	totalAXSecsSizeFile=$(awk '{total += $2} END { printf "%d\n", total} ' ${of}.ax)
	totalAXSecsSizeRnk2File=$(awk '{total += $2} END { printf "%d\n", total} ' ${of}.ax.rnk2)
	if [ "$totalAXSecsSpace" -ne "$totalAXSecsSizeFile" ]; then
		echo "$name# WARN : validation failed for ${of}.ax : file total size = $totalAXSecsSizeFile : total AX sections space = $totalAXSecsSpace : diff = $((totalAXSecsSizeFile-totalAXSecsSpace))" | tee -a ${name}.log
	elif [ "$totalAXSecsSpace" -ne "$totalAXSecsSizeRnk2File" ]; then
		echo "$name# WARN : validation failed for ${of}.ax.rnk2: file total size = $totalAXSecsSizeRnk2File : total AX sections space = $totalAXSecsSpace : diff = $((totalAXSecsSizeFile-totalAXSecsSpace))" | tee -a ${name}.log
	else
		echo "$name# : validation success : total AX secs space = $totalAXSecsSpace : ${of}.ax ${of}.ax.rnk2" | tee -a ${name}.log
	fi
fi

# add headers/footers
sed -i "1i$(printf "0x%08x\t%s\n" $((start)) "$ELF_PSEC_STARTOF_TEXT")" ${of}.ax
printf "0x%08x\t%s\n" $((end)) "$ELF_PSEC_ENDOF_TEXT" >> ${of}.ax
sed -i "1i$ESH_HEADER_TEXT_1" ${of}.ax
sed -i "1i$ESH_HEADER_TEXT_1" ${of}.ax.rnk2
sed -i "1i$ESH_HEADER_AXSECS" ${of}.ax-secs
printf "%10s%09d/%09d\t%s\n" " " $totalAXSecsSpace $totalAXSecsSize "Total space/size" >> ${of}.ax-secs

# Cleanup
rm ${of}.ax.tmp
