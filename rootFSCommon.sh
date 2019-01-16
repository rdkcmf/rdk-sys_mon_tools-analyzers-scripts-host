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
# $0 : rootFSCommon.sh is a Linux Host based script with common functions to host rootFS based scripts/utilities/apps.

SPEC_CHAR_PATTERN='s/[]|&;<()$`\" *?#~=%!{}[]/\\&/g'
SH2LO_L3_PATTERN='^[-l][-rwxs]\{9\} [0-9]\{1,\} [[:alnum:]]\{1,\} [[:alnum:]]\{1,\} [0-9]\{1,\} [[:alpha:]]\{1,3\}[[:blank:]]\{1,\}[0-9]\{1,2\}[[:blank:]]\{1,\}[0-9]\{1,2\}[:]\{0,1\}[0-9]\{1,2\}'
#SH2LO_L3_PATTERN='^[-l][-rwxs]\{9\}[[:blank:]]\{1,\}[0-9]\{1,\}[[:blank:]]\{1,\}[[:alnum:]]\{1,\}[[:blank:]]\{1,\}[[:alnum:]]\{1,\}[[:blank:]]\{1,\}[0-9]\{1,\}[[:blank:]]\{1,\}[[:alpha:]]\{1,3\}[[:blank:]]\{1,\}[0-9]\{1,2\}[[:blank:]]\{1,\}[0-9]\{1,2\}:[0-9]\{1,2\}'

SH2LO_PATTERN=$SH2LO_L3_PATTERN

# Function: fileFormat
function fileFormat()
{
	local __nf__=`cat $1 | awk 'BEGIN{FS=" "}; { print NF }' | head -n 1`
	case ${__nf__} in
		1|8|9|11 )
		 ;;
		* )
		usage
		exit
		 ;;
	esac
	echo $__nf__
}

# Function: flsh2lo - file list conversion from short to long format
# $1: input file list file in short format
# $2: input file list pattern file in long format
# $3: output file list file in long format
function flsh2lo()
{
	join -1 1 -2 9 $1 $2 -o 2.1,2.2,2.3,2.4,2.5,2.6,2.7,2.8,2.9 > $3
}

# Function: fllo2sh - file list conversion from long to short format
# $1: input file list file in long format
# $2: output file list file in short format
function fllo2sh()
{
	cat $1 | tr -s ' ' | cut -d ' ' -f9- > $2
}

# Function: flsh2bn - file list conversion from short format to basename
# $1: input file list file	- inFL
# $2: output file list file	- outFL
function flsh2bn()
{
	cat /dev/null > $2
	cat "$1" | tr -s ' ' | cut -d ' ' -f1 | while read
	do
		echo ${REPLY##*/} >> $2
	done
	sort -u $2 -o $2
}

# Function: flst2sh - file list conversion from short stat to short format
# $1: input file list file in short stat format
# $2: input file list pattern file in short [file/link] format
# $3: output file list file in short [file/link] format
function flst2sh()
{
	cat /dev/null > $3
	sed -e "$SPEC_CHAR_PATTERN" $1 | while read -r
	do
		grep "^$REPLY\$\|^$REPLY \-> " $2 >> $3
	done
}

# Function: slbn2sh - symlink list conversion from basename to short format
# $1: input symlink list file in basename format
# $2: input symlink to file map pattern file
# $3: output file list file in short format
function slbn2sh()
{
	cat /dev/null > $3
	sed -e "$SPEC_CHAR_PATTERN" $1 | while read -r
	do
		grep "/$REPLY \-> " $2 | cut -d ' ' -f3 >> $3
	done
}

# Function: rootFSFLBV - rootFS file list builder/validator
# $1: in  - rootFS type
# $2: in  - rootFS descriptor
# $3: out - rootFS file list file postfix: if empty, the default $rootFS.file.all is used, otherwise - "$rootFS.$3" format used.
function rootFSFLBV()
{
	local _rfs_=$1
	local _rfsDescr_=$2
	local _rootFS_=
	local _outFile_=
	local _path_=
	if [ "$_rfs_" == "folder" ]; then
		if [ ! -e $_rfsDescr_/version.txt ]; then
			_rootFS_=`basename $_rfsDescr_`
			#echo "$name# WARNING: $_rfsDescr_/version.txt file is not present. Cannot retrieve version info. Using rootFS folder name"
		else
			_rootFS_=`cat $_rfsDescr_/version.txt | grep -i "^imagename" |  tr ': =' ':' | cut -d ':' -f2`
		fi

		_path_=$0
		_path_=${_path_%/*}
		[ "$3" == "" ] && _outFile_=$_rootFS_.file.all || _outFile_=$_rootFS_.$3
		$_path_/rootFSFLBuilder.sh -r $_rfsDescr_ -o $_outFile_ > /dev/null
	else
		_rootFS_=`basename $_rfsDescr_ | cut -d '.' -f1`
	fi
	echo $_rootFS_
}

# Function: flcomplval - file list complement validation
# $1: input file: complete file list
# $2: input file: complement file list #1
# $3: input file: complement file list #2
# $4: input parameter: sort column
function flcomplval()
{
	[ "$4" == "" ] && col=1 || col=$4
	[ "$(cat "$1" | md5sum | cut -d ' ' -f1)" == "$(cat "$2" "$3" | sort -k$col | md5sum | cut -d ' ' -f1)" ] && echo "true" || echo "false"
}

# Function: flslfilter - file list symlink filter 
# $1: input file: file list with or without symlinks
# return: <input file> name if no symlinks found otherwise <input file>.supported file name and the  file created with no symlinks
function flslfilter()
{
	grep -v "\->" $1 > $1.supported
	if [ "$(md5sum $1 | cut -d ' ' -f1)" == "$(md5sum $1.supported | cut -d ' ' -f1)" ]; then 
		rm $1.supported
		echo "$1"
	else
		echo "$1.supported"
	fi
}

