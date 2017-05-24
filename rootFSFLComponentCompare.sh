#!/bin/sh

# Function: usage
function usage()
{
	echo "$name# Usage : `basename $0 .sh` [-1 fileList#1 -2 fileList#2 [-3 fileList#3]] | [-h]"
	echo "$name# rootFS File List Component Compare"
	echo "$name# -1    : a componentized fileList#1 - rootFSFLComponentizer.sh output with ext {componentized.components}"
	echo "$name# -2    : a componentized fileList#2 - rootFSFLComponentizer.sh output with ext {componentized.components}"
	echo "$name# -3    : an optional name of a file to output a component based difference between fileList#1,2=fileList#1-fileList#2"
	echo "$name# -h    : display this help and exit"
}

# Main:
cmdline="$0 $@"
name=`basename $0 .sh`
echo "$cmdline" > $name.log

if [ $# -eq 0 ]; then
	echo "$name# ERROR : wrong number of parameters in the command argument list!"
	usage
	exit 1
fi

fileList1=
fileList2=
fileList3=
while [ "$1" != "" ]; do
	case $1 in
		-1 ) 	shift
			fileList1=$1
			;;
		-2 ) 	shift
			fileList2=$1
			;;
		-3 ) 	shift
			fileList3=$1
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

if [ ! -s "$fileList1" ]; then
	echo "$name# ERROR : File list #1 \"$fileList1\" is empty or not found!"
	usage
	exit 1
fi
if [ ! -s "$fileList2" ]; then
	echo "$name# ERROR : File list #2 \"$fileList2\" is empty or not found!"
	usage
	exit 1
fi

echo "$name : File list #1 = $fileList1" | tee -a $name.log
echo "$name : File list #2 = $fileList2" | tee -a $name.log
[ -z "$fileList3" ] && fileList3="${fileList1%%.*}.${fileList2%%.*}.cbd"
echo "$name : File list #3 = $fileList3" | tee -a $name.log

startTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`

join     -j 3 $fileList1 $fileList2 | awk '{printf "%28s %3s %8s %3s %8s %4s %9s\n", $1, $2, $3, $4, $5, $2-$4, $3-$5}' > $fileList3.0
join -v1 -j 3 $fileList1 $fileList2 | awk '{printf "%28s %3s %8s %3s %8s %4s %9s\n", $1, $2, $3,  0,  0,    $2,    $3}' > $fileList3.1
join -v2 -j 3 $fileList1 $fileList2 | awk '{printf "%28s %3s %8s %3s %8s %4s %9s\n", $1,  0,  0, $2, $3,   -$2,   -$3}' > $fileList3.2
cat $fileList3.0 $fileList3.1 $fileList3.2 | sort -k1 -o $fileList3
sort -rnk7 $fileList3 -o $fileList3.rnk7

# Clean up
rm $fileList3.0 $fileList3.1 $fileList3.2

endTime=`cat /proc/uptime | cut -d ' ' -f1 | cut -d '.' -f1`
execTime=`expr $endTime - $startTime`
printf "$name : Exec time : %02dh:%02dm:%02ds\n" $((execTime/3600)) $((execTime%3600/60)) $((execTime%60))

