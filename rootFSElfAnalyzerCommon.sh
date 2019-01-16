#!/bin/bash
#
# If not stated otherwise in this file or this component's Licenses.txt file the
# following copyright and licenses apply:
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
#

#Globals
libdlDefault="/lib/libdl-2.19.so"
libdlDefaultP="$(echo "$libdlDefault" | tr '/' '%')"

# Function: _rootFSDLinkElfAnalyzer_cleanup
function _rootFSDLinkElfAnalyzer_cleanup()
{
	#echo "$FUNCNAME: _elfP = $1 : _elfPwdP = $2 : _wFolder = $3 : _out = $4"
	rm -f "$1".elfrefs "$1".elffound* "$1".*.short "$_elfPwdP".link
	local _clean="$( grep _rootFSDLoadElfAnalyzer <(echo ${FUNCNAME[*]}))"
	[ -z "$_clean" ] && [ -e "$3" ] && [ -z "$(ls -A $3)" ] && rm -rf "$3"
	[ ! -s "$4".error ] && rm -f "$4".error
}

# Function: _rootFSDLinkElfAnalyzer_cleanup_on_signal
function _rootFSDLinkElfAnalyzer_cleanup_on_signal()
{
	errorStatus=$?
	#echo "$FUNCNAME: signal = $1 : _elfP = $2 : _elfPwdP = $3 : _wFolder = $4 : _out = $5"
	_rootFSDLinkElfAnalyzer_cleanup "$2" "$3" "$4" "$5"
	exitProcessing "$1" $errorStatus
	exit $exitCode
}

# Function: _buildElfDFtextTable:
# input:
# $1 - rootFS folder
# $2 - an elf object name
# $3 - an output file name
function _buildElfDFtextTable()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _out="$3"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "out" "$_out"
	"$objdump" -TC "$_rfsFolder/$_elf" | grep "^[[:xdigit:]]\{8\}.*\{6\}DF .text" | sed 's/ \+/ /g;s/\t/ /' | cut -d ' ' -f1,7- | sed 's/ /\t/1' | sort -u | sort -t$'\t' -k2,2 -o "$_out"
}

# Function: _sraddr2line
# Input:
# $1 - rootFS folder
# $2 - target ELF filename
# $3 - symbol reference list file to analyze; all symbols are analyzed if the name is empty
# $4 - output file name
# Output:
# "symbol name - source code location" structured file
# "symbol name - source code location" log =<output file name>.log

#_sraddr2line "$rfsFolder" "$elf" "$symList" "$odTCDFUNDFolder/$elfBase"

function _sraddr2line()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _symList="$3"
	local _out="$4"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "symList" "$_symList" "out" "$_out"

	# Build symbol file
	#sed '1,/Global entries:/d' <(readelf -A "$_rfsFolder/$_elf") | grep " FUNC " | sed '1d;s/^ .//;/^$/d' | tr -s ' ' | tr ' ' '\t' | sort -t$'\t' -k7,7 -o "$_out".gentry.all
	sed '1,/Global entries:/d' <(readelf -AW "$_rfsFolder/$_elf" | c++filt) | grep " FUNC " | sed '1d;s/^ .//;/^$/d' | sed 's/ \+/ /g;s/ /\t/1;s/ /\t/1;s/ /\t/1;s/ /\t/1;s/ /\t/1;s/ /\t/1' | sort -t$'\t' -k7,7 -o "$_out".gentry.all

	if [ -n "$_symList" ]; then
		join -t$'\t' -1 1 -2 7 <(sort "$_symList") "$_out".gentry.all -o 2.1,2.2,2.3,2.4,2.5,2.6,2.7 > "$_out".gentry.user
	else
		ln -sf "$PWD/$_out".gentry.all "$_out".gentry.user
	fi

	# Disassemble the elf
	if [ ! -e "$_out".dC ]; then
		"$objdump" -dC "$_rfsFolder/$_elf" > "$_out".dC
	fi

	# Find source code locations of symbol refs 
	while IFS=$'\t' read _addr _access _initial _symval _type _ndx _name
	do
		grep -w -- "$_access" "$_out".dC | cut -f1 | cut -d ':' -f1 > "$_out.usr.$_name"
		addr2line -Cpfa -e "$_rfsFolder/$_elf" @"$_out.usr.$_name" | cut -d ' ' -f2- > "$_out.usr.$_name.tmp"
		mv "$_out.usr.$_name.tmp" "$_out.usr.$_name"
	done < "$_out".gentry.user
}

# Input:
# $1 - rootFS folder
# $2 - a list of target (full path) ELF filenames
# $3 - symbol list file; all symbols are analyzed if the name is empty
# $4 - output file folder
# $5 - output file postfix
# Output:

# _elfSymRefSources "$_rfsFolder" "$_elf"       "$UndRefListFile"             "locationBase"
# _elfSymRefSources "$_rfsFolder" "$_out".libdl "$odTCDFtextFolder"/libdl.api "$_out".libdl
function _elfSymRefSources
{
	local _rfsFolder="$1"
	local _elfList="$2"
	local _symList="$3"
	local _out="$4"
	local _pfx="$5"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elfList" "$_elfList" "symList" "$_symList" "out" "$_out" "pfx" "$_pfx"

	local _elf=
	while read _elf
	do
		local _elfP=$(echo "$_elf" | tr '/' '%')
		local _log="$_out/$_elfP$_pfx".log
		local _none=true

		[ -s "$odTCDFUNDFolder/$_elfP".log ] && continue
		_sraddr2line "$_rfsFolder" "$_elf" "$_symList" "$odTCDFUNDFolder/$_elfP"

		local _ref=
		cat /dev/null > "$_log"
		cat /dev/null > "$_log".tmp
		#Fix me
		if [ -n "$_symList" ]; then
			while read _ref
			do
				if [ -s "$odTCDFUNDFolder/$_elfP".usr."$_ref" ]; then
					printf "\t%s:\n" "$_ref" >> "$_log".tmp
					sed 's/^/\t\t/' "$odTCDFUNDFolder/$_elfP".usr."$_ref" >> "$_log".tmp
					_none=false
				else
					printf "\t%s:\tnone\n" "$_ref" >> "$_log".tmp
				fi
			done < "$_symList"

			if [ "$_none" == "false" ]; then
				printf "%-37s:\n" "$_elf" >> "$_log"
				cat "$_log".tmp >> "$_log"
			else
				printf "%-37s:\tnone\n" "$_elf" >> "$_log"
			fi
		else
			for _ref in "$odTCDFUNDFolder/$_elfP".usr.* 
			do
				if [ -s "$_ref" ]; then
					printf "\t%s:\n" "${_ref##*.}" >> "$_log".tmp
					sed 's/^/\t\t/' "$_ref" >> "$_log".tmp
					_none=false
				else
					printf "\t%s:\n" "${_ref##*.}" >> "$_log".tmp
				fi
			done

			if [ "$_none" == "false" ]; then
				printf "%s:\n" "$_elf" >> "$_log"
				cat "$_log".tmp >> "$_log"
			else
				printf "%s:\tnone\n" "$_elf" >> "$_log"
			fi
		fi
		#cleanup
		rm -f "$_log".tmp
	done < "$_elfList"
}

# Function: _soRefedByApp
# $1 - folder	-a folder with a list of apps and dependent dynamically linked libraries, as .dlink
# $2 - filename	-a list of shared libraries to analyze
# $3 - logname	-an output log file
# _soRefedByApp $_folder $_soList $_log
function _soRefedByApp()
{
	local _folder="$1"
	local _soList="$2"
	local _log="$3"

	if [ -s "$_soList" ]; then
		cat /dev/null > "$_log"
		local _elf=
		local _refed=
		local _byte=${#_folder}
		_byte=$((_byte+2))
		while read _elf
		do
			grep "^$_elf$" "$_folder"/*.dlink | cut -d ":"  -f1 | cut -b$_byte- | tr '%' '/' | sort > "$_soList".elf
			printf "%-4d %s:" $(wc -l $"$_soList".elf | cut -d ' ' -f1) "$_elf" >> "$_log"
			while read _refed
			do
				printf "\t%s" ${_refed/"${_folder}/"/} >> "$_log"
			done < "$_soList".elf
			echo >> "$_log"
		done < "$_soList"
		sort -rnk1 "$_log" -o "$_log"
		sed -i 's/\t/\n\t/g;s/.dlink//g;s/ \+/\t/' "$_log"

		rm -f "$_soList".elf
	fi
}

# Function: _rootFSDLinkElfAnalyzer
# Finds all dynamically linked shared library dependencies of a single ELF object (exe/so) or a list of refs to shared objects in a recursive fashion
# Input:
# $1 - rootFS folder
# $2 - target ELF file name or "empty": In the later case, $2 is not associated w/ any specific ELF, $3 is a collection of ELFs such as NSS ELFs.
# $3 - 1) $2 is not empty : $3 is empty or a list of ELF's references such as a list of ELF's links/names/ or both; 2) $2 is empty : $3 is a collection of ELFs such NSS ELFs.
#	$2 and $3 cannot be both empty.
# $4 - output file name
# $5 - work folder
# $6 - build an elf's libdl dependency list, if not empty
# $7 - build elf's dlink iter log, if not empty
# Output:
# ELF file dynamically linked library list = <output file name> = <$4 name>

# _rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps list : $7 - iter log

function _rootFSDLinkElfAnalyzer()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _elfRefs="$3"
	local _out="$4"
	local _wFolder="$5"
	local _libdl="$6"
	local _iterLog="$7"

	[ -z "$_wFolder" ] && _wFolder=.
	local _elfP="$_wFolder/$(basename "$_out")"
	local _elfPwdP="$PWD/$_elfP"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "elfRefs" "$_elfRefs" "out" "$_out" "wFolder" "$_wFolder" "iterLog" "$_iterLog"

	. "$path"/errorCommon.sh
	setTrapHandlerWithParams _rootFSDLinkElfAnalyzer_cleanup_on_signal 6 0 1 2 3 6 15 "$_elfP" "$_elfPwdP" "$_wFolder" "$_out"

	[ -n "$_iterLog" ] && cat /dev/null > "$_iterLog"

	if [ -n "$_elf" ]; then
		"$objdump" -x "$_rfsFolder/$_elf" | grep "NEEDED" | tr -s ' ' | cut -d ' ' -f3 > "$_elfP".elfrefs
	else
		cp "$_elfRefs" "$_elfP".elfrefs
	fi

	local _iter=0
	cat /dev/null > "$_out"
	cat /dev/null > "$_out".error

	if [ -n "$_libdl" ]; then
		local _libdlElf="$_elf"
		cat /dev/null > "$_out".libdl
	fi

	ln -sf "$_elfPwdP".elfrefs "$_elfPwdP".link
	while [ -s "$_elfPwdP.link" ]; do
		# find all references in the objdump output
		cat /dev/null > "$_elfP".elffound
		while read _entry
		do
			if [[ "$_entry" == /* ]]; then
				echo "$_rfsFolder$_entry" >> "$_elfP".elffound
			else
				find "$_rfsFolder" -name "$_entry" | grep -v "\.debug" > "$_elfP".elffound.tmp
				if [ -s "$_elfP".elffound.tmp ]; then 
					cat "$_elfP".elffound.tmp >> "$_elfP".elffound
				else
					printf "%1d: unresolved _entry: %s\n" $_iter "$_entry/$_rfsFolder/" >> "$_out".error
				fi
			fi
		done < "$_elfP".elfrefs

		cat /dev/null > "$_elfP.$_iter".short
		while read _entry
		do
			_entryHResolved=$(readlink -e $_entry)
			if [ -n "$_entryHResolved" ]; then
				local entryTResolved="${_entryHResolved/$_rfsFolder//}"
				echo "$entryTResolved" | tr -s '/' >> "$_elfP.$_iter".short
				if [ -n "$_libdl" ]; then
					if [[ $entryTResolved == *libdl* ]] && [[ -n "$_libdlElf" ]]; then
						#echo "1: $_libdlElf"
						echo "$_libdlElf" | tr -s '/' >> "$_out".libdl
					fi
				fi
			else
				printf "%1d: unresolved  link: %s\n" $_iter "${_entry/$_rfsFolder//}" | tr -s '/' >> "$_out".error
			fi
		done < "$_elfP".elffound
		sort -u "$_elfP.$_iter".short -o "$_elfP.$_iter".short

		if [ "$_iter" -eq 0 ]; then
			cat "$_elfP.$_iter".short > "$_out"
			ln -sf "$_elfPwdP.$_iter".short "$_elfPwdP".link
		else
			comm -13 "$_elfP".$((_iter-1)).short "$_elfP.$_iter".short > "$_elfP".uniq.short
			cat "$_elfP".uniq.short >> "$_out"
			ln -sf "$_elfPwdP".uniq.short "$_elfPwdP".link
			
		fi

		if [ -n "$_iterLog" ]; then
			while read _entry
			do
				printf "%1d: %s\n" "$_iter" "$_entry" >> "$_iterLog"
			done < "$_elfPwdP".link
		fi

		cat /dev/null > "$_elfP".elfrefs
		while read _entry
		do
			#echo "iter=$_iter : _entry=$_entry"
			local _needed=$("$objdump" -x "$_rfsFolder/$_entry" | grep "NEEDED" | tr -s ' ' | cut -d ' ' -f3)
			"$objdump" -x "$_rfsFolder/$_entry" | grep "NEEDED" | tr -s ' ' | cut -d ' ' -f3 >> "$_elfP".elfrefs
			if [ -n "$_libdl" ]; then
				if [[ $(echo "$_needed") == *libdl* ]]; then
					#echo "2: $_entry"
					echo "$_entry" | tr -s '/' >> "$_out".libdl
					_libdlElf=
				fi
			fi
		done < <(sed -e '/^[ \t]*$/d' "$_elfPwdP".link)
		sort -u "$_elfP".elfrefs -o "$_elfP".elfrefs

		_iter=`expr $_iter + 1`
	done
	[ -s "$_out" ] && sort -u "$_out" -o "$_out"

	if [ -n "$_libdl" ] && [ -s "$_out".libdl ]; then
		sort -u "$_out".libdl -o "$_out".libdl
		if [ -e "$odTCDFtextFolder"/libdlApi ]; then
			if [ ! -s "$rfsLibdlFolder"/"$_out".libdl.log ]; then
				_elfSymRefSources "$_rfsFolder" "$_out".libdl "$odTCDFtextFolder"/libdlApi "$rfsLibdlFolder" ".dlink.libdl"
			else
				printf "skipping $rfsLibdlFolder/$_out.libdl.log generation !\n"
			fi
		else
			printf "missing $odTCDFtextFolder/libdlApi file!\n" >> "$_out".libdl.error
		fi
	fi

	# cleanup
	_rootFSDLinkElfAnalyzer_cleanup "$_elfP" "$_elfPwdP" "$_wFolder" "$_out"
}

_NSS_DEFAULT_SERVICES="compat\ndb\ndns\nfiles\nnis"

# Function: _rootFSBuildNssCache
# Builds NSS cache
# Input:
# $1 - rootFS folder
# Output:
# Target rootFS NSS cache consitsing of:
# $rfsNssFolder/nss.services	- a list NSS services created based on target's /etc/nsswitch.conf config file
# $rfsNssFolder/nss.short	- a list NSS service libraries found and matched to the $rfsNssFolder/nss.services
# $rfsNssFolder/nss.not-found	- a list NSS service libraries not-found /not-installed according to the $rfsNssFolder/nss.services
# $rfsNssFolder/nss.api		- a list NSS service libraries (in % format) containing exposed service API

# _rootFSBuildNssCache : $1 - rootFS folder

function _rootFSBuildNssCache()
{
	local _rfsFolder="$1"

	if [ ! -e "$_rfsFolder"/etc/nsswitch.conf ]; then
		# Build NSS default services if $rfsNssFolder/nss.services is missing
		echo -e "$_NSS_DEFAULT_SERVICES" > $rfsNssFolder/nss.services
	else
		sed '/^#/d;/^$/d;s/^.*://;s/^ *//g;s/[.*]//g' "$_rfsFolder"/etc/nsswitch.conf | tr ' ' '\n' | sort -u -o $rfsNssFolder/nss.services
	fi

	if [ -e "$rfsNssFolder"/nss.api ]; then
		return
	fi

	cat /dev/null > "$rfsNssFolder"/nss.api
	cat /dev/null > "$rfsNssFolder"/nss.short
	cat /dev/null > "$rfsNssFolder"/nss.not-found
	local _service=
	while read _service
	do
		local _lib=$(find "$_rfsFolder" -type f -name "libnss_${_service}*" | grep -v "\.debug")
		if [ -n "$_lib" ]; then
			local _libT=$(echo "$_lib" | sed "s:$sub::")
			echo "$_libT" | sed "s:$sub::" >> "$rfsNssFolder"/nss.short
			local _libP=$(echo "$_libT" | tr '/' '%')
			if [ ! -e "$odTCDFtextFolder/$_libP".odTC-DFtext ]; then
				_buildElfDFtextTable $_rfsFolder "$_lib" "$odTCDFtextFolder/$_libP".odTC-DFtext
			fi
			if [ ! -e "$rfsNssFolder/$_libP".api ]; then
				#cat <(sed "s/^_nss_${_service}_//" "$odTCDFtextFolder/$_libP".odTC-DFtext) \
				#    <(sed "s/^_nss_${_service}_//;s/_r$//" "$odTCDFtextFolder/$_libP".odTC-DFtext) | sort -u -o "$rfsNssFolder/$_libP".api

				cat <(sed "s/^[[:xdigit:]]\{8\}\t_nss_${_service}_//" "$odTCDFtextFolder/$_libP".odTC-DFtext) \
				    <(sed "s/^[[:xdigit:]]\{8\}\t_nss_${_service}_//;s/_r$//" "$odTCDFtextFolder/$_libP".odTC-DFtext) | sort -u -o "$rfsNssFolder/$_libP".api
				echo "$_libP.api" >> "$rfsNssFolder"/nss.api
			fi
		else
			echo "libnss_${_service}*.so" >> "$rfsNssFolder"/nss.not-found
		fi
	done < "$rfsNssFolder"/nss.services

	local _elfDLink=
	while read _elfDLink
	do
		local _outBase="$(basename $(echo $_elfDLink | tr '/' '%'))"
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "$_elfDLink" "" "$rfsNssFolder/$_outBase" "" "" ""
	done < "$rfsNssFolder"/nss.short
}

# Function: _rootFSNssSingleElfAnalyzer
# Input:
# $1 - rootFS folder
# $2 - target ELF
# $3 - an output file name
# $4 - a log
# Output:
# ELF file NSS library list = $rfsNssFolder/<output file base name>.dload = $rfsNssFolder/<$4 base name>
# ELF file NSS library list log = $rfsNssFolder/<output file base name>.nss.log

function _rootFSNssSingleElfAnalyzer()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _out="$3"
	local _nssLog="$4"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "out" "$_out" "nssLog" "$_nssLog"

	local _elfP=$(echo $_elf | tr '/' '%')
	local _outBase="$(basename "$_out")"
	local _nssOut="$rfsNssFolder/$_outBase".tmp

	# build a list of elf's UND symbols (if not built) and compare it with nss api
	if [ ! -s "$odTCDFUNDFolder/$_elfP".odTC-DFUND ]; then
		"$objdump" -TC "$_rfsFolder/$_elf" | grep "^[[:xdigit:]]\{8\}.*\{6\}DF \*UND\*" | cut -f2 | tr -s ' ' | cut -d ' ' -f3- | sort -u -o "$odTCDFUNDFolder/$_elfP".odTC-DFUND
	fi
	
	cat /dev/null > "$_nssOut"
	local _nss_service_api=
	local _none=true
	while read _nss_service_api
	do
		comm -12 "$rfsNssFolder/$_nss_service_api" "$odTCDFUNDFolder/$_elfP".odTC-DFUND > "$rfsNssFolder/$_elfP.$_nss_service_api.deps"
		if [ -s "$rfsNssFolder/$_elfP.$_nss_service_api.deps" ]; then
			printf "\t%s\t:\n" "$_nss_service_api" >> $_nssOut
			#_sraddr2line "$rfsFolder" "$elf" "$symList" "$odTCDFUNDFolder/$elfBase"
			_sraddr2line "$_rfsFolder" "$_elf" "$rfsNssFolder/$_elfP.$_nss_service_api.deps" "$odTCDFUNDFolder/$_outBase"
			local _line=
			while read _line
			do
				if [ -s "$odTCDFUNDFolder/$_outBase.usr.$_line" ]; then
					printf "\t\t%-18s\t:\n" "$_line" >> $_nssOut
					sed 's/^/\t\t\t/' "$odTCDFUNDFolder/$_outBase.usr.$_line" >> $_nssOut
				else
					printf "\t\t%-18s\t: not found\n" "$_line" >> $_nssOut
				fi
			done < "$rfsNssFolder/$_elfP.$_nss_service_api.deps"
			local _nss_service_lib=$(echo "$_nss_service_api" | tr '%' '/')
			echo ${_nss_service_lib%.api} >> "$_out"
			_none=false
		else
			printf "\t%s\t: none\n" "$_nss_service_api" >> $_nssOut
			rm "$rfsNssFolder/$_elfP.$_nss_service_api.deps"
		fi
	done < "$rfsNssFolder"/nss.api
	if [ $_none = "false" ]; then
		printf "%-37s\t:\n" "$_elf" >> $_nssLog
		cat $_nssOut >> $_nssLog
	else
		printf "%-37s\t: none\n" "$_elf" >> $_nssLog
	fi

	# Cleanup
	rm -f "$_nssOut"
}

# Function: _rootFSNssElfAnalyzer
# Description:
# Identifies if an Elf binary depends on Nss api methods and lists source code locations of Api calls.
# Input:
# $1 - rootFS folder
# $2 - target ELF file name
# $3 - an output file name base
# Output:
# ELF file NSS library list = $rfsNssFolder/<output file base name>.dload = $rfsNssFolder/<$4 base name>
# ELF file NSS library list log = $rfsNssFolder/<output file base name>.nss.log

# _rootFSNssElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name : $3 - output file name base

function _rootFSNssElfAnalyzer()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _out="$3"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "out" "$_out"

	local _outBase="$(basename $_out)"
	local _nssOut="$rfsNssFolder/$_outBase".nss
	local _nssLog="$_nssOut".log

	if [ ! -s "$rfsNssFolder"/nss.api ]; then
		# if "$rfsNssFolder"/nss.api is of zero length, attempt to build it again and return if it's of zero length again
		_rootFSBuildNssCache "$rfsFolder"
		if [ ! -s "$rfsNssFolder"/nss.api ]; then
			# Target rootFS doesn't support NSS
			echo "$name# WARN : Target rootFS=$rfsFolder doesn't support NSS! Return!" | tee "$rfsNssFolder"/nss.log | tee -a "$name".log
			# Null the default services
			cat /dev/null > $rfsNssFolder/nss.services
			return $ERR_OBJ_NOT_FOUND
		fi
	fi

	cat /dev/null > "$_nssOut"
	cat /dev/null > "$_nssLog"
	_rootFSNssSingleElfAnalyzer "$_rfsFolder" "$_elf" "$_nssOut" "$_nssLog"

	# Build an so DLink list if not available
	if [ ! -e "$rfsDLinkFolder/$_outBase".dlink ]; then
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "$_elf" "" "$rfsDLinkFolder/$_outBase".dlink "" "" ""
	fi

	# build lists of symbols (if not built) of all so in the DLink list and compare them with nss api
	local _elfDLink=
	while read _elfDLink
	do
		local _outBaseDLink="$(basename $(echo $_elfDLink | tr '/' '%'))"
		_rootFSNssSingleElfAnalyzer "$_rfsFolder" "$_elfDLink" "$odTCDFUNDFolder/$_outBaseDLink" "$_nssLog"
		if [ -s "$odTCDFUNDFolder/$_outBaseDLink" ]; then
			cat "$odTCDFUNDFolder/$_outBaseDLink" >> "$_nssOut"
			rm -f "$odTCDFUNDFolder/$_outBaseDLink"
		fi
	done < "$rfsDLinkFolder/$_outBase".dlink

	# create a final list of elf's nss libraries
	sort -u "$_nssOut" -o "$_nssOut"

	cat /dev/null > "$_nssOut".dlink
	while read _elfDLink
	do
		local _outBaseDLink="$(basename $(echo $_elfDLink | tr '/' '%'))"
		cat "$rfsNssFolder/$_outBaseDLink" >> "$_nssOut".dlink
	done < "$_nssOut"

	# create a final list of elf's nss dlink libraries
	sort -u "$_nssOut".dlink -o "$_nssOut".dlink
}

# Function: _rootFSSymbsElfAnalyzer:
# input:
# $1 - an elf object name
# $2 - a sorted list of shared libraries to analyze
# $3 - an analysis folder
# $4 - a folder with dynamic symbol tables of rootFS Elf objects
# $5 - an output file name

function _rootFSSymbsElfAnalyzer()
{
	local _elf="$1"
	local _libs="$2"
	local _wFolder="$3"
	local _dsymFolder="$4"
	local _out="$5"
	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "elf" "$_elf" "libs" "$(cat $_libs | tr '\n' ' ')" "wFolder" "$_wFolder" "dlsymsFolder"  "$_dsymFolder" "out" "$_out" 

	cat /dev/null > "$_out".log
	_elfP=$(echo "$_elf" | tr '/' '%')
	local _soFile=
	while read _soFile
	do
		_soFileP=$(echo "$_soFile" | tr '/' '%')
		join -t$'\t' -1 1 -2 2 "$_wFolder/$_elfP".symbs "$_dsymFolder/$_soFileP".odTC-DFtext -o 2.1,2.2 | grep -v "^[[:xdigit:]]\{8\}"$'\t'"main$" > "$_wFolder/$_elfP-$_soFileP".str-symb
		if [ -s "$_wFolder/$_elfP-$_soFileP".str-symb ]; then
			echo "$_soFile:" >> "$_out".log
			cut -f1 "$_wFolder/$_elfP-$_soFileP".str-symb > "$_wFolder/$_elfP-$_soFileP".str-symb.addrs
			addr2line -Cpfa -e "$rfsFolder/$_soFile" @"$_wFolder/$_elfP-$_soFileP".str-symb.addrs >"$_wFolder/$_elfP-$_soFileP".str-symb.addr2line
			sed 's/^/\t/' <(cut -f2- "$_wFolder/$_elfP-$_soFileP".str-symb.addr2line) >> "$_out".log
			echo "$_soFile" >> "$_out" # matched libs

#			rm "$_wFolder/$_elfP-$_soFileP".str-symb.addrs "$_wFolder/$_elfP-$_soFileP".str-symb
#		else
#			rm -f "$_wFolder/$_elfP-$_soFileP".str-symb
		fi
	# Don't check <this> shared object
	done < <(grep -v "^$_elf$" "$_libs")
}


# Function: _rootFSDLoadElfAnalyzer
# Input:
# $1 - rootFS folder
# $2 - target ELF or ELF file ref name
# $3 - an output file name
# $4 - work folder
# Output:
# ELF file dynamically loaded library list = $rfsDLoadFolder/<output file base name>.dload = $rfsDLoadFolder/<$4 base name>
# ELF file dynamically loaded library list log = $rfsDLoadFolder/<output file base name>.dload.log

# _rootFSDLoadElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name : $3 - output file name : $4 - work folder

function _rootFSDLoadElfAnalyzer()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _out="$3"
	local _wFolder="$4"

	local _outBase="$(basename "$_out")"
	local _dlinkOutBase="$rfsDLinkFolder/$_outBase".dlink
	local _dlopenOut="$rfsDLoadFolder/$_outBase".dlopen
	local _dlsymsOut="$rfsSymsFolder/$_outBase".dlsym
	local _dloadOutAll="$rfsDLoadFolder/$_outBase".dload.all
	local _symbsBase="$rfsSymsFolder/$_outBase"
	local _dloadLog="$rfsDLoadFolder/$_outBase".dload.log

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "out" "$_out" "wFolder" "$_wFolder" | tee -a "$name".log
	#printf "%-12s = %s\n%-12s = %s\n%-12s = %s\n" "dlinkOutBase" "$_dlinkOutBase" "dloadOutAll" "$_dloadOutAll" "dlsymsOut" "$_dlsymsOut" | tee -a "$name".log

	cat /dev/null > "$_dloadLog"
	cat /dev/null > "$_dlsymsOut"
	cat /dev/null > "$_dloadOutAll"

	if [ ! -s "$_dlinkOutBase" ]; then
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - iter log
		_rootFSDLinkElfAnalyzer "$_rfsFolder" "$_elf" "" "$_dlinkOutBase" "$_wFolder" "" ""
	fi
	
	#if an elf, check dlink list for libdl & exit if not there.
	if [ -z "$(comm -12 "$_dlinkOutBase" <(echo $libdlDefault))" ]; then
		printf "%-36s : %s\n" "$_elf" "not libdl dlinked" >> "$_dloadLog"
		return
	fi

	if [ ! -s "$rootFS".files.elf.dlink-libdld.dlapi ] || [ ! -s "$rootFS".files.so.unrefed.dlink-libdld.dlapi ]; then
		echo "Calling $path/rootFSELFAnalyzer.sh..."
		"$path"/rootFSELFAnalyzer.sh -r $rfsFolder -od "$objdump" -dlink
	fi
	sort -u -k9 "$rootFS".files.elf.dlink-libdld.dlapi "$rootFS".files.so.unrefed.dlink-libdld.dlapi -o "$rootFS".files.elf.dlink-libdld.dlapi.all

	[ ! -e "$rootFS".files.elf.dlink-libdld.dlapi.short ] && fllo2sh "$rootFS".files.elf.dlink-libdld.dlapi "$rootFS".files.elf.dlink-libdld.dlapi.short
	[ ! -e "$rootFS".files.so.unrefed.dlink-libdld.dlapi ] && fllo2sh "$rootFS".files.so.unrefed.dlink-libdld.dlapi "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short
	[ ! -e "$rootFS".files.elf.dlink-libdld.dlapi.all.short ] && fllo2sh "$rootFS".files.elf.dlink-libdld.dlapi.all "$rootFS".files.elf.dlink-libdld.dlapi.all.short

	[ ! -e "$rootFS".files.so.all.short ] && fllo2sh "$rootFS".files.so.all "$rootFS".files.so.all.short

	# create a list of libs and an exe (if required) of libdl directly dependent elfs
	if [ -s "$_dlinkOutBase".libdl ]; then
		comm -1 "$rootFS".files.elf.dlink-libdld.dlapi.all.short "$_dlinkOutBase".libdl | awk -F'\t' -v base="$rfsDLoadFolder/$_outBase" '{\
		if (NF == 2) {\
			printf("%s\n", $2) > base".dlink-libdld.dlapi"
		} else if (NF == 1) {\
			printf("%-36s : dlapi =\n", $1) > base".dload.log"
		}\
		}'
	else
		comm -12 "$rootFS".files.elf.dlink-libdld.dlapi.all.short <(sort <(cat "$_dlinkOutBase" <(echo "$_elf"))) > $rfsDLoadFolder/$_outBase.dlink-libdld.dlapi
	fi

	# find all dlapi libs:
	[ ! -e "$rootFS".files.so.dlink-libdld.dlapi.short ] && fllo2sh "$rootFS".files.so.dlink-libdld.dlapi "$rootFS".files.so.dlink-libdld.dlapi.short
	[ ! -e "$rootFS".files.so.dlink-libdld.dlapi.all.short ] && sort -u "$rootFS".files.so.dlink-libdld.dlapi.short "$rootFS".files.so.unrefed.dlink-libdld.dlapi.short \
		-o "$rootFS".files.so.dlink-libdld.dlapi.all.short
	
	ln -sf "$PWD/$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi "$PWD/$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.link

	local _iter=1
	cat /dev/null > "$rfsDLoadFolder/$_outBase".dload+dlink.all
	cat /dev/null > "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.parsed
	while [ -s "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.link ]
	do
		local _elfDLoad=
		cat /dev/null > "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.next
		while read _elfDLoad
		do
			#printf "\t%-2d: elfDLoad=%s\n" "$_iter" "$_elfDLoad"
			local _elfDLoadP=$(echo $_elfDLoad | tr '/' '%')
			#[ -e $rfsDLoadFolder/$_elfDLoadP.dload ] && continue
			local _outElfBase="$(basename "$_elfDLoadP")"

			_dloadOut="$rfsDLoadFolder/$_outElfBase".dload
			_dlopenOut="$rfsDLoadFolder/$_outElfBase".dlopen
			if [ -n "$(grep ^$_elfDLoad$ "$rootFS".files.exe.all)" ]; then
				_dlinkOut="$rfsDLinkFolder/$_outElfBase".dlink
			else
				_dlinkOut="$rfsDLinkUnrefedSoFolder/$_outElfBase".dlink
			fi
			_dlsymsOut="$rfsSymsFolder/$_outElfBase".dlsym
			_symbsBase="$rfsSymsFolder/$_outElfBase"

			#printf "%-12s = %s\n%-12s = %s\n%-12s = %s\n" "dlinkOut" "$_dlinkOut" "dloadOut" "$_dloadOut" "dlsymsOut" "$_dlsymsOut"

			cat /dev/null > "$_dloadOut"
			cat /dev/null > "$_dlsymsOut"

			# build elf's list of UND symbols if not built
			if [ ! -s "$odTCDFUNDFolder/$_outElfBase".odTC-DFUND ]; then
				"$objdump" -TC "$_rfsFolder/$_elfDLoad" | grep "^[[:xdigit:]]\{8\}.*\{6\}DF \*UND\*" | cut -f2 | tr -s ' ' | cut -d ' ' -f3- | cut -d '(' -f1 | sort -u -o ${odTCDFUNDFolder}/"$_outElfBase".odTC-DFUND
			fi

			# Identify an elf's obj dependencies on $libdlDefault api
			libdlApi="$(comm -12 <(cut -f2- "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext) "$odTCDFUNDFolder/$_outElfBase".odTC-DFUND)"
			if [ -z "${libdlApi}" ]; then
				printf "%-36s : dlapi =\n" "$_elfDLoad" >> "$_dloadLog"
				continue
			fi

			printf "%-36s : dlapi = %s\n" "$_elfDLoad" "$(echo "$libdlApi" | tr '\n' ' ')" >> "$_dloadLog"

			if [[ "$libdlApi" == *dlopen* ]] || [[ "$libdlApi" == *dlsym* ]]; then
				if [ ! -e "$_symbsBase".symbs ]; then
					strings "$_rfsFolder/$_elfDLoad" | grep -v "[^a-zA-Z0-9_./]" | sort -u -o "$_symbsBase".symbs
				fi
			fi

			if [ ! -s "$_dlinkOut" ]; then
				#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - iter log
				_rootFSDLinkElfAnalyzer "$_rfsFolder" "$_elfDLoad" "" "$_dlinkOut" "$_wFolder" "" ""
			fi

			if [[ "$libdlApi" == *dlopen* ]]; then
				# 1. Find a list of shared objects in strings,
				grep "\.so" "$_symbsBase".symbs | sort -u -o "$_symbsBase".str-so
				#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - iter log
				_rootFSDLinkElfAnalyzer "$_rfsFolder" "$_elfDLoad" "$_symbsBase".str-so "$_symbsBase".str-so.dlink "$_wFolder" "" ""
				# 2. remove <this> dlapi elf and compare it with a list of all (capable of dload) libs to find dependent libdl api libs
				comm -12 <(comm -23 "$_symbsBase".str-so.dlink <(echo "$_elfDLoad")) "$rootFS".files.so.dlink-libdld.dlapi.all.short > "$_dlopenOut"
				if [ -s "$_dlopenOut" ]; then
					cat "$_dlopenOut" >> "$_dloadOut"
					printf "\t%-28s : %s (%d)\n" "dlopen" "$_dlopenOut" $(wc -l "$_dlopenOut" | cut -d ' ' -f1) >> "$_dloadLog"
				else
					printf "\t%-28s : not found\n" "dlopen" >> "$_dloadLog"
					rm -f "$_dlopenOut"
				fi

				echo "$_elfDLoad" > "$_outElfBase".file
				echo "dlopen" > "$_outElfBase".sym
				# _elfSymRefSources "$_rfsFolder" "$_elfFileList" "$symListFile" "locationBase"
				#_elfSymRefSources "$_rfsFolder" $_outElfBase.file $_outElfBase.sym "$odTCDFUNDFolder/$_outElfBase"
				_elfSymRefSources "$_rfsFolder" "$_outElfBase".file "$_outElfBase".sym "$odTCDFUNDFolder/" ""
				if [ -e "$odTCDFUNDFolder/$_outElfBase".usr.dlopen ]; then
					printf "\t\t%-20s :\t\t%s (%d)\n" "dlopen refs" "$odTCDFUNDFolder/$_outElfBase".usr.dlopen $(wc -l "$odTCDFUNDFolder/$_outElfBase".usr.dlopen | cut -d ' ' -f1) >> "$_dloadLog"
				else
					printf "\t\t%-20s :\t\t%s (%d)\n" "dlopen refs" "$odTCDFUNDFolder/$_outElfBase".usr.dlopen 0 >> "$_dloadLog"
				fi
				rm -f "$_outElfBase".*
			fi

			if [[ "$libdlApi" == *dlsym* ]]; then
				# Find a list of shared objects that have strings matching valid c/cpp identifiers/symbols
				_rootFSSymbsElfAnalyzer "$_elfDLoad" <(comm -23 "$rootFS".files.so.all.short "$_dlinkOut") "$rfsSymsFolder" "$odTCDFtextFolder" "$_dlsymsOut"
				if [ -s "$_dlsymsOut" ]; then
					cat "$_dlsymsOut" >> "$_dloadOut"
					printf "\t%-28s : %s (%d)\n" "dlsym" "$_dlsymsOut" $(wc -l "$_dlsymsOut" | cut -d ' ' -f1) >> "$_dloadLog"
					local _dlsymsOutFile=
					while read _dlsymsOutFile; do
						local _dlsymsOutFileP=$(echo "$_dlsymsOutFile" | tr '/' '%')
						if [ -e "$rfsSymsFolder/$_elfDLoadP-$_dlsymsOutFileP.str-symb.addr2line" ]; then
							printf "\t\t%-20s :\t\t%s (%d)\n" "dlsym refs" "$rfsSymsFolder/$_elfDLoadP-$_dlsymsOutFileP.str-symb.addr2line" $(wc -l "$rfsSymsFolder/$_elfDLoadP-$_dlsymsOutFileP.str-symb.addr2line" | cut -d ' ' -f1) >> "$_dloadLog"
						else
							printf "\t\t%-20s :\t\t%s (%d)\n" "dlsym refs" "$rfsSymsFolder/$_elfDLoadP-$_dlsymsOutFileP.str-symb.addr2line" 0 >> "$_dloadLog"
						fi
					done < "$_dlsymsOut"
				else
					printf "\t%-28s : not found\n" "dlsym" >> "$_dloadLog"
					rm -f "$_dlsymsOut"
				fi
			fi

			if [ -s "$_dloadOut" ]; then
				sort -u "$_dloadOut" -o "$_dloadOut"
				printf "\t%-28s : %s (%d)\n" "dloaded" "$_dloadOut" $(wc -l "$_dloadOut" | cut -d ' ' -f1) >> "$_dloadLog"
				cat "$_dloadOut" >> "$_dloadOutAll"

				comm -12 "$_dloadOut" "$rootFS".files.so.dlink-libdld.dlapi.all.short >> "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.next
			else
				printf "\t%-28s : not found\n" "dloaded" >> "$_dloadLog"
			fi

			cat <(echo $_elfDLoad) "$_dloadOut" "$_dlinkOut" >> $rfsDLoadFolder/$_outBase.dload+dlink.all

			echo "$_elfDLoad" >> "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.parsed
			((_iter++))

		done < "$PWD/$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi

		sort -u "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.parsed -o "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.parsed
		sort -u "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.next -o "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.next
		comm -23 "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.next "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.parsed > "$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi

		# cleanup
		rm -f $rfsDLoadFolder/$_outBase.dlink-libdld.dlapi.next
	done

	sort -u "$_dloadOutAll" -o "$_dloadOutAll"
	sort -u "$rfsDLoadFolder/$_outBase".dload+dlink.all -o "$rfsDLoadFolder/$_outBase".dload+dlink.all

	# cleanup
	rm -f "$PWD/$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi.link "$PWD/$rfsDLoadFolder/$_outBase".dlink-libdld.dlapi
	rm -f "$rootFS".files.elf.dlink-libdld.dlapi.all.short "$rootFS".files.so.dlink-libdld.dlapi.all.short
}

# Function: _rootFSElfAnalyzerValidation
# Input:
# $1 - rootFS name
# $2 - rfsElfFolder name
# $3 - process/*/maps file name
# $4 - rt validation folder name
# $5 - exe all file name
# $6 - elf all libdl-api file name
# $7 - log name
# Output:

# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps file : $4 - rt validation folder
#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - log name

function _rootFSElfAnalyzerValidation()
{
	local _rootFS="$1"
	local _rfsElfFolder="$2"
	local _ppmFile="$3"
	local _validFolder="$4"
	local _exeAllFile="$5"
	local _elfDlapiAllFile="$6"
	local _log="$7"

	rm -rf "$_validFolder"
	mkdir -p "$_validFolder"

	local _procPid=
	local _ename=
	local _proc=
	local _perms=
	local _offs=
	local _dev=
	local _inode=
	grep -v "\[vdso\]" "$_ppmFile" | while read _proc _perms _offs _dev _inode _ename
	do
		local _entryPid=$(echo "$_proc" | cut -d '/' -f3)
		local _ename=${_ename#/new_root}
		if [ "$_procPid" != "$_entryPid" ]; then
			# New process parsing with $_entryPid
			_procPid=$_entryPid
			echo "$_ename" > "$_validFolder/pid-$_procPid"
		else
			# Continue parsing same process with _procPid=$_entryPid
			echo "$_ename" >> "$_validFolder/pid-$_procPid"
		fi
	done

	local _file=
	cat /dev/null > "$_rootFS".proc-so-md5sum
	for _file in "$_validFolder"/*
	do
		sort -u "$_file" -o "$_file"
		md5sum "$_file" >> "$_rootFS".proc-so-md5sum
	done

	sort -k1,1 "$_rootFS".proc-so-md5sum -o "$_rootFS".proc-so-md5sum

	# Process redundant/identical (multiple instances of the same process) processes
	local _md5sum=
	while read _md5sum
	do
		_exeName=
		while read _md5 _file
		do
			if [ -z "$_exeName" ]; then
				_exeName=$(comm -12 "$_exeAllFile" "$_file")
				_exeNameP=$(echo "$_exeName" | tr '/' '%')
				if [ ! -e "$_validFolder/$_exeNameP" ]; then
					mv "$_file" "$_validFolder/$_exeNameP"
				else
					mv "$_file" "$_validFolder/$_exeNameP.md5-$_md5"
					_exeNameP="$_exeNameP.md5-$_md5"
				fi
			else
				rm "$_file"
			fi

			cd "$_validFolder"
			ln -sf "$_exeNameP" $(basename "$_file")
			cd - > /dev/null
		done < <(grep "$_md5sum" "$_rootFS".proc-so-md5sum)
	done < <(cut -d ' ' -f1 "$_rootFS".proc-so-md5sum | uniq -d)

	# Process single instance processes
	while read _file
	do
		_exeName=$(comm -12 "$_exeAllFile" "$_file")
		_exeNameP=$(echo "$_exeName" | tr '/' '%')
		if [ -e "$_validFolder/$_exeNameP" ]; then
			mv "$_file" "$_validFolder/$_exeNameP"."$(basename $_file)"
		else
			mv "$_file" "$_validFolder/$_exeNameP"
		fi
	done < <(find "$_validFolder"/ -type f -name "pid-*")

	# create a list of all processes and references (as links) to them
	ls -la "$_validFolder"/ | tr -s ' ' | cut -d ' ' -f9- | tail -n +4 > "$_rootFS".procs+refs

	# create a list of all run-time processes
	grep "\->" "$_rootFS".procs+refs | cut -d ' ' -f3 | sort -u -o "$_rootFS".procs.groups
	comm -23 <(sort "$_rootFS".procs+refs) "$_rootFS".procs.groups > "$_rootFS".procs.rt

	# create a list of all independent run-time processes that can be analyzed
	grep -v "\->" "$_rootFS".procs+refs | sort -o "$_rootFS".procs.analyze

	# create a list of run-time redundant processes not needed for analysis
	cat /dev/null > "$_rootFS".procs.rt-redundant
	grep "\->" "$_rootFS".procs+refs | sort -k3,3 | awk -v file="$_rootFS".procs.rt-redundant '{\
		if (entry == $3) { printf("%s\n", $0) >> file; }; entry=$3;
		}'

	# validate analyzed/independent run-time processes
	cat /dev/null > "$_rootFS".procs.analyze.validated
	cat /dev/null > "$_rootFS".procs.analyze.validated-ident
	cat /dev/null > "$_rootFS".procs.analyze.not-validated

	cat /dev/null > "$_rootFS".procs.analyze.validated.libdl-api
	cat /dev/null > "$_rootFS".procs.analyze.validated-ident.libdl-api
	cat /dev/null > "$_rootFS".procs.analyze.not-validated.libdl-api
	while read _file
	do
		local _fileE=
		if [[ "$_file" == *.md5-* ]]; then
			_fileE=${_file%.md5-*}
		elif [[ "$_file" == *.pid-* ]]; then
			_fileE=${_file%.pid-*}
		else
			_fileE=$_file
		fi
		cat /dev/null > "$_validFolder/$_file".not-validated	# specific to "rt collected" - not-validated
		cat /dev/null > "$_validFolder/$_file".validated	# specific to "elf analyzed" - validated
		cat /dev/null > "$_validFolder/$_file".validated-ident	# common between "elf analyzed" and "rt collected"

		comm "$_rfsElfFolder/$_fileE" "$_validFolder/$_file" | awk -F$'\t' -v base="$_rootFS".procs.analyze -v name="$_validFolder/$_file" '{\
		if (NF == 2) {\
			printf("%s\n", $2) >> name".not-validated"
		} else if (NF == 1) {\
			printf("%s\n", $1) >> name".validated"
		} else {\
			printf("%s\n", $3) >> name".validated-ident"
		}\
		}'

		if [ -s "$_validFolder/$_file".not-validated ]; then
			# specific to "rt collected" - not-validated
			echo "$_file" >> "$_rootFS".procs.analyze.not-validated
			if [ -n "$(comm -12 "$_elfDlapiAllFile" $_rfsElfFolder/$_fileE)" ]; then
				echo "$_file" >> "$_rootFS".procs.analyze.not-validated.libdl-api
			fi
			rm "$_validFolder/$_file".validated "$_validFolder/$_file".validated-ident
		elif [ -s "$_validFolder/$_file".validated ]; then
			# specific to "elf analyzed" - validated
			echo "$_file" >> "$_rootFS".procs.analyze.validated
			if [ -n "$(comm -12 "$_elfDlapiAllFile" $_rfsElfFolder/$_fileE)" ]; then
				echo "$_file" >> "$_rootFS".procs.analyze.validated.libdl-api
			fi
			rm "$_validFolder/$_file".not-validated "$_validFolder/$_file".validated-ident
		else
			# common between "elf analyzed" and "rt collected" - validated identical
			echo "$_file" >> "$_rootFS".procs.analyze.validated-ident
			if [ -n "$(comm -12 "$_elfDlapiAllFile" $_rfsElfFolder/$_fileE)" ]; then
				echo "$_file" >> "$_rootFS".procs.analyze.validated-ident.libdl-api
			fi
			rm "$_validFolder/$_file".not-validated "$_validFolder/$_file".validated
		fi
	done < "$_rootFS".procs.analyze

	printf "%-36s : %5d : %s\n" "/proc/<pid>/maps processes" $(wc -l "$_rootFS".procs.rt | cut -d ' ' -f1) "$_rootFS.procs.rt" | tee -a $_log
	printf "%-36s : %5d : %s\n" "Analyzed / not-redundant processes" $(wc -l "$_rootFS".procs.analyze | cut -d ' ' -f1) "$_rootFS.procs.analyze" | tee -a $_log
	printf "%-36s : %5d : %s\n" "Run-time redundant processes" $(wc -l "$_rootFS".procs.rt-redundant | cut -d ' ' -f1) "$_rootFS.procs.rt-redundant" | tee -a $_log
	printf "%-36s : %5d : %s\n" "Validated identical processes" $(wc -l "$_rootFS".procs.analyze.validated-ident | cut -d ' ' -f1) "$_rootFS.procs.analyze.validated-ident" | tee -a $_log
	printf "%-36s : %5d : %s\n" "Validated processes" $(wc -l "$_rootFS".procs.analyze.validated | cut -d ' ' -f1) "$_rootFS.procs.analyze.validated" | tee -a $_log
	printf "%-36s : %5d : %s\n" "Not validated processes" $(wc -l "$_rootFS".procs.analyze.not-validated | cut -d ' ' -f1) "$_rootFS.procs.analyze.not-validated" | tee -a $_log
	printf "%-36s : %5d : %s\n" "Validated ident processes, dlapi" $(wc -l "$_rootFS".procs.analyze.validated-ident.libdl-api | cut -d ' ' -f1) ""$_rootFS".procs.analyze.validated-ident.libdl-api" | tee -a $_log
	if [ -s "$_rootFS".procs.analyze.validated-ident ] && [ -s "$_rootFS".procs.analyze.validated-ident.libdl-api ]; then
		comm -23 "$_rootFS".procs.analyze.validated-ident "$_rootFS".procs.analyze.validated-ident.libdl-api > "$_rootFS".procs.analyze.validated-ident.not-libdl-api
		if [ -s "$_rootFS".procs.analyze.validated-ident.not-libdl-api ]; then
			printf "%-36s : %5d : %s\n" "Validated ident processes, no dlapi" $(wc -l "$_rootFS".procs.analyze.validated-ident.not-libdl-api | cut -d ' ' -f1) ""$_rootFS".procs.analyze.validated-ident.not-libdl-api" | tee -a $_log
		else
			rm "$_rootFS".procs.analyze.validated-ident.not-libdl-api
		fi
	fi
	printf "%-36s : %5d : %s\n" "Validated processes, dlapi" $(wc -l "$_rootFS".procs.analyze.validated.libdl-api | cut -d ' ' -f1) "$_rootFS".procs.analyze.validated.libdl-api | tee -a $_log
	if [ -s "$_rootFS".procs.analyze.validated ] && [ -s "$_rootFS".procs.analyze.validated.libdl-api ]; then
		comm -23 "$_rootFS".procs.analyze.validated "$_rootFS".procs.analyze.validated.libdl-api > "$_rootFS".procs.analyze.validated.not-libdl-api
		if [ -s "$_rootFS".procs.analyze.validated.not-libdl-api ]; then
			printf "%-36s : %5d : %s\n" "Validated processes, no dlapi" $(wc -l "$_rootFS".procs.analyze.validated.not-libdl-api | cut -d ' ' -f1) "$_rootFS".procs.analyze.validated.not-libdl-api | tee -a $_log
		else
			rm "$_rootFS".procs.analyze.validated.not-libdl-api
		fi
	fi
	printf "%-36s : %5d : %s\n" "Not validated processes, dlapi" $(wc -l "$_rootFS".procs.analyze.not-validated.libdl-api | cut -d ' ' -f1) "$_rootFS".procs.analyze.not-validated.libdl-api | tee -a $_log
	if [ -s "$_rootFS".procs.analyze.not-validated ] && [ -s "$_rootFS".procs.analyze.not-validated.libdl-api ]; then
		comm -23 "$_rootFS".procs.analyze.not-validated "$_rootFS".procs.analyze.not-validated.libdl-api > "$_rootFS".procs.analyze.not-validated.not-libdl-api
		if [ -s "$_rootFS".procs.analyze.not-validated.not-libdl-api ]; then
			printf "%-36s : %5d : %s\n" "Not validated processes, dlapi" $(wc -l "$_rootFS".procs.analyze.not-validated.not-libdl-api | cut -d ' ' -f1) "$_rootFS".procs.analyze.not-validated.not-libdl-api | tee -a $_log
		else
			rm "$_rootFS".procs.analyze.not-validated.not-libdl-api
		fi
	fi

	# Cleanup
	rm -f "$_rootFS".procs.groups "$_rootFS".proc-so-md5sum
}

