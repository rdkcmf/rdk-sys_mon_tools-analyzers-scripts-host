#!/bin/sh
# $0 : rootFSTTSAnalyzer.sh is a Linux target based script to analyze usage of regular files based on access info.

# Defaults
lpath="."             # log file path
rpath="/"             # root/search/file path
vfile="/version.txt"  # version.txt file

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [ {-s|-v|-a} [-r file/folder]] | [-h]"
	echo "$name# Target RootFS regular file usage analyzer based on access info"
	echo "$name# {-s|-v|-a} : a mutualy exclusive mandatory option : s - set / v - verify / a - analyze rootFS/folder"
	echo "$name# -r         : an optional folder / file to analyze : default = $rpath"
	echo "$name# -l         : an optional log file path : default = $lpath"
	echo "$name# -f         : an optional version.txt file location : default = $vfile"
	echo "$name# -h         : display this help and exit"
}

# Function: vdate2epoch
function vdate2epoch()
{
	local vdate_day="$3"
	local vdate_time="$4"
	local vdate_year="$6"
	case "$2" in
	    Jan) vdate_month="01" ;;
	    Feb) vdate_month="02" ;;
	    Mar) vdate_month="03" ;;
	    Apr) vdate_month="04" ;;
	    May) vdate_month="05" ;;
	    Jun) vdate_month="06" ;;
	    Jul) vdate_month="07" ;;
	    Aug) vdate_month="08" ;;
	    Sep) vdate_month="09" ;;
	    Oct) vdate_month="10" ;;
	    Nov) vdate_month="11" ;;
	    Dec) vdate_month="12" ;;
	esac

	# get epoch for the local timezone
	export epoch=`date -d "$vdate_year-$vdate_month-$vdate_day $vdate_time" +%s`
	# get the local timezone
	tz=`date | tr -s ' ' | cut -d ' ' -f5`
	if [ "$5" != "$tz" ]; then
		# requested to local timezone conversion
		case $5 in
			EDT) epoch=$(( epoch+14400 )) ;;	#UTC -> EDT
			UTC) epoch=$(( epoch-14400 )) ;;	#EDT -> UTC
			*)   echo "Error: \"$5\" timezone is not supported. Exit!"
			     exit ;;
	    	esac
	fi
	echo "$epoch"
}

SPEC_CHAR_PATTERN='s/[]|&;<()$`\" *?#~=%!{}[]/\\&/g'
SH2LO_L3_PATTERN='^[-l][-rwxs]\{9\} [0-9]\{1,\} [[:alnum:]]\{1,\} [[:alnum:]]\{1,\} [0-9]\{1,\} [[:alpha:]]\{1,3\}[[:blank:]]\{1,\}[0-9]\{1,2\}[[:blank:]]\{1,\}[0-9]\{1,2\}[:]\{0,1\}[0-9]\{1,2\}'
SH2LO_PATTERN=$SH2LO_L3_PATTERN

# Function: flsh2lo - file list conversion from short to long format
# $1: input file list file in short format
# $2: input file list pattern file in long format
# $3: output file list file in long format
function flsh2lo()
{
	cat /dev/null > $3
	sed -e "$SPEC_CHAR_PATTERN" $1 | while read -r
	do
		grep "$SH2LO_PATTERN $REPLY\$" $2 >> $3
	done
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`

options=
while [ "$1" != "" ]; do
	case "$1" in
		-s | -v | -a )  if [ "$options" == "" ]; then 
					options="$1"
				else
					echo "$name# ERROR : mandatory options {-s|-v|-a} are mutualy exclusive"
					usage
					exit
				fi
				;;
		-r | --root )	shift
				rpath="$1"
				vfile=$(echo "${rpath}"/"$vfile" | tr -s '/')
				;;
		-f | --vfile )	shift
				vfile="$1"
				;;
		-l | --lpath )	shift
				lpath="$1"
				;;
		-h | --help )	usage
				exit
				;;
		* )		echo "$name# ERROR : unknown parameter in the command argument list!"
				usage
				exit 1
	esac
	shift
done

if [ "$options" == "" ]; then
	echo "$name# ERROR : One of the manadatory {-s|-v|-a} options must be set! Exit"
	usage
	exit
fi

if [ ! -e "${rpath}" ]; then
	echo "$name# ERROR : ${rpath} doesn't exist! Exit"
	usage
	exit
fi

if [ "$(cat /proc/mounts | grep -w ${rpath} | tr -s ' ' | cut -d ' ' -f4)" == "ro" ]; then
	echo "$name# ERROR : read-only \"${rpath}\" rootfs! Exit!"
	exit
fi

if [ ! -e "$vfile" ]; then
	echo "$name# ERROR : $vfile file is not present. Cannot retrieve build timestamp info!"
	usage
	exit
fi

if [ "$(md5sum ${rpath}/version.txt | cut -d ' ' -f1)" != "$(md5sum ${vfile} | cut -d ' ' -f1)" ]; then
	echo "$name# WARN  : Using ${vfile} instead of ${rpath}/version.txt"
	exit
fi

if [ ! -e "${lpath}" ]; then
	echo "$name# ERROR : log path = ${lpath} doesn't exist"
	exit
fi

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
versionTimeStamp=`stat -c"%x" $vfile`
rootFS=`cat $vfile | grep -i imagename |  tr ': =' ':' | cut -d ':' -f2`
buildTimeStamp=`grep Generated "$vfile" | cut -d ' ' -f3-`
buildTimeEpoch=$(vdate2epoch ${buildTimeStamp})

echo "$cmdline" > ${lpath}/${rootFS}.ts.log
echo "$name: rootFS       = ${rootFS} : options = $options" | tee -a ${lpath}/${rootFS}.ts.log
echo "$name: timestamp    = \"${buildTimeStamp}\" / ${buildTimeEpoch}" | tee -a ${lpath}/${rootFS}.ts.log
echo "$name: root path    = ${rpath}" | tee -a ${lpath}/${rootFS}.ts.log
echo "$name: log path     = ${lpath}" | tee -a ${lpath}/${rootFS}.ts.log
echo "$name: version file = $vfile" | tee -a ${lpath}/${rootFS}.ts.log
echo "" | tee -a ${lpath}/${rootFS}.ts.log

touch -d "@${buildTimeEpoch}" "$vfile" 2> ${lpath}/${rootFS}.ts.err
if [ "$?" -ne "0" ]; then
	echo "${name}: Error executing $(cat ${lpath}/${rootFS}.ts.err). Exit." | tee -a ${lpath}/${rootFS}.ts.log
	rm -f ${lpath}/${rootFS}.ts.err
	exit 
fi
rm -f ${lpath}/${rootFS}.ts.err

if [ "$options" == "-s" ]; then
	echo -e "$name: setting    data ... \c"
	find "${rpath}" -xdev -type f -exec touch -d "@${buildTimeEpoch}" {} \;
	echo "done"
fi

echo -e "$name: collecting data ... \c"
find "${rpath}" -xdev -type f -exec stat -c"%X %x %n" {} \; | sort -k5 > ${lpath}/${rootFS}.ts.files.stat.all
echo "done"

if [ "$options" == "-s" ] || [ "$options" == "-v" ]; then
        grep -v "${buildTimeEpoch}" ${lpath}/${rootFS}.ts.files.stat.all > ${lpath}/${rootFS}.ts.dontmatch.txt
        if [ -s "${lpath}/${rootFS}.ts.dontmatch.txt" ]; then
                echo "$name# WARNING: timestamp has not been set successfully for `wc -l ${lpath}/${rootFS}.ts.dontmatch.txt | cut -d ' ' -f1` file(s)!" | tee -a ${lpath}/${rootFS}.ts.log
                echo "$name# WARNING: a file list with not expected timestamps is in the ${lpath}/${rootFS}.ts.dontmatch.txt" | tee -a ${lpath}/${rootFS}.ts.log
        else
                rm ${lpath}/${rootFS}.ts.dontmatch.txt
                echo "$name: timestamp has been set successfully!" | tee -a ${lpath}/${rootFS}.ts.log
        fi
fi

if [ "$options" == "-a" ]; then
	echo -e "$name: analyzing  data ... \c"

	if [ ! -d "${rpath}" ]; then
		filestat=$(grep ${buildTimeEpoch} ${lpath}/${rootFS}.ts.files.stat.all)
		filename=$(cat ${lpath}/${rootFS}.ts.files.stat.all | cut -d ' ' -f4)
		echo "done"
		if [ "${filestat}" == "" ]; then
			echo "$name: ${rpath} file is used" | tee -a ${lpath}/${rootFS}.ts.log
			ls -la ${filename} > ${lpath}/${rootFS}.ts.used
			rm -f ${lpath}/${rootFS}.ts.unused
		else
			echo "$name: ${rpath} file is NOT used" | tee -a ${lpath}/${rootFS}.ts.log
			ls -la ${filename} > ${lpath}/${rootFS}.ts.unused
			rm -f ${lpath}/${rootFS}.ts.used
		fi
	else
		# all files
		find "${rpath}" -xdev -type f -exec ls -la {} \; | tr -s ' ' | sort -u -k9 > ${lpath}/${rootFS}.files.all
		cat ${lpath}/${rootFS}.files.all | tr -s ' ' | cut -d ' ' -f9- | sort > ${lpath}/${rootFS}.files.all.short
		grep -v ${buildTimeEpoch} ${lpath}/${rootFS}.ts.files.stat.all | cut -d ' ' -f4 | sort > ${lpath}/${rootFS}.ts.used.short
		cat ${lpath}/${rootFS}.files.all.short ${lpath}/${rootFS}.ts.used.short | sort | uniq -u > ${lpath}/${rootFS}.ts.unused.short

		# all used files
		if [ -s "${lpath}/${rootFS}.ts.used.short" ]; then
			flsh2lo ${lpath}/${rootFS}.ts.used.short ${lpath}/${rootFS}.files.all ${lpath}/${rootFS}.ts.used
		fi
		touch ${lpath}/${rootFS}.ts.used

		# all unused files
		if [ -s "${lpath}/${rootFS}.ts.unused.short" ]; then
			flsh2lo ${lpath}/${rootFS}.ts.unused.short ${lpath}/${rootFS}.files.all ${lpath}/${rootFS}.ts.unused
		fi
		touch ${lpath}/${rootFS}.ts.unused
		echo "done"

		awk '{total += $5} END { printf "Total          : %5d files : %10d B / %9.2f KB / %6.2f MB\n", NR, total, total/1024, total/(1024*1024) }' ${lpath}/${rootFS}.files.all | tee -a ${lpath}/${rootFS}.ts.log
		awk '{total += $5} END { printf "Total      Used: %5d files : %10d B / %9.2f KB / %6.2f MB\n", NR, total, total/1024, total/(1024*1024) }' ${lpath}/${rootFS}.ts.used | tee -a ${lpath}/${rootFS}.ts.log
		awk '{total += $5} END { printf "Total    UnUsed: %5d files : %10d B / %9.2f KB / %6.2f MB\n", NR, total, total/1024, total/(1024*1024) }' ${lpath}/${rootFS}.ts.unused | tee -a ${lpath}/${rootFS}.ts.log

		# clean up
		rm ${lpath}/${rootFS}.files.all.short ${lpath}/${rootFS}.ts.*.short
	fi
fi

# clean up
rm ${lpath}/${rootFS}.ts.files.stat.all

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name: Execution time: %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

