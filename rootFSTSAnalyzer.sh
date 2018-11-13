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
# $0 : rootFSTSAnalyzer.sh is a Linux Host based script to analyze usage of regular files based on access time.

# Setup:
usage()
{
	echo "$name# Usage   : `basename $0 .sh` {-s|-v|-a} [-r folder] | [-h]"
	echo "$name# -s|-v|-a: mandatory & mutualy exclusive timestamp analysis type: s - set; v - verify set; a - analyze"
	echo "$name# -r      : rootFS folder"
	echo "$name# -l      : include symlink analysis. \"-a\" analysis type requires rootFS file list file set following the option"
	echo "$name# -h      : display this help and exit"
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

path=$0
path=${path%/*}
source $path/rootFSCommon.sh

analysis=
rfsFolder=
rfsFL=
findType="-type f"
symlink=
while [ "$1" != "" ]; do
	case $1 in
		-s|-v| -a )	analysis=$1
		 		;;
		-r| --root )	shift
				rfsFolder=$1
				;;
		-l| --link )	shift
				findType="$findType -o -type l"
				symlink="y"
				rfsFL=$1
				;;
		-V| --validat )	validation="y"
				;;
		-h| --help )	usage
				exit
				;;
		*)              echo "$name# ERROR : unknown parameter in the command argument list!"
				usage
				exit 1
	esac
	shift
done

if [ "$analysis" == "" ]; then
	echo "$name# ERROR : type of analysis is not properly set!"
        usage
	exit
fi

if [ "$rfsFolder" == "" ] || [ ! -d "$rfsFolder" ]; then
	echo "$name# ERROR : rootFS folder $rfsFolder is not set!"
        usage
	exit
fi

if [ ! -e $rfsFolder/version.txt ]; then
	echo "$name# ERROR : $rfsFolder/version.txt file is not present. Cannot retrieve build timestamp info!"
        usage
	exit
fi

if [ "$analysis" == "-a" ] && [ "$symlink" == "y" ]; then
	if [ ! -e "$rfsFL" ]; then
		echo "$name# ERROR : rootFS file list is not set for symlink analysis!"
		usage
		exit
	fi
fi

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
versionTimeStamp=`stat -c"%x" $rfsFolder/version.txt`
rootFS=`cat $rfsFolder/version.txt | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
buildTimeStamp=`grep Generated $rfsFolder/version.txt | cut -d ' ' -f3-`
touch -d "$versionTimeStamp" $rfsFolder/version.txt
buildTimeEpoch=`date -d "$buildTimeStamp" +%s`

echo "$cmdline" > $rootFS.ts.log
echo "$name: rootFS   : $rootFS" | tee -a $rootFS.ts.log
echo "$name: build    : \"$buildTimeStamp\" / $buildTimeEpoch" | tee -a $rootFS.ts.log

if [ "$analysis" == "-s" ]; then
        echo -e "$name: setting   ... \c"
        find $rfsFolder \( $findType \) -exec touch -h -d "$buildTimeStamp" {} \;
        echo "done"
fi

[ "$analysis" == "-a" ] && echo -e "$name: collecting... \c" || echo -e "$name: verifying ... \c"

find $rfsFolder \( $findType \) -exec stat -c"%X %x %n" {} \; | sort -k5 > $rootFS.ts.all.tmp

[ -e $rootFS.ts.all ] && rm $rootFS.ts.all
sub=${rfsFolder%/}
while read line
do
	echo ${line/$sub/} >> $rootFS.ts.all
done < $rootFS.ts.all.tmp
rm $rootFS.ts.all.tmp
echo "done"

if [ "$analysis" == "-s" ] || [ "$analysis" == "-v" ]; then
        grep -v $buildTimeEpoch $rootFS.ts.all > $rootFS.ts.dontmatch.txt
        if [ -s $rootFS.ts.dontmatch.txt ]; then
                echo "$name# WARNING: timestamp has not been set successfully for `wc -l $rootFS.ts.dontmatch.txt | cut -d ' ' -f1` file(s)!" | tee -a $rootFS.ts.log
                echo "$name# WARNING: a file list with not expected timestamps is in the $rootFS.ts.dontmatch.txt" | tee -a $rootFS.ts.log
        else
                rm $rootFS.ts.dontmatch.txt
                echo "$name: timestamp has been set successfully!" | tee -a $rootFS.ts.log
        fi
fi

if [ "$analysis" == "-a" ]; then
        echo -e "$name: analyzing ... \c"

	if [ "$symlink" == "" ]; then
		$path/rootFSFLBuilder.sh -r $rfsFolder -o $rootFS.files.all > /dev/null
	else
		if [ "$rfsFL" != "$rootFS.files.all" ]; then 
			[ -e "$rootFS.files.all" ] && mv $rootFS.files.all $rootFS.files.all.orig
			ln -sf $rfsFL $rootFS.files.all
		fi
	fi

	fllo2sh $rootFS.files.all $rootFS.files.all.short

        cat $rootFS.ts.all | grep -v $buildTimeEpoch | cut -d ' ' -f5 > $rootFS.ts.used.short.tmp

	if [ "$symlink" == "y" ]; then 
		flst2sh $rootFS.ts.used.short.tmp $rootFS.files.all.short $rootFS.ts.used.short 
		sort $rootFS.ts.used.short -o $rootFS.ts.used.short
	else
		mv $rootFS.ts.used.short.tmp $rootFS.ts.used.short
	fi

        comm -23 $rootFS.files.all.short $rootFS.ts.used.short > $rootFS.ts.unused.short
        # used files
	flsh2lo $rootFS.ts.used.short $rootFS.files.all $rootFS.ts.used
        # unused files
	flsh2lo $rootFS.ts.unused.short $rootFS.files.all $rootFS.ts.unused

        echo "done"

        if [ "$validation" == "y" ]; then
       		printf "$name: validating... "
        	md5loval=$(flcomplval $rootFS.files.all $rootFS.ts.used $rootFS.ts.unused 9)
        	md5shval=$(flcomplval $rootFS.files.all.short $rootFS.ts.used.short $rootFS.ts.unused.short 1)
        	if [ "$md5shval" == "true" ] && [ "$md5loval" == "true" ]; then
       			printf "done\n"
        	else
        		printf "failed! status: %s/%s\n" $md5shval $md5loval
        	fi
	fi
	
        awk '{total += $5} END { printf "Total   inImage: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' $rootFS.files.all | tee -a $rootFS.ts.log
        awk '{total += $5} END { printf "Total      Used: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' $rootFS.ts.used   | tee -a $rootFS.ts.log
        awk '{total += $5} END { printf "Total    UnUsed: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' $rootFS.ts.unused | tee -a $rootFS.ts.log

        # clean up
        rm $rootFS.files.all.short $rootFS.ts.*.short
        [ -e $rootFS.ts.used.short.tmp ] && rm $rootFS.ts.used.short.tmp
fi

# clean up
rm $rootFS.ts.all

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

