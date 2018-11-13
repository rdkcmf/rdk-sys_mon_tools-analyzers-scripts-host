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
# $0 : tsAnalyzer.sh is a Linux Host based script to analyze usage of regular files based on access timestamp.
# $1 : param1 is a command line option: s - set timestamp; v - verify timestamp; a - analyze rootFS"
# $2 : param2 is a rootFS folder
# $3 : param3 is a optional file with a list of exceptions from unused files

# Setup:
usage()
{
	echo "$name# Usage : $0 {-s|-v|-a} param2 [param3]"
	echo "$name# param1: command option: s - set timestamp; v - verify timestamp; a - analyze rootFS"
	echo "$name# param2: rootFS folder"
	echo "$name# param3: optional excluded file list"
}

name=`basename $0 .sh`
if [ "$1" == "" ] || [ "$2" == "" ]; then
	echo "$name# ERROR : param1 and/or param2 not properly set!"
        usage
	exit
fi

case ${1} in
        -s|-v|-a )
         ;;
        * )
	echo "$name# ERROR : param1 not properly set!"
        usage
	exit
         ;;
esac

if [ ! -d "$2" ]; then
	echo "$name# ERROR : param1 is not a folder!"
        usage
	exit
fi

if [ ! -e $2/version.txt ]; then
	echo "$name# ERROR : $2/version.txt file is not present. Cannot retrieve build timestamp info!"
        usage
	exit
fi

if [ "$3" != "" ] && [ ! -e "$3" ]; then
	echo "$name# ERROR : optional file $3 doesn't exist"
        usage
	exit
fi

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
versionTimeStamp=`stat -c"%x" $2/version.txt`
rootFS=`cat $2/version.txt | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
buildTimeStamp=`grep Generated $2/version.txt | cut -d ' ' -f3-`
touch -d "$versionTimeStamp" $2/version.txt
buildTimeEpoch=`date -d "$buildTimeStamp" +%s`

echo "$0 $@" > $rootFS.ts.log
echo "$name: rootFS   : $rootFS" | tee -a $rootFS.ts.log
echo "$name: timestamp: \"$buildTimeStamp\" / $buildTimeEpoch" | tee -a $rootFS.ts.log

if [ "$1" == "-s" ]; then
        echo -e "$name: setting   timestamp ... \c"
        find $2 -type f -exec touch -d "$buildTimeStamp" {} \;
        echo "done"
fi

echo -e "$name: verifying timestamp ... \c"
find $2 -type f -exec stat -c"%X %x %n" {} \; | sort -k5 > $rootFS.ts.all.txt.tmp

if [ -e $rootFS.ts.all.txt ]; then
        rm $rootFS.ts.all.txt
fi
sub=$2
sub=${sub%/}
cat $rootFS.ts.all.txt.tmp | while read line
do
	echo -e "${line%$sub*}\c" >> $rootFS.ts.all.txt; echo ${line#*$sub} >> $rootFS.ts.all.txt
done
rm $rootFS.ts.all.txt.tmp
echo "done"

if [ "$1" == "-s" ] || [ "$1" == "-v" ]; then
        grep -v $buildTimeEpoch $rootFS.ts.all.txt > $rootFS.ts.dontmatch.txt
        if [ -s $rootFS.ts.dontmatch.txt ]; then
                echo "$name# WARNING: timestamp has not been set successfully for `wc -l $rootFS.ts.dontmatch.txt | cut -d ' ' -f1` file(s)!" | tee -a $rootFS.ts.log
                echo "$name# WARNING: a file list with not expected timestamps is in the $rootFS.ts.dontmatch.txt" | tee -a $rootFS.ts.log
        else
                rm $rootFS.ts.dontmatch.txt
                echo "$name: timestamp has been set successfully!" | tee -a $rootFS.ts.log
        fi
fi

if [ "$1" == "-a" ]; then
        echo -e "$name: analyzing ... \c"

        # all files
        find $2 -type f -exec ls -la {} \; | sort -u -k9 > $rootFS.files.all.tmp
        if [ -e $rootFS.files.all ]; then
                rm $rootFS.files.all
        fi
        cat $rootFS.files.all.tmp | while read line
        do
	        echo -e "${line%$sub*}\c" >> $rootFS.files.all; echo ${line#*$sub} >> $rootFS.files.all
        done
        rm $rootFS.files.all.tmp

        cat $rootFS.files.all | tr -s ' ' | cut -d ' ' -f9- | sort -k1 > $rootFS.files.all.short
        
        cat $rootFS.ts.all.txt | grep -v $buildTimeEpoch | cut -d ' ' -f5 | sort -k1 > $rootFS.ts.used.short
        comm -23 $rootFS.files.all.short $rootFS.ts.used.short > $rootFS.ts.unused.short

        # all used files
        if [ -s $rootFS.ts.used.short ]; then
                if [ -e $rootFS.ts.used ]; then
                        rm $rootFS.ts.used
                fi
	        cat $rootFS.ts.used.short | while read line
	        do
		        grep -w "$line\$" $rootFS.files.all >> $rootFS.ts.used
	        done
        fi
        touch $rootFS.ts.used

        # all unused files
        if [ -s $rootFS.ts.unused.short ]; then
                if [ -e $rootFS.ts.unused ]; then
                        rm $rootFS.ts.unused
                fi
	        cat $rootFS.ts.unused.short | while read line
	        do
		        grep -w "$line\$" $rootFS.files.all >> $rootFS.ts.unused
	        done
        fi
        touch $rootFS.ts.unused

        # excluded files
        if [ x$3 != x ] && [ -s $3 ]; then
                nf=`cat $3 | awk 'BEGIN{FS=" "}; { print NF }' | head -n 1`
                if [ $nf -ne 1 ]; then
	                cat $3 | tr -s ' ' | cut -d ' ' -f$nf- > $3.tmp
                else
	                ln -s $3 $3.tmp
                fi

                if [ -e $rootFS.ts.excluded ]; then
                        rm $rootFS.ts.excluded
                fi
                sort -u -k1 $3.tmp > $rootFS.ts.excluded.short
                eincount=`wc -l $3.tmp | cut -d ' ' -f1`                        # excluded input count
                endcount=`wc -l $rootFS.ts.excluded.short | cut -d ' ' -f1`     # excluded non-duplicate count
                edcount=`expr $eincount - $endcount`                            # excluded duplicate count
                if [ $edcount -gt 0 ]; then
                        # There are duplicate files in the list of excluded files
                        sort -k1 $3.tmp | uniq -d > $rootFS.ts.excluded.dups.short
                fi
                touch $rootFS.ts.excluded
	        cat $rootFS.ts.excluded.short | while read line
	        do
		        grep -w "$line\$" $rootFS.files.all >> $rootFS.ts.excluded
	        done
                eprcount=`wc -l $rootFS.ts.excluded | cut -d ' ' -f1`           # excluded present count
                emcount=`expr $endcount - $eprcount`                            # excluded missing count
                if [ $emcount -gt 0 ]; then
                        # There are missing files in the list of excluded files
                        cat $rootFS.ts.excluded | tr -s ' ' | cut -d ' ' -f9- > $rootFS.ts.excluded.short.tmp
		        comm -23 $rootFS.ts.excluded.short $rootFS.ts.excluded.short.tmp > $rootFS.ts.excluded.missing
                        mv $rootFS.ts.excluded.short.tmp $rootFS.ts.excluded.short
                fi

                if [ -e $rootFS.ts.excluded.used ]; then
                        rm $rootFS.ts.excluded.used
                fi
                touch $rootFS.ts.excluded.used
	        cat $rootFS.ts.excluded.short | while read line
	        do
		        grep -w "$line\$" $rootFS.ts.used >> $rootFS.ts.excluded.used
	        done
                eucount=`wc -l $rootFS.ts.excluded.used | cut -d ' ' -f1`       # excluded used count

                if [ $eprcount -gt 0 ] && [ $eucount -gt 0 ]; then
                        # There are used files in the list of excluded files
                        cut -d ' ' -f9- $rootFS.ts.excluded.used > $rootFS.ts.excluded.used.short
	                comm -23 $rootFS.ts.excluded.short $rootFS.ts.excluded.used.short > $rootFS.ts.eexcluded.short
                        if [ -e $rootFS.ts.eexcluded ]; then
                                rm $rootFS.ts.eexcluded
                        fi
	                cat $rootFS.ts.eexcluded.short | while read line
	                do
		                grep -w "$line\$" $rootFS.files.all >> $rootFS.ts.eexcluded
	                done
                fi
                touch $rootFS.ts.eexcluded
                eecount=`wc -l $rootFS.ts.eexcluded | cut -d ' ' -f1`           # effective excluded count
        fi

        # effective used files
        if [ x$3.tmp != x ] && [ -s $3.tmp ]; then
                if [ -e $rootFS.ts.eused ]; then
                        rm $rootFS.ts.eused
                fi
                cat $rootFS.ts.used.short $rootFS.ts.excluded.short | sort -u -k1 > $rootFS.ts.eused.short
                touch $rootFS.ts.eused
	        cat $rootFS.ts.eused.short | while read line
	        do
		        grep -w "$line\$" $rootFS.files.all >> $rootFS.ts.eused
	        done
        fi

        # effective unused files
        if [ x$3.tmp != x ] && [ -s $3.tmp ] && [ -s $rootFS.ts.unused.short ]; then
                if [ -e $rootFS.ts.eunused ]; then
                        rm $rootFS.ts.eunused
                fi
                comm -23 $rootFS.ts.unused.short $rootFS.ts.excluded.short > $rootFS.ts.eunused.short
	        cat $rootFS.ts.eunused.short | while read line
	        do
		        grep -w "$line\$" $rootFS.files.all >> $rootFS.ts.eunused
	        done
        fi
        touch $rootFS.ts.eunused

        echo "done"

        cat $rootFS.files.all   | awk '{total += $5} END { printf "Total   inImage: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.ts.log
        cat $rootFS.ts.used     | awk '{total += $5} END { printf "Total      Used: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.ts.log
        cat $rootFS.ts.unused   | awk '{total += $5} END { printf "Total    UnUsed: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.ts.log
        if [ x$3.tmp != x ] && [ -s $3.tmp ]; then
                cat $rootFS.ts.excluded | awk '{total += $5} END { printf "Total  Excluded: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.ts.log
                if [ $eecount -gt 0 ]; then
                        cat $rootFS.ts.eexcluded | awk '{total += $5} END { printf "Total eExcluded: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.ts.log
                fi
                cat $rootFS.ts.eused    | awk '{total += $5} END { printf "Total     eUsed: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.ts.log
                cat $rootFS.ts.eunused  | awk '{total += $5} END { printf "Total   eUnUsed: %4d files / %9d Bytes / %6d KB / %3d MB\n", NR, total, total/1024, total/(1024*1024) }' | tee -a $rootFS.ts.log
                if [ $eucount -gt 0 ]; then
                        echo "$name# WARNING: There are $eucount used file(s) in the $3.tmp exclusion list!" | tee -a $rootFS.ts.log
                fi
                if [ -s $rootFS.ts.excluded.dups.short ]; then
                        echo "$name# WARNING: There are $edcount duplicate file(s) in the $3.tmp exclusion list!" | tee -a $rootFS.ts.log
                fi
                if [ -s $rootFS.ts.excluded.missing ]; then
                        echo "$name# WARNING: There are $emcount missing file(s) in the $3.tmp exclusion list!" | tee -a $rootFS.ts.log
                fi
        fi

        # clean up
        rm $rootFS.files.all.short $rootFS.ts.*.short
        if [ -e $3.tmp ]; then
	        rm $3.tmp
        fi
fi

# clean up
rm $rootFS.ts.all.txt

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

