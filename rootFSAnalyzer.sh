#!/bin/bash
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
# $0 : rootFSAnalyzer.sh is a Linux Host based script to analyze content of the root FS.
# $1 : param1 is rootfs [ramdisk] folder to be analyzed
# $2 : param2 is an optional used file list to identify referenced unused files from the used ones. 

# Run rootFSAnalyzer.sh. Ex.: ./rootFSAnalyzer.sh <path to rootFS/ramdisk> [<an optional used file list>]
# The output files: 

# Variables:
DUP_FILE_EXT_EXCLUDED="\.svn\|\.svn-base\|\.pc\|\.la"
SIM_FILE_EXT_EXCLUDED="\.svn\|\.svn-base\|\.class"
REFED_FILES_SUPPORTED="ASCII\| script\|HTML document\|SGML document\|UTF-8 Unicode"
EXE_FILE_PATTERN="executable"
EXE_FILE_PATTERN_SUP="ELF 32-bit LSB executable"
SO_FILE_PATTERN="shared object"
SO_FILE_PATTERN_SUP="ELF 32-bit LSB executable"

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-r folder [-u file] [-o {a|d}{m}{c}{r}]] | [-h]"
	echo "$name# Target RootFS analysis to build file map and identify file artifacts"
	echo "$name# -r    : a rootFS folder"
	echo "$name# -u    : an optional used file list, must not be empty!"
	echo "$name# -o    : optional settings list : { output control : a - all | d - default/minimal }, m - file map, c - common file analysis, r - refed file analysis [requires used file list]"
	echo "$name# -h    : display this help and exit"
}

# Function: sl2fi - symlink to file conversion split
# $1: input symlink list file in short format
# $2: input "symlink to file" map pattern file
# $3: output file list file in short format
# $4: output symlink list file in short format corresponding to $3
function sl2fi()
{
	cat /dev/null | tee $3 $4 >/dev/null
	sed -e "$SPEC_CHAR_PATTERN" $1 | while read -r
	do
		grep "$REPLY \-> .*0\$" $2 | tee >(cut -d ' ' -f3 >> $3) >(cut -d ' ' -f1 >> $4) >/dev/null
	done
	sort -u $3 -o $3
	sort -u $4 -o $4
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/rootFSCommon.sh

rfsFolder=
usedFiles=
ignoredFiles=
options=
fileMap="n"
outputCtr="default/minimal"
refedLevel=
findType="-type f"
symlink=

while [ "$1" != "" ]; do
	case $1 in
		-r | --root )   shift
				rfsFolder=$1
				;;
		-u | --used )   shift
				usedFiles=$1
				;;
		-o | --opts )   shift
				options=$1
				[ "${options#*m}" != "$options" ] && fileMap="y"
				[ "${options#*c}" != "$options" ] && commonFileAnalysis="y"
				[ "${options#*a}" != "$options" ] && outputCtr="all"
				[ "${options#*l}" != "$options" ] && symlink="y"
				if [ "${options#*r1}" != "$options" ]; then
					refedFileAnalysis="y"; refedLevel="r1"
				fi
				if [ "${options#*r2}" != "$options" ]; then 
					refedFileAnalysis="y"; refedLevel="r2"
				fi
				if [ "${options#*r3}" != "$options" ]; then 
					refedFileAnalysis="y"; refedLevel="r3"
				fi
				;;
		-i | --used )   shift
				ignoredFiles=$1
				;;
		-h | --help )   usage
				exit
				;;
		* )             usage
				exit 1
    esac
    shift
done

if [ "$rfsFolder" == "" ]; then
	echo "$name# Error   : rootFS folder is not set!"
	usage
	exit
fi

if [ ! -d "$rfsFolder" ]; then
	echo "$name# Error   : $rfsFolder is not a folder!"
	usage
	exit
fi

if [ "$usedFiles" != "" ] && [ ! -s "$usedFiles" ]; then
        echo "$name# Error   : $usedFiles is an empty file or the file doesn't exist!"
        usage
        exit
fi

if [ "$refedFileAnalysis" == "y" ]; then
	if [ "$usedFiles" == "" ] || [ ! -s "$usedFiles" ] && [ "$refedLevel" != "r3" ]; then
		refedFileAnalysis="n"
		echo "$name# WARNING: a used file list is not set: referenced file analysis will not be conducted!"
	fi
fi

if [ "$ignoredFiles" != "" ] && [ ! -s "$ignoredFiles" ]; then
	echo "$name# WARNING: an ignored file list $ignoredFiles is empty or doesn't exist! It won't affect results!"
fi

if [ ! -e "$rfsFolder/version.txt" ]; then
        echo "$name# WARNING: $rfsFolder/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name"
        rootFS=`basename $rfsFolder`
else
        rootFS=`cat $rfsFolder/version.txt | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
fi

[ "$symlink" == "y" ] && findType="$findType -o -type l"

echo "$cmdline" > $rootFS.files.log
echo "$name: rootFS = $rootFS : options = $options" | tee -a $rootFS.files.log

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

# create listing of target rootFS on the host
echo "RootFS file list construction:"
find $rfsFolder \( $findType \) -exec ls -la {} \;  | tr -s ' ' > $rootFS.files.ls.host

test -e $rootFS.files.all && rm $rootFS.files.all
sub=$rfsFolder
sub=${sub%/}
cat $rootFS.files.ls.host | while read line
do
	echo ${line/$sub/} >> $rootFS.files.all
done

if [ "$fileMap" == "y" ] || [ "$refedFileAnalysis" == "y" ]; then
	#find $rfsFolder -type f -exec file -b {} \; | awk 'BEGIN{FS=OFS=","} { if (match($0, "ELF")) { print $1, $NF; } else if (match($0, "ASCII")) { if (match($1, "ASCII")) print $1; else { print $1 " ASCII"; } } else { print $1; } }' > $rootFS.files.file
	#find $rfsFolder \( -type f -o -type l \) -exec file -b {} \; | awk 'BEGIN{FS=OFS=","} { if (match($0, "ELF")) { print $1, $NF; } else { print $1; } }' > $rootFS.files.file
	#find $rfsFolder \( $findType \) -exec file -b {} \; | awk 'BEGIN{FS=OFS=","} { if (match($0, "ELF")) { print $1, $2, $NF; } else { print $1; } }' > $rootFS.files.file
	find $rfsFolder \( $findType \) -exec file {} \; | awk -F',|: ' 'BEGIN{OFS=","} { if (match($0, "ELF")) {extType=""; cmd="readelf -S "$1" | grep -E '\'' .debug_| .pdr| .comment| .symtab| .strtab'\'' | tr -s '\'' '\'' | cut -d '\'' '\'' -f3 | sed '\''s/.debug_.*/.dbg/g'\'' | sort | uniq | tr -d '\''\n'\''"; cmd | getline extType; close(cmd); if (extType=="") { print $2, $3, $NF; } else { print $2, $3, $NF, extType; } } else { print $2; } }' > $rootFS.files.file
	if [ "$(wc -l $rootFS.files.all | cut -d ' ' -f1)" != "$(wc -l $rootFS.files.file | cut -d ' ' -f1)" ]; then
		echo "$name# Error   : Sizes of $rootFS.files.all and $rootFS.files.file don't match!"
		exit
	fi
	paste -d';' $rootFS.files.all $rootFS.files.file > $rootFS.files.lsfile
fi

# File map construction
maxExt=55
if [ "$fileMap" == "y" ]; then
	echo "RootFS file map:"
	cat $rootFS.files.lsfile | cut -d ';' -f2- | sort -u -k1 > $rootFS.files.descr

	test -e $rootFS.rootFS && rm -rf $rootFS.rootFS
	mkdir -p $rootFS.rootFS/size/bnsize
	maxExt=$(wc -L $rootFS.files.descr | cut -d ' ' -f1)
	cat $rootFS.files.descr | while read line
	do
		ext=`echo "$line" | tr '[ /,]' '_' | tr -s '_'`
		cat $rootFS.files.lsfile | grep ";$line" | cut -d ';' -f1 | sort -k9 > $rootFS.rootFS/$rootFS.$ext

		cat $rootFS.rootFS/$rootFS.$ext | awk -v mL=$maxExt -v extens="$line" '{total += $5} END { printf "%*s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL, extens, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
		cat $rootFS.rootFS/$rootFS.$ext | awk '{ printf "%s %2d %s %s %8d %s %2d %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }' > $rootFS.rootFS/$rootFS.$ext.formatted
		cat $rootFS.rootFS/$rootFS.$ext | cut -d ' ' -f5,9 | awk '{ printf "%8d %s\n", $1, $2 }' > $rootFS.rootFS/size/$rootFS.$ext
		cat $rootFS.rootFS/$rootFS.$ext | cut -d ' ' -f5 > $rootFS.rootFS/size/bnsize/$rootFS.$ext.size
		cat $rootFS.rootFS/$rootFS.$ext | cut -d ' ' -f9 | rev | cut -d "/" -f1 | rev > $rootFS.rootFS/size/bnsize/$rootFS.$ext.bn
		paste -d ' '  $rootFS.rootFS/size/bnsize/$rootFS.$ext.size $rootFS.rootFS/size/bnsize/$rootFS.$ext.bn | sort -k2 | awk '{ printf "%8d %s\n", $1, $2 }' > $rootFS.rootFS/size/bnsize/$rootFS.$ext

		mv  $rootFS.rootFS/$rootFS.$ext.formatted $rootFS.rootFS/$rootFS.$ext
		rm $rootFS.rootFS/size/bnsize/$rootFS.$ext.size $rootFS.rootFS/size/bnsize/$rootFS.$ext.bn
	done
	
	test -e $rootFS.files.descr && rm $rootFS.files.descr
fi
cat $rootFS.files.all | cut -d ' ' -f5 | awk -v mL=$maxExt 'BEGIN {str="Total"} {total += $1} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
phase1EndTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

if [ "$commonFileAnalysis" == "y" ]; then
	echo "Common duplicate/similar file analysis:" | tee -a $rootFS.files.log
	phase2StartTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

	# Duplicate file analysis
	cat $rootFS.files.all | grep -v "$DUP_FILE_EXT_EXCLUDED" | sort -nk5 > $rootFS.files.dups.all.supported
	cat $rootFS.files.dups.all.supported | tr -s ' ' | cut -d ' ' -f5 | sort -n | uniq -d > $rootFS.files.dups.all.lpattern
	test -e $rootFS.files.dups.all.eql.files && rm $rootFS.files.dups.all.eql.files
	cat $rootFS.files.dups.all.lpattern | while read line
	do
		awk -v len=$line 'BEGIN {FS=" "} { if ($5 == len) { print $0; } }' $rootFS.files.dups.all.supported >> $rootFS.files.dups.all.eql.files
	done

	test -e $rootFS.files.dups.all.eql.md5sum && rm $rootFS.files.dups.all.eql.md5sum
	cat $rootFS.files.dups.all.eql.files | while read line
	do
		line=${line#*/}
		md5sum "$sub/$line" | cut -d ' ' -f1 >> $rootFS.files.dups.all.eql.md5sum
	done
	paste -d ' ' $rootFS.files.dups.all.eql.files $rootFS.files.dups.all.eql.md5sum > $rootFS.files.dups.all.eql.files.md5sum
	sort $rootFS.files.dups.all.eql.md5sum | uniq -d > $rootFS.files.dups.all.eql.md5sum.dups

	test -e $rootFS.files.dups.all && rm $rootFS.files.dups.all
	cat $rootFS.files.dups.all.eql.md5sum.dups | while read line
	do
		awk -v dups=$line '$0 ~ dups { printf "%s %2d %s %s %8d %s %2d %s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $10, $9}' $rootFS.files.dups.all.eql.files.md5sum >> $rootFS.files.dups.all
	done

	if [ -s $rootFS.files.dups.all ] || [ "$outputCtr" == "all" ]; then
		cat $rootFS.files.dups.all | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Duplicate all"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log

		cat $rootFS.files.dups.all | tr -s ' ' | cut -d ' ' -f5 | grep \^0 | uniq -c | tr -s ' ' | cut -d ' ' -f2 > $rootFS.files.dups.empty.count
		if [ -s $rootFS.files.dups.empty.count ] || [ "$outputCtr" == "all" ]; then
			md5sum /dev/null | cut -d ' ' -f1 > $rootFS.files.empty.md5sum.0

			grep -w    -f $rootFS.files.empty.md5sum.0 $rootFS.files.dups.all > $rootFS.files.dups.empty
			grep -w -v -f $rootFS.files.empty.md5sum.0 $rootFS.files.dups.all > $rootFS.files.dups.not-empty
			if [ -s $rootFS.files.dups.empty ] || [ "$outputCtr" == "all" ]; then
				cat $rootFS.files.dups.empty | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Duplicate empty"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
			else
				rm  $rootFS.files.dups.empty
			fi

			if [ -s $rootFS.files.dups.not-empty ] || [ "$outputCtr" == "all" ]; then
				cat $rootFS.files.dups.not-empty | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Duplicate not-empty"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
			else
				rm  $rootFS.files.dups.not-empty
			fi
		fi
	fi

	# Similar file analysis
	cat $rootFS.files.all | grep -v "$SIM_FILE_EXT_EXCLUDED" | tr -s ' ' | cut -d ' ' -f9 | rev | cut -d "/" -f1 | rev | cut -d '.' -f1,2 | sort | uniq -d  | sed 's/\./\\./g' > $rootFS.files.sim.pattern
	# find all similar files
	grep -w -f $rootFS.files.sim.pattern $rootFS.files.all | grep -v "$SIM_FILE_EXT_EXCLUDED" > $rootFS.files.sim
	cat $rootFS.files.sim | awk '{ printf "%s %2d %s %s %8d %s %2d %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9}' > $rootFS.files.similar.all
	cat $rootFS.files.sim | cut -d ' ' -f9- | sort > $rootFS.files.sim.short
	cp $rootFS.files.similar.all $rootFS.files.similar

	#cat $rootFS.files.sim.pattern | while read line
	#do
	#	grep "$line" $rootFS.files.all | awk '{ printf "%s %2d %s %s %8d %s %2d %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9}' >> $rootFS.files.similar.all
	#	awk "/$line/"'{ printf "%s %2d %s %s %8d %s %2d %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9}' $rootFS.files.all >> $rootFS.files.similar.all
	#	awk -v sims=$line '$0 ~ sims { printf "%s %2d %s %s %8d %s %2d %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9}' $rootFS.files.all >> $rootFS.files.similar.all
	#done

	# find all similar duplicate files
	grep -w -f $rootFS.files.sim.pattern $rootFS.files.dups.all > $rootFS.files.similar.dups
	cat $rootFS.files.similar.dups | tr -s ' ' | cut -d ' ' -f10 | sort > $rootFS.files.sim.dups.short
	# find all similar unique files
	#comm -13 $rootFS.files.sim.dups.short $rootFS.files.sim.short > $rootFS.files.sim.uniq.short
	#grep -w -f $rootFS.files.sim.uniq.short $rootFS.files.sim > $rootFS.files.sim.uniq

	cat $rootFS.files.sim | cut -d ' ' -f5 | grep \^0 | uniq -c | tr -s ' ' | cut -d ' ' -f2 > $rootFS.files.sim.empty.count

	if [ -s $rootFS.files.similar.all ] || [ "$outputCtr" == "all" ]; then
		cat $rootFS.files.similar.all | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Similar all"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	fi

	if [ -s $rootFS.files.similar.dups ] || [ "$outputCtr" == "all" ]; then
		if [ -s $rootFS.files.sim.empty.count ]; then
			grep -w    -f $rootFS.files.empty.md5sum.0 $rootFS.files.similar.dups > $rootFS.files.similar.dups.empty
			grep -w -v -f $rootFS.files.empty.md5sum.0 $rootFS.files.similar.dups > $rootFS.files.similar.dups.not-empty
			if [ -s $rootFS.files.similar.dups.empty ] || [ "$outputCtr" == "all" ]; then
				cat $rootFS.files.similar.dups.empty | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Similar dupl empty"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
			else
				rm $rootFS.files.similar.dups.empty
			fi
			if [ -s $rootFS.files.similar.dups.not-empty ] || [ "$outputCtr" == "all" ]; then
				cat $rootFS.files.similar.dups.not-empty | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Similar dupl not-empty"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
			fi
		else
			test -e $rootFS.files.similar.dups.not-empty && rm $rootFS.files.similar.dups.not-empty
			ln -s $rootFS.files.similar.dups $rootFS.files.similar.dups.not-empty
		fi

		cat $rootFS.files.similar.dups.not-empty | grep    "\.so" > $rootFS.files.similar.dups.not-empty-so
		cat $rootFS.files.similar.dups.not-empty | grep -v "\.so" > $rootFS.files.similar.dups.not-empty-other
		if [ -s $rootFS.files.similar.dups.not-empty-so ] || [ "$outputCtr" == "all" ]; then
			cat $rootFS.files.similar.dups.not-empty-so | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Similar dupl not-empty .so"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
		else
			rm $rootFS.files.similar.dups.not-empty-so
		fi
		if [ -s $rootFS.files.similar.dups.not-empty-other ] || [ "$outputCtr" == "all" ]; then
			cat $rootFS.files.similar.dups.not-empty-other | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Similar dupl not-empty other"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
		else
			rm $rootFS.files.similar.dups.not-empty-other
		fi

		# remove all dups from the similar files
		cat $rootFS.files.similar.dups | tr -s ' ' | cut -d ' ' -f10 > $rootFS.files.sim.dups.short
		grep -w -v -f $rootFS.files.sim.dups.short $rootFS.files.similar > $rootFS.files.similar.tmp
		mv $rootFS.files.similar.tmp $rootFS.files.similar
	fi

	# check for similar .so files
	if [ -s $rootFS.files.similar ] || [ "$outputCtr" == "all" ]; then
		grep "\.so" $rootFS.files.similar | tr -s ' ' | cut -d ' ' -f9 | rev | cut -d "/" -f1 | rev | cut -d '.' -f1,2 | sort | uniq -d > $rootFS.files.similar.so.names
	
		if [ -s $rootFS.files.similar.so.names ] || [ "$outputCtr" == "all" ]; then
			grep -w -f $rootFS.files.similar.so.names $rootFS.files.similar > $rootFS.files.similar.so

			if [ -s $rootFS.files.similar.so ] || [ "$outputCtr" == "all" ]; then
				cat $rootFS.files.similar.so | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Similar .so"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log

				# remove all .so from the similar files
				fllo2sh $rootFS.files.similar.so $rootFS.files.similar.so.short
				grep -w -v -f $rootFS.files.similar.so.short $rootFS.files.similar > $rootFS.files.similar.tmp
				mv $rootFS.files.similar.tmp $rootFS.files.similar
				rm $rootFS.files.similar.so.short
			else
				rm $rootFS.files.similar.so
			fi
		fi
		rm $rootFS.files.similar.so.names
	fi

	if [ -s $rootFS.files.similar ] || [ "$outputCtr" == "all" ]; then
		cat $rootFS.files.similar | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Similar other"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
		mv $rootFS.files.similar $rootFS.files.similar.other
	else
		rm $rootFS.files.similar
	fi

	# check for .svn files
	grep "\.svn\|\.svn-base" $rootFS.files.all > $rootFS.files.svn
	if [ -s $rootFS.files.svn ] || [ "$outputCtr" == "all" ]; then
		cat $rootFS.files.svn | tr -s ' ' | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str=".svn"} {total += $5} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	else
		rm $rootFS.files.svn
	fi

	rm $rootFS.files.dups.all.* $rootFS.files.dups.empty.count
	rm  $rootFS.files.sim $rootFS.files.sim.*
	test -e $rootFS.files.empty.md5sum.0 && rm $rootFS.files.empty.md5sum.0
	
	phase2EndTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
fi

sort -k9 $rootFS.files.all -o $rootFS.files.all

# Unused referenced file analysis - unused files referenced from the used ones. Optional.
if [ "$refedFileAnalysis" == "y" ] && [ "$usedFiles" != "" ] && [ -s "$usedFiles" ] && [ "$refedLevel" != "r3" ]; then
	echo "Referenced unused ascii/unicode file analysis:" | tee -a $rootFS.files.log
	phase3StartTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

	# check input file formats if unused file analysis requested
	nf2=$(fileFormat $usedFiles)
	if [ "$nf2" -ne 1 ]; then
		cat $usedFiles | tr -s ' ' | cut -d ' ' -f${nf2}- | sort -o $usedFiles.short
	else
		sort $usedFiles -o $usedFiles.short
	fi

	if [ -s "$ignoredFiles" ]; then
		nfi=$(fileFormat $ignoredFiles)
		[ ! "$nfi" -eq 1 ] && cat $ignoredFiles | tr -s ' ' | cut -d ' ' -f$nfi- | sort -o $ignoredFiles.short || sort $ignoredFiles -o $ignoredFiles.short
	fi

	# find all "unused" files
	fllo2sh $rootFS.files.all $rootFS.files.all.short
	[ "$symlink" == "y" ] && sort $rootFS.files.all.short -o $rootFS.files.all.short
	comm -23 $rootFS.files.all.short $usedFiles.short > $rootFS.files.unused.short

	# find all "unused" supported files
	grep -v "$SIM_FILE_EXT_EXCLUDED" $rootFS.files.unused.short > $rootFS.files.unused.supported.all.short
	if [ "$symlink" == "y" ]; then
		grep "\->" $rootFS.files.unused.supported.all.short > $rootFS.files.unused.supported.symlinks
		cat $rootFS.files.unused.supported.symlinks | tr -s ' ' | cut -d ' ' -f1 | sort -o $rootFS.files.unused.supported.symlinks.short
		cat $rootFS.files.unused.supported.symlinks | tr -s ' ' | cut -d ' ' -f3 | sort -u -o $rootFS.files.unused.supported.symlinks.files.short
		comm -23 $rootFS.files.unused.supported.all.short $rootFS.files.unused.supported.symlinks > $rootFS.files.unused.supported.short
		
		if [ -s $rootFS.files.unused.supported.symlinks.short ]; then
			cat /dev/null > $rootFS.files.unused.supported.sl2fimap.short
			while read refedEntry
			do
				usedFileH=$(readlink -e ${sub}${refedEntry})
				if [ "$usedFileH" != "" ]; then
					usedFile=${usedFileH/$sub/}
					[ "$(grep "$usedFile" $usedFiles.short)" != "" ] && usedStat="1" || usedStat="0"
					echo "$refedEntry -> $usedFile $usedStat" >> $rootFS.files.unused.supported.sl2fimap.short
				else
					echo "$refedEntry : $(file ${sub}${refedEntry} | cut -d ':' -f2)" >> $rootFS.files.unused.supported.sl2fimap.short
				fi
			done < $rootFS.files.unused.supported.symlinks.short
		fi

		[ "$refedLevel" == "r2" ] && flsh2bn $rootFS.files.unused.supported.symlinks.short $rootFS.files.unused.supported.symlinks.basename
	else
		grep -v "\->" $rootFS.files.unused.supported.all.short > $rootFS.files.unused.supported.short
	fi

	[ "$refedLevel" == "r2" ] && flsh2bn $rootFS.files.unused.supported.all.short $rootFS.files.unused.supported.all.basename

	# find all ascii/unicode files
	cat $rootFS.files.lsfile | grep "$REFED_FILES_SUPPORTED" | cut -d ';' -f1 > $rootFS.files.ascii

	iter=0
	[ -e $rootFS.files.ascii.refed.short  ] && rm $rootFS.files.ascii.refed.short
	[ -e $rootFS.files.ascii.used.refed.log ] && rm $rootFS.files.ascii.used.refed.log
	[ -e $rootFS.files.ascii.used.refed.basename.all ] && rm $rootFS.files.ascii.used.refed.basename.all
	ln -sf $usedFiles.short $rootFS.files.ascii.used.link
	while [ -s $rootFS.files.ascii.used.link ]; do
		echo "iter = $iter" >> $rootFS.files.ascii.used.refed.log
		# find all ascii/unicode "used"/"refed" files
		flsh2lo $rootFS.files.ascii.used.link $rootFS.files.ascii $rootFS.files.ascii.used
		grep -v "\.txt" $rootFS.files.ascii.used | cut -d ' ' -f9- | sort -u -o $rootFS.files.ascii.used.short

		[ "$refedLevel" == "r2" ] && cat /dev/null > $rootFS.files.ascii.used.refed.$iter.basename

		# create a file with referenced symbols from an ascii/unicode "used"/"refed" file
		cat /dev/null > $rootFS.files.ascii.refed.$iter.short
		if [ -e $rootFS.files.ascii.used.all.short ]; then
			# remove "refed" files processed during all previous iterations
			comm -23 $rootFS.files.ascii.used.short $rootFS.files.ascii.used.all.short > $rootFS.files.ascii.used.tmp.short
			mv $rootFS.files.ascii.used.tmp.short $rootFS.files.ascii.used.short

			cat $rootFS.files.ascii.used.short >> $rootFS.files.ascii.used.all.short
			sort -u $rootFS.files.ascii.used.all.short -o $rootFS.files.ascii.used.all.short
		else
			cat $rootFS.files.ascii.used.short > $rootFS.files.ascii.used.all.short
		fi
		cp $rootFS.files.ascii.used.short $rootFS.files.ascii.used.$iter.short

		cat /dev/null > $rootFS.files.ascii.used.refed.symlinks.$iter.short

		cat $rootFS.files.ascii.used.short | while read usedFile
		do
			cat ${sub}${usedFile} | awk -F '#|//' '{ print $1 }' | tr ' :=\t' '\n' | tr -d '",;' | sort -u -o $rootFS.files.ascii.used.symbols

			if [ "$outputCtr" == "all" ]; then
				# Log all symbols from a used/refed file
				mkdir -p $rootFS.refed/$usedFile
				cp $rootFS.files.ascii.used.symbols $rootFS.refed/$usedFile/$rootFS.files.ascii.used.symbols.all
			fi

			# find file matches in short format
			comm -12 $rootFS.files.unused.supported.short $rootFS.files.ascii.used.symbols > $rootFS.files.ascii.used.refed.short
			if [ "$symlink" == "y" ]; then
				# find all symlink matches in short format
				comm -12 $rootFS.files.unused.supported.symlinks.short $rootFS.files.ascii.used.symbols > $rootFS.files.ascii.used.refed.symlinks.short
				
				sl2fi $rootFS.files.ascii.used.refed.symlinks.short $rootFS.files.unused.supported.sl2fimap.short \
				$rootFS.files.ascii.used.refed.unused.files.short $rootFS.files.ascii.used.refed.unused.symlinks.short
				cat $rootFS.files.ascii.used.refed.unused.files.short >> $rootFS.files.ascii.used.refed.short
				sort -u $rootFS.files.ascii.used.refed.short -o $rootFS.files.ascii.used.refed.short
				
				# remove full path symlinks from referenced files, they're processed separately
				comm -13 $rootFS.files.ascii.used.refed.symlinks.short $rootFS.files.ascii.used.refed.short > $rootFS.files.ascii.used.refed.tmp.files.short
				mv $rootFS.files.ascii.used.refed.tmp.files.short $rootFS.files.ascii.used.refed.short
				
				# remove converted symlinks from $rootFS.files.ascii.used.refed.symlinks.short
				mv $rootFS.files.ascii.used.refed.unused.symlinks.short $rootFS.files.ascii.used.refed.symlinks.short
			fi

			if [ "$refedLevel" == "r2" ]; then
				# remove all used files from the $rootFS.files.ascii.used.symbols
				comm -13 $usedFiles.short $rootFS.files.ascii.used.symbols > $rootFS.files.ascii.used.symbols.tmp

				# remove full path unused references from the $rootFS.files.ascii.used.symbols
				comm -23 $rootFS.files.ascii.used.symbols.tmp $rootFS.files.ascii.used.refed.short > $rootFS.files.ascii.used.symbols

				flsh2bn $rootFS.files.ascii.used.symbols $rootFS.files.ascii.used.symbols.basename
				comm -12 $rootFS.files.unused.supported.all.basename $rootFS.files.ascii.used.symbols.basename > $rootFS.files.ascii.used.refed.basename
				
				if [ "$symlink" == "y" ]; then
					# remove symlink basenames from $rootFS.files.ascii.used.refed.basename
					comm -13 $rootFS.files.unused.supported.symlinks.basename $rootFS.files.ascii.used.refed.basename >> $rootFS.files.ascii.used.refed.short

					# process symlink basenames in $rootFS.files.ascii.used.refed.basename
					comm -12 $rootFS.files.unused.supported.symlinks.basename $rootFS.files.ascii.used.refed.basename > $rootFS.files.ascii.used.refed.basename.tmp
					slbn2sh $rootFS.files.ascii.used.refed.basename.tmp $rootFS.files.unused.supported.sl2fimap.short $rootFS.files.ascii.used.refed.bn2sh.short
					sort -u $rootFS.files.ascii.used.refed.bn2sh.short -o $rootFS.files.ascii.used.refed.bn2sh.short
					mv $rootFS.files.ascii.used.refed.basename.tmp $rootFS.files.ascii.used.refed.basename

					# remove all used files
					comm -13 $usedFiles.short $rootFS.files.ascii.used.refed.bn2sh.short >> $rootFS.files.ascii.used.refed.short
				else
					cat $rootFS.files.ascii.used.refed.basename >> $rootFS.files.ascii.used.refed.short
				fi

				sort -u $rootFS.files.ascii.used.refed.short -o $rootFS.files.ascii.used.refed.short
				comm -13 $usedFiles.short $rootFS.files.ascii.used.refed.short > $rootFS.files.ascii.used.refed.tmp.files.short
				mv $rootFS.files.ascii.used.refed.tmp.files.short $rootFS.files.ascii.used.refed.short

				[ "$outputCtr" == "all" ] && cp $rootFS.files.ascii.used.refed.short $rootFS.refed/$usedFile/$rootFS.files.ascii.used.symbols.refed
			fi

			if [ -s "$ignoredFiles" ]; then
				comm -13 $ignoredFiles.short $rootFS.files.ascii.used.refed.short > $rootFS.files.ascii.used.refed.tmp.files.short
				mv $rootFS.files.ascii.used.refed.tmp.files.short $rootFS.files.ascii.used.refed.short
			fi

			if [ -s $rootFS.files.ascii.used.refed.short ]; then
				# build a list of an i-th iteration's "refed" files
				cat $rootFS.files.ascii.used.refed.short >> $rootFS.files.ascii.refed.$iter.short
				# build a list of "refed" files and used/refed files they are "refed" from
				echo "$usedFile:" >> $rootFS.files.ascii.used.refed.log
				sed -e "$SPEC_CHAR_PATTERN" $rootFS.files.ascii.used.refed.short | while read -r refedEntry
				do
					echo -e "\t$refedEntry" >> $rootFS.files.ascii.used.refed.log
					if [ "$refedLevel" == "r2" ]; then
						if [ "${refedEntry:0:1}" != "/" ]; then
							grep "/$refedEntry\$" $rootFS.files.unused.supported.short | while read refed
							do
								echo -e "\t\t$refed" >> $rootFS.files.ascii.used.refed.log
							done
						fi
					fi
				done
			fi

 			if [ -s $rootFS.files.ascii.used.refed.symlinks.short ]; then
 				cat $rootFS.files.ascii.used.refed.symlinks.short >> $rootFS.files.ascii.used.refed.symlinks.$iter.short
				[ ! -s $rootFS.files.ascii.used.refed.short ] && echo "$usedFile:" >> $rootFS.files.ascii.used.refed.log
				while read refedEntry
				do
					usedFileH=$(readlink -e ${sub}${refedEntry})
					if [ "$usedFileH" != "" ]; then
						usedFile=${usedFileH/$sub/}
						echo -e "\t$refedEntry -> $usedFile" >> $rootFS.files.ascii.used.refed.log
			
						echo "$usedFile" >> $rootFS.files.ascii.refed.$iter.short
					else
						echo -e "\t$refedEntry:$(file ${sub}${refedEntry} | cut -d ':' -f2)" >> $rootFS.files.ascii.used.refed.log
					fi
				done < $rootFS.files.ascii.used.refed.symlinks.short
			fi

			[ -s $rootFS.files.ascii.used.refed.short ] || [ -s $rootFS.files.ascii.used.refed.symlinks.short ] && echo "" >> $rootFS.files.ascii.used.refed.log
			[ "$refedLevel" == "r2" ] && cat $rootFS.files.ascii.used.refed.basename >> $rootFS.files.ascii.used.refed.$iter.basename
		done
		sort -u $rootFS.files.ascii.refed.$iter.short -o $rootFS.files.ascii.refed.$iter.short
		[ "$refedLevel" == "r2" ] && sort -u $rootFS.files.ascii.used.refed.$iter.basename -o $rootFS.files.ascii.used.refed.$iter.basename
		[ "$symlink" == "y" ] && sort -u $rootFS.files.ascii.used.refed.symlinks.$iter.short -o $rootFS.files.ascii.used.refed.symlinks.$iter.short

		if [ -e $rootFS.files.ascii.refed.short ]; then
			comm -13 $rootFS.files.ascii.refed.short $rootFS.files.ascii.refed.$iter.short > $rootFS.files.ascii.refed.uniq.short

			cat $rootFS.files.ascii.refed.$iter.short >> $rootFS.files.ascii.refed.short
			sort -u $rootFS.files.ascii.refed.short -o $rootFS.files.ascii.refed.short

			ln -sf $rootFS.files.ascii.refed.uniq.short $rootFS.files.ascii.used.link
		else
			cat $rootFS.files.ascii.refed.$iter.short > $rootFS.files.ascii.refed.short
		
			ln -sf $rootFS.files.ascii.refed.$iter.short $rootFS.files.ascii.used.link
		fi
		
		iter=`expr $iter + 1`
	done
	
	# build a list of unique "refed" files from all iterations
	flsh2lo $rootFS.files.ascii.refed.short $rootFS.files.all $rootFS.files.ascii.refed

	if [ -s "$ignoredFiles" ]; then
		sed -e "$SPEC_CHAR_PATTERN" $ignoredFiles.short | grep -v -w -f - $rootFS.files.ascii.refed > $rootFS.files.ascii.refed.tmp
		mv $rootFS.files.ascii.refed.tmp $rootFS.files.ascii.refed
	fi
	sort -u -k9 $rootFS.files.ascii.refed -o $rootFS.files.ascii.refed

	cat $rootFS.files.ascii.refed | cut -d ' ' -f5 | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Refed"} {total += $1} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log

	#clean up
	rm $rootFS.files.ascii.used.link
	rm $rootFS.files.ascii.used.symbols $rootFS.files.ascii.used $rootFS.files.ascii.used.short $rootFS.files.ascii.used.*.short
	rm $rootFS.files.ascii $rootFS.files.ascii.refed.*.short $rootFS.files.unused.* $usedFiles.short $rootFS.files.all.short
	[ -e $rootFS.files.ascii.used.refed.basename ] && rm $rootFS.files.ascii.used.refed.basename
	[ -e $rootFS.files.ascii.used.symbols.basename ] && rm $rootFS.files.ascii.used.symbols.basename
	[ -e $rootFS.files.ascii.used.symbols.tmp ] && rm $rootFS.files.ascii.used.symbols.tmp
	[ -e "$ignoredFiles.short" ] && rm $ignoredFiles.short
	[ "$refedLevel" == "r1" ] && rm $rootFS.files.ascii.refed.short || mv $rootFS.files.ascii.refed.short $rootFS.files.ascii.refed.short+symbols
	[ "$refedLevel" == "r2" ] && rm $rootFS.files.ascii.used.refed.*.basename

	phase3EndTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
fi

# Referenced shared library object analysis - "needed" files referenced from the "used" elf files. Optional.
if [ "$refedFileAnalysis" == "y" ] && [ "$refedLevel" == "r3" ]; then
	echo "Referenced shared library object analysis:" | tee -a $rootFS.files.log
	phase3StartTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

	# find all executable files
	cat $rootFS.files.lsfile | grep "$EXE_FILE_PATTERN" | cut -d ';' -f1 | sort -k9 > $rootFS.files.exe.all
	fllo2sh $rootFS.files.exe.all $rootFS.files.exe.all.short

	# find all shared library object files
	cat $rootFS.files.lsfile | grep "$SO_FILE_PATTERN" | cut -d ';' -f1 | sort -k9 > $rootFS.files.so.all
	fllo2sh $rootFS.files.so.all $rootFS.files.so.all.short

	[ -e $rootFS.files.exe.used ] && rm $rootFS.files.exe.used
	[ -e $rootFS.files.so.used  ] && rm $rootFS.files.so.used
	if [ "$usedFiles" == "" ]; then
		ln -sf $rootFS.files.exe.all.short $rootFS.files.elf.analyze.short
	else
		usedFiles=$(flslfilter $usedFiles)

		# check input file formats if analysis requested
		nf2=$(fileFormat $usedFiles)
		if [ "$nf2" -ne 1 ]; then
			cat $usedFiles | tr -s ' ' | cut -d ' ' -f${nf2}- | sort -o $usedFiles.short
		else
			sort $usedFiles -o $usedFiles.short
		fi

		# find missing files within given used
		fllo2sh $rootFS.files.all $rootFS.files.all.short
		comm -23 $usedFiles.short $rootFS.files.all.short > $usedFiles.missing.short
	
		# find used executable files
		comm -12 $usedFiles.short $rootFS.files.exe.all.short > $rootFS.files.exe.used.short
		flsh2lo $rootFS.files.exe.used.short $rootFS.files.exe.all $rootFS.files.exe.used

		# find unused executable files
		comm -13 $rootFS.files.exe.used.short $rootFS.files.exe.all.short > $rootFS.files.exe.unused.short
		flsh2lo $rootFS.files.exe.unused.short $rootFS.files.exe.all $rootFS.files.exe.unused

		# find used shared object files
		comm -12 $usedFiles.short $rootFS.files.so.all.short > $rootFS.files.so.used.short
		flsh2lo $rootFS.files.so.used.short $rootFS.files.so.all $rootFS.files.so.used

		# find unused shared object files
		comm -13 $rootFS.files.so.used.short $rootFS.files.so.all.short > $rootFS.files.so.unused.short
		flsh2lo $rootFS.files.so.unused.short $rootFS.files.so.all $rootFS.files.so.unused

		if [ -s $rootFS.files.exe.used.short ] || [ ! -s $rootFS.files.so.used.short ]; then
			ln -sf $rootFS.files.exe.used.short $rootFS.files.elf.analyze.short
		else
			ln -sf $rootFS.files.so.used.short $rootFS.files.elf.analyze.short
		fi
	fi

	[ -e $rootFS.elf ] && rm -rf $rootFS.elf
	mkdir -p $rootFS.elf
	
	[ -e $rootFS.elf.log ] && rm $rootFS.elf.log
	cat $rootFS.files.elf.analyze.short | while read entryElf
	do
		elfName=$(echo $entryElf | tr '/' '%')
		echo "$entryElf:" >> $rootFS.elf.log

		# build a list of all referenced referenced/"needed" shared library objects from all/used executables
		objdump -x ${sub}${entryElf} | grep "NEEDED" | tr -s ' ' | cut -d ' ' -f3 > $rootFS.files.elf.refed.odump

		iter=0
		ln -sf $rootFS.files.elf.refed.odump $rootFS.files.so.refed.link
		while [ -s $rootFS.files.so.refed.link ]; do
			cat /dev/null > $rootFS.files.so.refed.$iter.short

			# find all references in the objdump output
			cat /dev/null > $rootFS.files.elf.odump.find
			cat $rootFS.files.elf.refed.odump | while read entry
			do
				find ${sub} -name $entry >> $rootFS.files.elf.odump.find
			done

			cat $rootFS.files.elf.odump.find | while read entry
			do
				entryHResolved=$(readlink -e $entry)
				if [ "$entryHResolved" != "" ]; then
					entryShort=${entryHResolved/$sub/}
					echo "$entryShort" >> $rootFS.files.so.refed.$iter.short
				else
					printf "%1d: unresolved link: %s\n" $iter ${entry/$sub/} >> $rootFS.elf.log
				fi
			done
			sort -u $rootFS.files.so.refed.$iter.short -o $rootFS.files.so.refed.$iter.short

			if [ "$iter" -eq 0 ]; then
				cat $rootFS.files.so.refed.$iter.short > $rootFS.elf/$elfName
				ln -sf $rootFS.files.so.refed.$iter.short $rootFS.files.so.refed.link
			else
				comm -13 $rootFS.files.so.refed.$((iter-1)).short $rootFS.files.so.refed.$iter.short > $rootFS.files.so.refed.uniq.short
				cat $rootFS.files.so.refed.uniq.short >> $rootFS.elf/$elfName
				ln -sf $rootFS.files.so.refed.uniq.short $rootFS.files.so.refed.link
			fi
		
			if [ "$outputCtr" == "all" ]; then
				cat $rootFS.files.so.refed.link | while read entry
				do
					printf "%1d: %s\n" $iter $entry >> $rootFS.elf.log
				done
			fi

			cat /dev/null > $rootFS.files.elf.refed.odump
			cat $rootFS.files.so.refed.link | while read entry
			do
				objdump -x ${sub}${entry} | grep "NEEDED" | tr -s ' ' | cut -d ' ' -f3 >> $rootFS.files.elf.refed.odump
			done
			sort -u $rootFS.files.elf.refed.odump -o $rootFS.files.elf.refed.odump

			iter=`expr $iter + 1`
		done
		[ -e $rootFS.elf/$elfName ] && sort -u $rootFS.elf/$elfName -o $rootFS.elf/$elfName
		[ "$outputCtr" == "all" ] && echo "" >> $rootFS.elf.log
	done

	# build $rootFS.files.so.refed
	if [ "$(ls -A $rootFS.elf)" != "" ]; then
		cat $rootFS.elf/* | sort -u -o $rootFS.files.so.refed.short
		[ -e $rootFS.elf.refed.log ] && rm $rootFS.elf.refed.log
		if [ -s $rootFS.files.so.refed.short ]; then
			cat $rootFS.files.so.refed.short | while read entry
			do
				grep -r "$entry" $rootFS.elf | cut -d ':' -f1 | tr '%' '/' | sort > $rootFS.files.elf.entry
				printf "%4d %s:\n" $(wc -l $rootFS.files.elf.entry | cut -d ' ' -f1) $entry >> $rootFS.elf.refed.log
				cat $rootFS.files.elf.entry | while read refed
				do
					printf "%4c \t\t%s\n" " " ${refed/"$rootFS.elf/"/} >> $rootFS.elf.refed.log
				done
			done
			rm $rootFS.files.elf.entry
		fi
	else
		cat /dev/null > $rootFS.files.so.refed.short
	fi
	flsh2lo $rootFS.files.so.refed.short $rootFS.files.so.all $rootFS.files.so.refed

	# build $rootFS.files.so.unrefed
	comm -13 $rootFS.files.so.refed.short $rootFS.files.so.all.short > $rootFS.files.so.unrefed.short
	flsh2lo $rootFS.files.so.unrefed.short $rootFS.files.so.all $rootFS.files.so.unrefed
	
	if [ -s $usedFiles.missing.short ]; then
		cat $usedFiles.missing.short | awk -v mL=$maxExt 'BEGIN {warn="Warning:"; str="Missing"} {total += $1} END { printf "%s %*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", warn, mL-length(str)-length(warn)-2, " ", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	fi

	# all/used/unused executables
	cat $rootFS.files.exe.all            | awk -v mL=$maxExt 'BEGIN {str="All executable"} {total += $5} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	if [ -s $rootFS.files.exe.used ]; then
		cat $rootFS.files.exe.used   | awk -v mL=$maxExt 'BEGIN {str="Used executable"} {total += $5} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	fi
	if [ -s $rootFS.files.exe.unused ]; then
		cat $rootFS.files.exe.unused | awk -v mL=$maxExt 'BEGIN {str="Unused executable"} {total += $5} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	fi

	# all/used/unused shared library objects
	cat $rootFS.files.so.all             | awk -v mL=$maxExt 'BEGIN {str="All shared library object"} {total += $5} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	if [ -s $rootFS.files.so.used ]; then
		cat $rootFS.files.so.used    | awk -v mL=$maxExt 'BEGIN {str="Used shared library object"} {total += $5} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	fi
	if [ -s $rootFS.files.so.unused ]; then
		cat $rootFS.files.so.unused  | awk -v mL=$maxExt 'BEGIN {str="Unused shared library object"} {total += $5} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	fi
	
	# refed/unrefed shared library objects
	if [ -s $rootFS.files.so.refed ]; then
		cat $rootFS.files.so.refed   | awk -v mL=$maxExt 'BEGIN {str="Referenced shared library object"} {total += $5} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	fi
	if [ -s $rootFS.files.so.unrefed ]; then
		cat $rootFS.files.so.unrefed | awk -v mL=$maxExt 'BEGIN {str="Unreferenced shared library object"} {total += $5} END { printf "%*c %s files: %5d : %9d Bytes / %6d KB / %3d MB\n", mL-length(str)-1, " ", str, NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.files.log
	fi

	#clean up
	rm $rootFS.files.elf.*
	rm $rootFS.files.so.refed.* 
	rm $rootFS.files.so.unrefed.*
	[ -e $rootFS.files.all.short ] && rm $rootFS.files.all.short 
	[ -e $rootFS.files.exe.all.short ] && rm $rootFS.files.exe.all.short 
	[ -e $rootFS.files.so.all.short ] && rm $rootFS.files.so.all.short
	[ -e $rootFS.files.exe.used.short ] && rm $rootFS.files.exe.used.short 
	[ -e $rootFS.files.so.used.short ] && rm $rootFS.files.so.used.short
	[ -e $rootFS.files.exe.unused.short ] && rm $rootFS.files.exe.unused.short
	[ -e $rootFS.files.so.unused.short ] && rm $rootFS.files.so.unused.short
	[ -e $usedFiles.short ] && rm $usedFiles.short
	[ -e $usedFiles.missing.short ] && [ ! -s $usedFiles.missing.short ] && rm $usedFiles.missing.short

	phase3EndTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
fi

#clean up
rm $rootFS.files.ls*
test -e $rootFS.files.file && rm $rootFS.files.file

phase1ExecTime=`expr $phase1EndTime - $startTime`
printf "$name: Phase 1 Execution time: %02dh:%02dm:%02ds\n" $((phase1ExecTime/3600)) $((phase1ExecTime%3600/60)) $((phase1ExecTime%60))

if [ "$commonFileAnalysis" == "y" ]; then
	phase2ExecTime=`expr $phase2EndTime - $phase2StartTime`
	printf "$name: Phase 2 Execution time: %02dh:%02dm:%02ds\n" $((phase2ExecTime/3600)) $((phase2ExecTime%3600/60)) $((phase2ExecTime%60))
fi

if [ "$refedFileAnalysis" == "y" ]; then
	phase3ExecTime=`expr $phase3EndTime - $phase3StartTime`
	printf "$name: Phase 3 Execution time: %02dh:%02dm:%02ds\n" $((phase3ExecTime/3600)) $((phase3ExecTime%3600/60)) $((phase3ExecTime%60))
fi

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Total   Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

