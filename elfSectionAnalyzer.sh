#!/bin/bash
#

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-e elf [-o of]] | [-h]"
	echo "$name# ELF object section analyzer"
	echo "$name# -e    : an ELF object"
	echo "$name# -o    : an output file base name"
	echo "$name# -F    : output a function file offset"
	echo "$name# -h    : display this help and exit"
	echo "$name#       : USE_SYSRES_PLATFORM { ARM | MIPS | x86 } = $([ ! -z "$USE_SYSRES_PLATFORM" ] && echo $USE_SYSRES_PLATFORM || echo "?")" 
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
while [ "$1" != "" ]; do
	case $1 in
		-e )   shift
				elf=$1
				;;
		-o )   shift
				of=$1
				;;
		-F )   shift
				funcFO=y
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

objdump=
platform=
if [ "$USE_SYSRES_PLATFORM" != "" ]; then
	platform=$(echo $USE_SYSRES_PLATFORM | tr '[:lower:]' '[:upper:]')
	case $platform in
		ARM  ) objdump=armeb-rdk-linux-uclibceabi-objdump ;;
		x86  ) objdump=i686-cm-linux-objdump ;;
		MIPS ) objdump=mipsel-linux-objdump ;;
		   * ) 
			echo "$name# ERROR : unsupported $USE_SYSRES_PLATFORM platform"
			echo "$name# ERROR : USE_SYSRES_PLATFORM = {ARM | MIPS | x86}"
			usage
			exit 1
	esac

	if [ "$(which $objdump)" == "" ]; then
		echo "$name# ERROR : Path to $objdump is not set!"
		usage
		exit
	fi
else
	echo "$name# ERROR : USE_SYSRES_PLATFORM = {ARM | MIPS | x86} env variable is NOT defined!"
	usage
	exit 1
fi

[ -z "$of" ] && of=${elf}
#echo "ELFS #3 =  $of" | tee -a ${name}.log

# create "start/end of executable sections" file
readelf -S "$elf" | grep " AX " | tr -s '[]' ' ' | tr -s ' ' | cut -d ' ' -f5,7 > ${of}.exec-secs
endst=0x$(tail -1 ${of}.exec-secs | cut -d ' ' -f1)
endsi=0x$(tail -1 ${of}.exec-secs | cut -d ' ' -f2)
start=0x$(head -1 ${of}.exec-secs | cut -d ' ' -f1)
end=$((endst + endsi - 1))

# create function map file: 1c - start address; 2c - length; 3c - function file offset; 4c - function name
$objdump -dC "$elf" | grep "^[[:xdigit:]]\{8\}" | awk '{printf "0x%s\n", $0}' > ${of}.text.tmp
pFuncAddr=
pFuncAttr=
cat /dev/null > ${of}.text
while read -r cFuncAddr cFuncAttr
do
	[ ! -z "$pFuncAddr" ] && printf "0x%08x\t%09d\t%s\n" $pFuncAddr $((cFuncAddr-pFuncAddr)) "$pFuncName" >> ${of}.text
	pFuncAddr=$cFuncAddr
	pFuncName=$cFuncAttr
done < ${of}.text.tmp
lastFunc=$(tail -1 ${of}.text.tmp)
printf "%s\t%09d\t%s\n" $(echo $lastFunc | cut -d ' ' -f1) $endsi $(echo $lastFunc | cut -d ' ' -f2-) >> ${of}.text
sort -rnk2 ${of}.text -o ${of}.text.rnk2

# add headers
sed -i "1i$(printf "0x%08x\t%s\n" $((start)) "$ELF_PSEC_STARTOF_TEXT")" ${of}.text
printf "0x%08x\t%s\n" $((end)) "$ELF_PSEC_ENDOF_TEXT" >> ${of}.text
sed -i "1i$ESH_HEADER_TEXT_1" ${of}.text
sed -i "1i$ESH_HEADER_TEXT_1" ${of}.text.rnk2

# Cleanup
rm ${of}.text.tmp ${of}.exec-secs
