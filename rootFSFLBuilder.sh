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
#
# $0 : rootFSFLBuilder.sh is a Linux Host based script that builds a target rootFS file list based on a given rootFS folder.

# Output:
# A rootFS file list

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-r folder] | [-o] | [-h]"
	echo "$name# Target RootFS file list builder"
	echo "$name# -r    : a rootFS folder"
	echo "$name# -o    : an optional output RootFS file list to override default version.txt <imagename>.file.all output"
	echo "$name# -h    : display this help and exit"
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/rootFSCommon.sh

rfsFolder=
findType="-type f"
symlink=
while [ "$1" != "" ]; do
	case $1 in
		-r | --root )   shift
				rfsFolder=$1
				;;
		-o | --out )    shift
				outputFile=$1
				;;
		-l| --link )	findType="$findType -o -type l"
				symlink="-l"
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

if [ "$rfsFolder" == "" ]; then
	echo "$name# ERROR : rootFS folder is not set!"
        usage
	exit
fi

if [ ! -d "$rfsFolder" ]; then
	echo "$name# ERROR : $rfsFolder is not a folder!"
        usage
	exit
fi

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

rootFS=
versionTimeStamp=`stat -c"%x" $rfsFolder/version.txt`
if [ ! -e $rfsFolder/version.txt ]; then
	echo "$name# WARNING: $rfsFolder/version.txt file is not present. Cannot retrieve version info. Using rootFS folder for name" | tee -a $rootFS.flb.log
	rootFS=`basename $rfsFolder`
else
	rootFS=`cat $rfsFolder/version.txt | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
fi
touch -d "$versionTimeStamp" $rfsFolder/version.txt

echo "$cmdline" > $rootFS.flb.log
echo "$name : rfsFolder = $rfsFolder : rootFS = $rootFS" | tee -a $rootFS.flb.log

# create a list of target rootFS files
find $rfsFolder  \( $findType \) -exec ls -la {} \;  | tr -s ' ' > $rootFS.files.ls.host

test -e $rootFS.files.all && rm $rootFS.files.all
sub=${rfsFolder%/}
cat $rootFS.files.ls.host | while read line
do
	echo ${line/$sub/} >> $rootFS.files.all
done

#rFLFormat=$(fileFormat $rootFS.files.all)
#[ "$symlink" != "" ] && rFLFormat=$((rFLFormat - 2))

sort -k9 $rootFS.files.all -o $rootFS.files.all

cat $rootFS.files.all | awk '{total += $5} END { printf "rootFS total: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.flb.log

[ "$outputFile" != "" ] && [ "$rootFS.files.all" != "$outputFile" ] && mv $rootFS.files.all $outputFile

#clean up
rm $rootFS.files.ls.host

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60)) | tee -a $rootFS.flb.log

