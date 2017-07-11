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

# component name to allow any char except forward slash
COMPREGEXP='\([^/]*\)'
# full/absolute (not relative) path
FPATHREGEXP='/\(.*\)\([^/]*\)'

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-f tcFileList [-cf cfFileList] | [-fc fcmFileList] [-V]] [-h]"
	echo "$name# rootFS File List Componentizer"
	echo "$name# -f    : a 1/9-column rootFS file list to componentize : ls -1/ls -lA format"
	echo "$name# -fc   : a 2 column tab separated file-component map file - mutually exclusive with -cf"
	echo "$name# -cf   : a 2 column tab separated component-file map file - mutually exclusive with -fc"
	echo "$name# -mcm  : a 2 column tab-separated macro-component / component map file"
	echo "$name# -ca   : componentize all - make not componentized files a part of not-componentized component"
	echo "$name# -u    : convert input files to unix format before usage"
	echo "$name# -V    : validation of the produced ouput"
	echo "$name# -h    : display this help and exit"
}

# Function: filelistMetrics
# $1: file list	to calculate and print metrics
# $2: file list descriptor
# $3: file list columns count	- 
# $4: log file
function filelistMetrics()
{
	if [ -s "$1" ]; then
		if [ $3 -eq 9 ]; then
			awk -v fileName="$1" -v fileDescr="$2" '{total += $5} END { printf "%-16s : %5d files / %9d Bytes / %6d KB / %3d MB : %s\n", fileDescr, NR, total, total/1024, total/(1024*1024), fileName }' $1 | tee -a $4
		else
			awk -v fileName="$1" -v fileDescr="$2" 'END { printf "%-16s : %5d files : %s\n", fileDescr, NR, fileName }' $1 | tee -a $4
		fi
	else
		printf "%-16s : %5d files / %9d Bytes / %6d KB / %3d MB :\n" "$2" 0 0 0 0 | tee -a $4
	fi
}

# Function: flcomplval - file list complement validation
# $1: input file: complete file list
# $2: input file: complement file list #1
# $3: input file: complement file list #2
# $4: input parameter: sort column
function flcomplval()
{
	[ "$4" == "" ] && col=1 || col=$4
	[ "$(md5sum "$1" | cut -d ' ' -f1)" == "$(cat "$2" "$3" | sort -k$col | md5sum | cut -d ' ' -f1)" ] && echo "succeeded" || echo "failed"
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
echo "$cmdline" > $name.log

validate="n"
tcFileList=
cmFileList=
macroCompMap=
compAll="n"	#componentize all
tounix=
while [ "$1" != "" ]; do
	case $1 in
		-f ) 	shift
			tcFileList=$1
			;;
		-fc ) 	shift
			ccol=2
			fcol=1
			cmFileList=$1
			;;
		-cf ) 	shift
			ccol=1
			fcol=2
			cmFileList=$1
			;;
		-mcm ) 	shift
			macroCompMap=$1
			;;
		-ca ) 	compAll="y"
			;;
		-V )	validate="y"
			;;
		-u )	tounix="y"
			;;
		-h| --help)
			usage
			exit
			;;
		* )	echo "$name# ERROR : unknown parameter in the command argument list!"
			usage
			exit 1
	esac
	shift
done

if [ ! -s "$tcFileList" ]; then
	echo "$name# ERROR : file list \"$tcFileList\" to componentize is empty or not found!"
	usage
	exit
fi

if [ ! -s "$cmFileList" ]; then
	echo "$name# ERROR : Component map file list \"$cmFileList\" is empty or not found!"
	usage
	exit
fi

if [ -n "$tounix" ]; then 
	dos2unix $tcFileList $cmFileList &> /dev/null
fi

tcCol=$(awk '{printf "%d\n", NF}' $tcFileList | sort -u -n)
if [ "$tcCol" != "9" ] && [ "$tcCol" != "1" ]; then
	echo "$name# ERROR : file list \"$tcFileList\" to componentize is not a 1/9-column file!"
	usage
	exit
fi

if [ "$(awk '{printf "%d\n", NF}' $cmFileList | sort -u -n)" != "2" ]; then
	echo "$name# ERROR : Component map file list  \"$cmFileList\" is not a 2-column file!"
	usage
	exit
fi

if [ "$macroCompMap" != "" ] && [ ! -s "$macroCompMap" ]; then
	echo "$name# ERROR : Macro Component map \"$macroCompMap\" is empty or not found!"
	usage
	exit
fi

cat /dev/null > $cmFileList.error
awk -F "[ \t]+" -v cclmn=$ccol -v map=$cmFileList '{ if (match($cclmn, "/")) printf "%04d: %s\n", NR, $cclmn >> map".error" }' $cmFileList
if [ -s $cmFileList.error ]; then
	echo "$name# ERROR : Component map file list  \"$cmFileList\" contains forward slash / in the component field!"
	usage
	exit
fi
rm $cmFileList.error

if [ "$ccol" -eq 1 ]; then
	match=$(grep ^$COMPREGEXP$'\t'$FPATHREGEXP$ ${cmFileList})
	if [ -z "$match" ]; then
		echo "$name# ERROR : Component map file list  \"$cmFileList\" doesn't conform to the supported file format!"
		usage
		exit
	fi
elif [ "$ccol" -eq 2 ]; then
	match=$(grep ^$FPATHREGEXP$'\t'$COMPREGEXP$ ${cmFileList})
	if [ -z "$match" ]; then
		echo "$name# ERROR : Component map file list  \"$cmFileList\" doesn't conform to the supported file format!"
		usage
		exit
	fi
fi

tcFileListBN=`basename $tcFileList`
echo "$name : Component Map File          = $cmFileList" | tee -a $name.log
echo "$name : Componentize all            = $compAll" | tee -a $name.log
[ "$fcol" == "1" ] && echo "$name : Component Map File type     = filename-component" | tee -a $name.log || echo "$name : Component Map File type     = component-filename" | tee -a $name.log

# Main:
startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
sort -k$tcCol $tcFileList -o $tcFileList.sorted
sort -k$fcol,$fcol $cmFileList -o $cmFileList.sorted

cat /dev/null > $tcFileListBN.fcd
cat /dev/null > $tcFileListBN.componentized
cat /dev/null > $tcFileListBN.not-componentized
cat /dev/null > $tcFileListBN.componentized.tmp
if [ $tcCol -eq 9 ] ;then
	join -a1 -1 9 -2 $fcol $tcFileList.sorted $cmFileList.sorted | awk -v base=$tcFileListBN \
	'{ \
		printf "%s %s %s %s %8s %s %s %s %22s %s\n", $2, $3, $4, $5, $6, $7, $8, $9, $10, $1 >> base".fcd"; \
		if ($10 != "") \
		{ \
			printf "%s\n", $10 >> base".componentized.tmp"; \
			printf "%s %s %s %s %8s %s %s %s %22s %s\n", $2, $3, $4, $5, $6, $7, $8, $9, $10, $1 >> base".componentized"; \
		} \
		else \
			printf "%s %s %s %s %8s %s %s %s %s\n", $2, $3, $4, $5, $6, $7, $8, $9, $1 >> base".not-componentized"; \
	}'
else
	join -a1 -1 1 -2 $fcol $tcFileList.sorted $cmFileList.sorted | awk -v base=$tcFileListBN \
	'{ \
		printf "%22s %s\n", $2, $1 >> base".fcd"; \
		if ($2 != "") \
		{ \
			printf "%s\n", $2 >> base".componentized.tmp"; \
			printf "%22s %s\n", $2, $1 >> base".componentized"; \
		} \
		else \
			printf "%s\n", $1 >> base".not-componentized"; \
	}'
fi

if [ $tcCol -eq 9 ]; then
	sort -rnk5 $tcFileListBN.componentized -o $tcFileListBN.componentized.sorted-by-size
fi
sort -k$tcCol $tcFileListBN.componentized -o $tcFileListBN.componentized.sorted-by-components

rm -rf $tcFileListBN.componentized.componentization; mkdir $tcFileListBN.componentized.componentization
[ "$compAll" == "y" ] && ln -sf "../$tcFileListBN.not-componentized" $tcFileListBN.componentized.componentization/$tcFileListBN.componentized.not-componentized
if [ $tcCol -eq 9 ]; then
	awk -v base=$tcFileListBN.componentized.componentization/$tcFileListBN.componentized \
		-F "[ ]+" '{ printf "%s %s %s %s %8s %s %s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $10 >> base"."$9 }' $tcFileListBN.componentized.sorted-by-components
	cat /dev/null > $tcFileListBN.componentized.components
	for filename in $tcFileListBN.componentized.componentization/*; do
		prefix=$tcFileListBN.componentized.componentization/$tcFileListBN.componentized
		awk -v component=${filename#$prefix.} '{total += $5} END { printf "%3s\t%8s\t%s\n", NR, total, component}' ${filename} >> $tcFileListBN.componentized.components
	done
	sort -rnk2 $tcFileListBN.componentized.components -o $tcFileListBN.componentized.components.rnk2
else
	sed 's/^ *//' $tcFileListBN.componentized.sorted-by-components | awk -v base=$tcFileListBN.componentized.componentization/$tcFileListBN.componentized \
		-F "[ ]+" '{ printf "%s\n", $2 >> base"."$1 }'
	cat /dev/null > $tcFileListBN.componentized.components
	for filename in $tcFileListBN.componentized.componentization/*; do
		prefix=$tcFileListBN.componentized.componentization/$tcFileListBN.componentized
		awk -v component=${filename#$prefix.} 'END { printf "%3s\t%s\n", NR, component}' ${filename} >> $tcFileListBN.componentized.components
	done
fi

if [ "$macroCompMap" != "" ]; then
	cat /dev/null > $tcFileListBN.macro-componentized
	cat /dev/null > $tcFileListBN.not-macro-componentized
	sort -k2 $macroCompMap -o $macroCompMap.k2
	sort -u $tcFileListBN.componentized.tmp -o $tcFileListBN.componentized.tmp
	join -a1 -1 1 -2 2 $tcFileListBN.componentized.tmp $macroCompMap.k2 | awk -v base=$tcFileListBN \
	'{ \
		if ($2 != "") \
			printf "%s\t%s\n", $1, $2 >> base".macro-componentized"; \
		else \
			printf "%s\n", $1 >> base".not-macro-componentized"; \
	}'

	rm -rf $tcFileListBN.componentized.macro-componentization; mkdir $tcFileListBN.componentized.macro-componentization
	while IFS=$'\t' read -r comp mcomp; do
		cat $tcFileListBN.componentized.componentization/$tcFileListBN.componentized.$comp >> $tcFileListBN.componentized.macro-componentization/$tcFileListBN.macro-componentized.$mcomp
	done < $tcFileListBN.macro-componentized

	# Cleanup
	rm $macroCompMap.k2
fi

echo "$name : File-Component Distribution = $tcFileListBN.fcd" | tee -a $name.log
echo "$(filelistMetrics $tcFileList "$name : File List to componentize  " $tcCol $name.log)"
echo "$(filelistMetrics $tcFileListBN.componentized "$name : Componentized File List    " $tcCol $name.log)"
echo "$(filelistMetrics $tcFileListBN.not-componentized "$name : Not componentized File List" $tcCol $name.log)"

if [ $validate == "y" ]; then
	if [ $tcCol -eq 9 ]; then
		cat $tcFileList.sorted | tr -s ' ' > $tcFileList.sorted.tmp
		[ -s $tcFileListBN.componentized ] && cat $tcFileListBN.componentized | tr -s ' ' | cut -d ' ' -f1-8,10 > $tcFileListBN.componentized.tmp || cat /dev/null > $tcFileListBN.componentized.tmp
		[ -s $tcFileListBN.not-componentized ] && cat $tcFileListBN.not-componentized | tr -s ' ' > $tcFileListBN.not-componentized.tmp || cat /dev/null > $tcFileListBN.not-componentized.tmp
	else
		cp $tcFileList.sorted $tcFileList.sorted.tmp
		[ -s $tcFileListBN.componentized ] && sed 's/^ *//' $tcFileListBN.componentized | cut -d ' ' -f2 > $tcFileListBN.componentized.tmp || cat /dev/null > $tcFileListBN.componentized.tmp
		[ -s $tcFileListBN.not-componentized ] && cp $tcFileListBN.not-componentized $tcFileListBN.not-componentized.tmp || cat /dev/null > $tcFileListBN.not-componentized.tmp
	fi
	echo "$name : validation                  : $(flcomplval $tcFileList.sorted.tmp $tcFileListBN.componentized.tmp $tcFileListBN.not-componentized.tmp $tcCol)" | tee -a $name.log
	
	# Clean up
	rm $tcFileList.sorted.tmp $tcFileListBN.not-componentized.tmp
fi

if [ "$macroCompMap" != "" ]; then
	printf "%s : Macro-Component Map File    : %s\n" $name $macroCompMap | tee -a $name.log
	printf "%s : Componentized File List     : %5d components : %s\n" $name $(cat $tcFileListBN.componentized | tr -s ' ' | cut -d ' ' -f9 | sort -u | wc -l) $tcFileListBN.componentized | tee -a $name.log
	printf "%s : Macro-Componentized         : %5d components : %s\n" $name $(wc -l $tcFileListBN.macro-componentized | cut -d ' ' -f1) $tcFileListBN.macro-componentized | tee -a $name.log
	printf "%s : Not Macro-Componentized     : %5d components : %s\n" $name $(wc -l $tcFileListBN.not-macro-componentized | cut -d ' ' -f1) $tcFileListBN.not-macro-componentized | tee -a $name.log
fi

# Clean up
rm $tcFileListBN.componentized.tmp
rm $tcFileList.sorted $cmFileList.sorted
[ ! -s $tcFileListBN.componentized ] && rm $tcFileListBN.componentized $tcFileListBN.componentized.sorted-by-components
[ $tcCol -eq 9 ] && [ ! -s $tcFileListBN.componentized.sorted-by-size ] && rm $tcFileListBN.componentized.sorted-by-size

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : Exec time : %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

