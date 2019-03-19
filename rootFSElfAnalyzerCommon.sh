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
md5sumHash="[[:xdigit:]]\{32\}"
md5sumPExt="\.md5-$md5sumHash$"
procPExt="\.pid-[0-9]\+$"

# Regex for the /proc/<pid>/maps file format
procAllMaps_srsRegex='^/proc/.*/maps:[[:xdigit:]]\{8\}-[[:xdigit:]]\{8\} r-xp [[:xdigit:]]\{8\} [[:xdigit:]]\{2\}:[[:xdigit:]]\{2\} [[:digit:]]'

# File extensions for rt-validation service : _rootFSElfAnalyzerValidation
fme_rt="procs.rt"
fme_nonredundant="procs.nonredundant"
fme_nonredundant_si="procs.nonredundant-si"
fme_rt_redundant="procs.rt-redundant"
fme_analyze_validated_ident="procs.analyze.validated-ident"
fme_analyze_validated="procs.analyze.validated"
fme_analyze_not_validated="procs.analyze.not-validated"
fme_analyze_validated_ident_libdl_api="procs.analyze.validated-ident.libdl-api"
fme_analyze_validated_ident_not_libdl_api="procs.analyze.validated-ident.not-libdl-api"
fme_analyze_validated_libdl_api="procs.analyze.validated.libdl-api"
fme_analyze_validated_not_libdl_api="procs.analyze.validated.not-libdl-api"
fme_analyze_not_validated_libdl_api="procs.analyze.not-validated.libdl-api"
fme_analyze_not_validated_not_libdl_api="procs.analyze.not-validated.not-libdl-api"
fme_elf_rt_used="elf.rt-used"
fme_exe_rt_used=$fme_nonredundant_si
fme_so_rt_used="so.rt-used"

fme_not_available_in_ppm="procs.not-available-in-ppm"
fme_procs_analyze="procs.analyze"

# File extension descriptors for rt-validation service : _rootFSElfAnalyzerValidation
declare -A fileMetrics
fileMetrics[$fme_rt]="/proc/<pid>/maps processes"
fileMetrics[$fme_nonredundant]="Analyzed/non-redundant processes"
fileMetrics[$fme_nonredundant_si]="Non-redundant single instance procs"
fileMetrics[$fme_rt_redundant]="Run-time redundant processes"
fileMetrics[$fme_analyze_validated_ident]="Validated identical processes"
fileMetrics[$fme_analyze_validated]="Validated processes"
fileMetrics[$fme_analyze_not_validated]="Not validated processes"
fileMetrics[$fme_analyze_validated_ident_libdl_api]="Validated ident processes, dlapi"
fileMetrics[$fme_analyze_validated_ident_not_libdl_api]="Validated ident processes, no dlapi"
fileMetrics[$fme_analyze_validated_libdl_api]="Validated processes, dlapi"
fileMetrics[$fme_analyze_validated_not_libdl_api]="Validated processes, no dlapi"
fileMetrics[$fme_analyze_not_validated_libdl_api]="Not validated processes, dlapi"
fileMetrics[$fme_analyze_not_validated_not_libdl_api]="Not validated processes, no dlapi"
fileMetrics[$fme_elf_rt_used]="Run-time used elfs"
fileMetrics[$fme_exe_rt_used]="Run-time used execs"
fileMetrics[$fme_so_rt_used]="Run-time used libs"

fileMetrics[$fme_not_available_in_ppm]="Processes not available in -ppm file"

# File extension array for rt-validation service : _rootFSElfAnalyzerValidation
fileMetricsExts="$fme_rt \
$fme_nonredundant \
$fme_nonredundant_si \
$fme_rt_redundant \
$fme_analyze_validated_ident \
$fme_analyze_validated \
$fme_analyze_not_validated \
$fme_analyze_validated_ident_libdl_api \
$fme_analyze_validated_ident_not_libdl_api \
$fme_analyze_validated_libdl_api \
$fme_analyze_validated_not_libdl_api \
$fme_analyze_not_validated_libdl_api \
$fme_analyze_not_validated_not_libdl_api \
$fme_elf_rt_used \
$fme_exe_rt_used \
$fme_so_rt_used\
"

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

# Function: _logFileShort:
# input:
# $1 - file name, file format is in "ls" form
# $2 - file descriptor
# $3 - log name
function _logFileShort()
{
	if [ -s "$1" ]; then
		printf "%-36s : %5d : %s\n" "$2" $(wc -l "$1" | cut -d ' ' -f1) "$(echo "$1" | sed "s:$PWD/::")" | tee -a "$3"
	else
		printf "%-36s : %5d : %s\n" "$2" 0 "$1" | tee -a "$3"
	fi
}

# Function: _ppmFileValid:
# input:
# $1 - proc pid maps file in "grep r-xp /proc/*/maps" format
# $2 - number of lines to validate; all if empty ""
# output:
function _ppmFileValid()
{
	local _ppmf="$1"
	local _nlines="$2"
	local _valid=0
	local _return=$ERR_OBJ_NOT_VALID

	#printf "$FUNCNAME: $_ppmf : $_nlines\n" >> "$name".log
	if [ -s "$_ppmf" ]; then
		if [ -n "$_nlines" ]; then
			if [[ "$_nlines" =~ ^[0-9]+$ ]]; then
				[ -z "$(head -n $_nlines "$_ppmf" | grep -v "$procAllMaps_srsRegex")" ] && _valid=1 && _return=$ERR_NOT_A_ERROR
				#printf "$FUNCNAME: 1: valid = $_valid: return code = $_return\n$(head -n $_nlines "$_ppmf" | grep -v "$procAllMaps_srsRegex")\n" >> "$name".log
			fi
		else
			[ -z "$(grep -v "$procAllMaps_srsRegex" "$_ppmf")" ] && _valid=1 && _return=$ERR_NOT_A_ERROR
			#printf "$FUNCNAME: 2: valid = $_valid: return code = $_return\n$(grep -v "$procAllMaps_srsRegex" "$_ppmf")\n" >> "$name".log
		fi
	fi
	#printf "$FUNCNAME: 3: valid = $_valid: return code = $_return\n" >> "$name".log
	echo $_valid
	return $_return
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

# Function: _buildElfDFUNDtTable:
# input:
# $1 - rootFS folder
# $2 - an elf object name
# $3 - an output file name
# Use cases:
#_rootFSDLoadElfAnalyzer:
#_rootFSNssSingleElfAnalyzer:	
function _buildElfDFUNDtTable()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _out="$3"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "out" "$_out"
	"$objdump" -TC "$_rfsFolder/$_elf" | grep "^[[:xdigit:]]\{8\}.*\{6\}DF \*UND\*" | cut -f2 | cut -b23- | sed 's/^[0-9]* //;/^$/d'| sort -u -o "$_out"
}

# Function: _mkWFolder:
# input:
# $1 - work folder name to make/remake : removes the requested folder if safe to remove
#	1) validate removal if safe (doesn't remove the current folder or any parent's)
#	2) remove it if exists & allowed and make the new one OR make the new one if doen't exist
# output:
# std out - the new folder name
function _mkWFolder()
{
	local _wFolder="${1%/}"
	local _wFolderPfx=.

	if [ -n "$_wFolder" ]; then
		_wFolderPfx=$(readlink -e "$_wFolder")
		#echo "_wFolderPfx = $_wFolderPfx" >> "$name".log
		if [ -n "$_wFolderPfx" ] && [[ ! $PWD = $_wFolderPfx* ]]; then
			_wFolderPfx="${_wFolderPfx#$PWD/}"
			#echo "rm -rf $_wFolderPfx" >> "$name".log
			rm -rf "$_wFolderPfx"
			_err_=$?
			if [ $_err_ != 0 ]; then
				echo "$name# ERROR=$_err_ executing \"rm -rf $_wFolderPfx\" : Exit." | tee -a "$name".log
				exit $ERR_OBJ_NOT_VALID
			fi
			mkdir -p "$_wFolderPfx"
			#echo "mkdir -p $_wFolderPfx" >> "$name".log
		elif [ -z "$_wFolderPfx" ]; then
			_wFolderPfx="$_wFolder"
			#echo "mkdir -p $_wFolderPfx" >> "$name".log
			mkdir -p "$_wFolderPfx"
		fi
	fi
	echo "$_wFolderPfx"
}

# Function: _getElfDbgPath
# Input:
# $1 - rootFS folder
# $2 - target ELF filename
# $3 - rootFS dbg folder
# $4 - output file name - needed to log "missing" status in "$_out".dbg-missing file
# output:
# std out - Elf's dbg path if $3 is set, otherwise Elf's path
function _getElfDbgPath()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _rdbgFolder="$3"
	local _out="$4"

	local _elfPath=
	if [ -n "$_rdbgFolder" ]; then
		_elfPath="$_rdbgFolder"/$(dirname "$_elf")/.debug/$(basename "$_elf")
		if [ ! -e "$_elfPath" ]; then
			[ -n "$_out" ] && echo "$_elfPath" >> "$_out".dbg-missing
			_elfPath="$_rfsFolder/$_elf"
		fi
	else
		_elfPath="$_rfsFolder/$_elf"
	fi
	echo "$_elfPath"
}

# Function: _sraddr2line
# Input:
# $1 - rootFS folder
# $2 - target ELF filename
# $3 - symbol reference list file to analyze; all symbols are analyzed if the name is empty
# $4 - output file name
# $5 - rootFS dbg folder
# $6 - an optional service type - nss, libdlapi or none if empty
# $7 - an optional symbol name
# Output:
# "symbol name - source code location" structured file
# "symbol name - source code location" log =<output file name>.log

#_sraddr2line "$rfsFolder" "$elf" "$symList" "$odTCDFUNDFolder/$elfBase" "$rdbgFolder"

function _sraddr2line()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _symList="$3"
	local _out="$4"
	local _rdbgFolder="$5"
	local _service="$6"
	local _symb="$7"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n\n" \
	#"$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "symList" "$_symList" "out" "$_out" "rdbgFolder" "$_rdbgFolder" "service" "$_service" "symb" "$_symb" >> "$name".log

	# Build a symbol file if it's not built
	if [ ! -e "$_out".gentry.all ]; then
		sed '1,/Global entries:/d' <(readelf -AW "$_rfsFolder/$_elf" | c++filt) | grep " FUNC " | sed '1d;s/^ .//;/^$/d' | \
			sed 's/ \+/ /g;s/ /\t/1;s/ /\t/1;s/ /\t/1;s/ /\t/1;s/ /\t/1;s/ /\t/1' | sort -t$'\t' -k7,7 -o "$_out".gentry.all
	fi

	if [ -n "$_symb" ] && [ -e "$PWD/$_out$_service".user."$_symb" ]; then
		#echo "skipping $PWD/$_out$_service.user."$_symb >> "$name".log
		return
	elif [ -z "$_symList" ] && [ -z "$_symb" ] && [ -e "$PWD/$_out".gentry.all ]; then
		#echo "skipping $PWD/$_out.gentry.all" >> "$name".log
		return
	fi

	if [ -n "$_symList" ]; then
		join -t$'\t' -1 1 -2 7 <(sort "$_symList") "$_out".gentry.all -o 2.1,2.2,2.3,2.4,2.5,2.6,2.7 > "$_out$_service".gentry.user
	elif [ -n "$_symb" ]; then
		join -t$'\t' -1 1 -2 7 <(echo "$_symb") "$_out".gentry.all -o 2.1,2.2,2.3,2.4,2.5,2.6,2.7 > "$_out$_service".user."$_symb"
		ln -sf "$PWD/$_out$_service".user."$_symb" "$_out$_service".gentry.user
	else
		ln -sf "$PWD/$_out".gentry.all "$_out$_service".gentry.user
	fi

	# Disassemble the elf
	if [ ! -e "$_out".dC ]; then
		"$objdump" -dC "$_rfsFolder/$_elf" > "$_out".dC
	fi

	# Find source code locations of symbol refs; init a path from a dbg folder if set
	local _elfPath=$(_getElfDbgPath "$_rfsFolder" "$_elf" "$_rdbgFolder" "$_out")
	#echo "_elfPath = $_elfPath"

	while IFS=$'\t' read _addr _access _initial _symval _type _ndx _name
	do
		grep -w -- "$_access" "$_out".dC | cut -f1 | cut -d ':' -f1 | addr2line -Cpfa -e "$_elfPath" | cut -d ' ' -f2- > "$_out.usr.$_name"
	done < "$_out$_service".gentry.user

	rm -f "$_out$_service".gentry.user
}

# Input:
# $1 - rootFS folder
# $2 - a list of target (full path) ELF filenames
# $3 - symbol list file; all symbols are analyzed if the $3 name or the symbol $7 name is empty 
# $4 - output file folder
# $5 - output file postfix
# $6 - rootFS dbg folder
# $7 - service type
# $8 - symbol name
# Output:

# Use cases:
#_rootFSDLinkElfAnalyzer: _elfSymRefSources "$_rfsFolder" "$_out".libdl "$odTCDFtextFolder"/libdlApi "$rfsLibdlFolder" ".dlink.libdl" "$_rdbgFolder" ".libdl"
#_rootFSDLoadElfAnalyzer: _elfSymRefSources "$_rfsFolder" "$_outElfBase".file "$_outElfBase".sym "$odTCDFUNDFolder/" "" "$_rdbgFolder" ".libdl"
function _elfSymRefSources
{
	local _rfsFolder="$1"
	local _elfList="$2"
	local _symList="$3"
	local _out="$4"
	local _pfx="$5"
	local _rdbgFolder="$6"
	local _service="$7"
	local _symb="$8"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" \
	#"$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elfList" "$_elfList" "symList" "$_symList" "out" "$_out" "pfx" "$_pfx" "rdbgFolder" "$_rdbgFolder" "service" "$_service" "symb" "$_symb"

	local _elf=
	while read _elf
	do
		local _elfP=$(echo "$_elf" | tr '/' '%')
		local _log="$_out/$_elfP$_pfx".log
		local _none=true

		#if [ -s "$odTCDFUNDFolder/$_elfP$_service".gentry.user ]; then
		#	printf "%s: skipping %s\n" "$FUNCNAME" "$odTCDFUNDFolder/$_elfP$_service".gentry.user >> "$name".log
		#	continue
		#fi
		_sraddr2line "$_rfsFolder" "$_elf" "$_symList" "$odTCDFUNDFolder/$_elfP" "$_rdbgFolder" "$_service" "$_symb"

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
		elif [ -n "$_symb" ]; then
			if [ -s "$odTCDFUNDFolder/$_elfP".usr."$_symb" ]; then
				printf "\t%s:\n" "$_symb" >> "$_log".tmp
				sed 's/^/\t\t/' "$odTCDFUNDFolder/$_elfP".usr."$_symb" >> "$_log".tmp
				_none=false
			else
				printf "\t%s:\tnone\n" "$_symb" >> "$_log".tmp
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


# Function: _logElfSymRefSources
# $1 - rfsf	-a rootFS folder
# $2 - elf	-an elf
# $3 - symb	-a symbol
# $4 - outb	-an outbase
# $5 - outf	-an output folder
# $6 - log	-an output log file
# $7 - dbg	-a rootFS dbg folder
# $8 - service	-a service type

function _logElfSymRefSources()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _symb="$3"
	local _outb="$4"
	local _outf="$5"
	local _log="$6"
	local _rdbgFolder="$7"
	local _serv="$8"

	echo "$_elf" > "$_outb".file
	# _elfSymRefSources "rfsFolder" "elf list"          "symbol list"      "out folder"      "postfix" "dbg folder" "service" "symb"
	_elfSymRefSources "$_rfsFolder" "$_outb".file "" "$_outf/" "" "$_rdbgFolder" "$_serv" "$_symb"
	if [ -e "$_outf/$_outb".usr.$_symb ]; then
		printf "\t\t%-20s :\t\t%s (%d)\n" "$_symb refs" "$_outf/$_outb".usr.$_symb $(wc -l "$_outf/$_outb".usr.$_symb | cut -d ' ' -f1) >> "$_log"
	else
		printf "\t\t%-20s :\t\t%s (%d)\n" "$_symb refs" "$_outf/$_outb".usr.$_symb 0 >> "$_log"
	fi

	rm -f "$_outb".*
}

# Function: _soRefedByApp
# $1 - folder	-a folder with a list of apps and dependent dynamically linked libraries, as .dlink
# $2 - filename	-a list of shared libraries to analyze
# $3 - logname	-an output log file
# $4 - ext	-an optional file extension in the folder to look for; all files are analyzed if empty
# _soRefedByApp $_folder $_soList $_log
function _soRefedByApp()
{
	local _folder="$1"
	local _soList="$2"
	local _log="$3"
	local _ext="$4"

	cat /dev/null > "$_log"
	if [ -s "$_soList" ]; then
		local _elf=
		local _refed=
		local _byte=${#_folder}
		_byte=$((_byte+2))
		while read _elf
		do
			grep -H "^$_elf$" "$_folder"/*"$_ext" | cut -d ":"  -f1 | cut -b$_byte- | tr '%' '/' | sort > "$_soList".elf
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
# $7 - rootFS dbg folder
# $8 - build elf's dlink iter log, if not empty
# Output:
# ELF file dynamically linked library list = <output file name> = <$4 name>

# _rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name : $5 - work folder : $6 - libdl deps : $7 - rdbg folder : $8 - iter log

function _rootFSDLinkElfAnalyzer()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _elfRefs="$3"
	local _out="$4"
	local _wFolder="$5"
	local _libdl="$6"
	local _rdbgFolder="$7"
	local _iterLog="$8"

	[ -z "$_wFolder" ] && _wFolder=.
	local _elfP="$_wFolder/$(basename "$_out")"
	local _elfPwdP="$PWD/$_elfP"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" \
	#"$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "elfRefs" "$_elfRefs" "out" "$_out" "wFolder" "$_wFolder" "rdbgFolder" "$_rdbgFolder" "iterLog" "$_iterLog"

	. "$path"/errorCommon.sh
	setTrapHandlerWithParams _rootFSDLinkElfAnalyzer_cleanup_on_signal 6 0 1 2 3 6 15 "$_elfP" "$_elfPwdP" "$_wFolder" "$_out"

	[ -n "$_iterLog" ] && cat /dev/null > "$_iterLog"

	if [ -n "$_elf" ]; then
		"$objdump" -x "$_rfsFolder/$_elf" | grep "NEEDED" | tr -s ' ' | cut -d ' ' -f3 > "$_elfP".elfrefs
	else
		if [ ! -s "$_elfRefs" ]; then
			printf "%s: ERROR: File $_elfRefs doesn't exist or NULL! Exit\n" "$FUNCNAME" "$_elfRefs" | tee "$_out".error
			return $ERR_OBJ_NOT_VALID
		fi
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
				# _elfSymRefSources "rfsFolder" "elf list"    "symbol list"                "out folder"      "postfix"      "dbg folder"   "service"
				_elfSymRefSources "$_rfsFolder" "$_out".libdl "$odTCDFtextFolder"/libdlApi "$rfsLibdlFolder" ".dlink.libdl" "$_rdbgFolder" ".libdl"
			else
				printf "skipping $rfsLibdlFolder/$_out.libdl.log generation !\n" | tee -a "$name".log
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
# $2 - rootFS dbg folder
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
	local _rdbgFolder="$2"

	#printf "%s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "rdbgFolder" "$_rdbgFolder"

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
				_buildElfDFtextTable $_rfsFolder "$_libT" "$odTCDFtextFolder/$_libP".odTC-DFtext
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
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name
		# : $5 - work folder : $6 - libdl deps : $7 - rdbg folder : $8 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "$_elfDLink" "" "$rfsNssFolder/$_outBase" "" "" "$_rdbgFolder" ""
	done < "$rfsNssFolder"/nss.short
}

# Function: _rootFSNssSingleElfAnalyzer
# Input:
# $1 - rootFS folder
# $2 - target ELF
# $3 - an output file name base
# $4 - rootFS dbg folder
# $5 - a log
# Output:
# ELF file NSS library list = $rfsNssFolder/<output file base name>.dload = $rfsNssFolder/<$4 base name>
# ELF file NSS library list log = $rfsNssFolder/<output file base name>.nss.log

function _rootFSNssSingleElfAnalyzer()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _out="$3"
	local _rdbgFolder="$4"
	local _nssLog="$5"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" \
	#"$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "out" "$_out" "nssLog" "$_nssLog" "rdbgFolder" "$_rdbgFolder"

	local _elfP=$(echo $_elf | tr '/' '%')
	local _outBase="$(basename "$_out")"
	local _nssOut="$rfsNssFolder/$_outBase".tmp

	# build a list of elf's UND symbols (if not built) and compare it with nss api
	if [ ! -s "$odTCDFUNDFolder/$_elfP".odTC-DFUND ]; then
		_buildElfDFUNDtTable "$_rfsFolder" "$_elf" "$odTCDFUNDFolder/$_elfP".odTC-DFUND
	fi
	
	cat /dev/null > "$_nssOut"
	local _nss_service_api=
	local _none=true
	while read _nss_service_api
	do
		comm -12 "$rfsNssFolder/$_nss_service_api" "$odTCDFUNDFolder/$_elfP".odTC-DFUND > "$rfsNssFolder/$_elfP.$_nss_service_api.deps"
		if [ -s "$rfsNssFolder/$_elfP.$_nss_service_api.deps" ]; then
			printf "\t%s\t:\n" "$_nss_service_api" >> "$_nssOut"
			#_sraddr2line "$rfsFolder" "$elf" "$symList" "$odTCDFUNDFolder/$elfBase" "$_rdbgFolder" "service" "symb"
			_sraddr2line "$_rfsFolder" "$_elf" "$rfsNssFolder/$_elfP.$_nss_service_api.deps" "$odTCDFUNDFolder/$_outBase" "$_rdbgFolder" ".nss" ""
			local _line=
			while read _line
			do
				if [ -s "$odTCDFUNDFolder/$_outBase.usr.$_line" ]; then
					printf "\t\t%-18s\t:\n" "$_line" >> "$_nssOut"
					sed 's/^/\t\t\t/' "$odTCDFUNDFolder/$_outBase.usr.$_line" >> "$_nssOut"
				else
					printf "\t\t%-18s\t: not found\n" "$_line" >> "$_nssOut"
				fi
			done < "$rfsNssFolder/$_elfP.$_nss_service_api.deps"
			local _nss_service_lib=$(echo "$_nss_service_api" | tr '%' '/')
			echo ${_nss_service_lib%.api} >> "$_out".nss
			_none=false
		else
			printf "\t%s\t: none\n" "$_nss_service_api" >> "$_nssOut"
			rm "$rfsNssFolder/$_elfP.$_nss_service_api.deps"
		fi
	done < "$rfsNssFolder"/nss.api
	if [ $_none = "false" ]; then
		printf "%-37s\t:\n" "$_elf" >> "$_nssLog"
		cat "$_nssOut" >> "$_nssLog"
	else
		printf "%-37s\t: none\n" "$_elf" >> "$_nssLog"
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
# $4 - rdbg folder
# Output:
# ELF file NSS library list = $rfsNssFolder/<output file base name>.dload = $rfsNssFolder/<$4 base name>
# ELF file NSS library list log = $rfsNssFolder/<output file base name>.nss.log

# _rootFSNssElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name : $3 - output file name base : $4 - rdbg folder

function _rootFSNssElfAnalyzer()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _out="$3"
	local _rdbgFolder="$4"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "out" "$_out" "rdbgFolder" "$_rdbgFolder"

	local _outBase="$(basename $_out)"
	local _nssOut="$rfsNssFolder/$_outBase".nss
	local _nssLog="$_nssOut".log

	if [ ! -s "$rfsNssFolder"/nss.api ]; then
		# if "$rfsNssFolder"/nss.api is of zero length, attempt to build it again and return if it's of zero length again
		_rootFSBuildNssCache "$rfsFolder" "$_rdbgFolder"
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
	_rootFSNssSingleElfAnalyzer "$_rfsFolder" "$_elf" "$rfsNssFolder/$_outBase" "$_rdbgFolder" "$_nssLog"
	# The result is in "$_nssOut"="$rfsNssFolder/$_outBase".nss if appilcable

	# Build an so DLink list if not available
	if [ ! -e "$rfsDLinkFolder/$_outBase".dlink ]; then
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name
		# : $5 - work folder : $6 - libdl deps : $7 - rdbg folder : $8 - iter log
		_rootFSDLinkElfAnalyzer "$rfsFolder" "$_elf" "" "$rfsDLinkFolder/$_outBase".dlink "" "" "$_rdbgFolder" ""
	fi

	# build lists of symbols (if not built) of all so in the DLink list and compare them with nss api
	local _elfDLink=
	local _outBaseDLink=
	while read _elfDLink
	do
		_outBaseDLink="$(basename $(echo $_elfDLink | tr '/' '%'))"
		_rootFSNssSingleElfAnalyzer "$_rfsFolder" "$_elfDLink" "$rfsNssFolder/$_outBaseDLink" "$_rdbgFolder" "$_nssLog"
		# The result is in "$_nssOut"="$rfsNssFolder/$_outBaseDLink".nss if appilcable
		[ -s "$rfsNssFolder/$_outBaseDLink".nss ] && cat "$rfsNssFolder/$_outBaseDLink".nss >> "$_nssOut"
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
# $6 - rdbg folder

function _rootFSSymbsElfAnalyzer()
{
	local _elf="$1"
	local _libs="$2"
	local _wFolder="$3"
	local _dsymFolder="$4"
	local _out="$5"
	local _rdbgFolder="$6"
	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" "$FUNCNAME:" "elf" "$_elf" "libs" "$(cat $_libs | tr '\n' ' ')" "wFolder" "$_wFolder" "dlsymsFolder"  "$_dsymFolder" "out" "$_out" 

	cat /dev/null > "$_out".log
	_elfP=$(echo "$_elf" | tr '/' '%')
	local _soFile=
	while read _soFile
	do
		_soFileP=$(echo "$_soFile" | tr '/' '%')
		join -t$'\t' -1 1 -2 2 "$_wFolder/$_elfP".vccpp "$_dsymFolder/$_soFileP".odTC-DFtext -o 2.1,2.2 | grep -v "^[[:xdigit:]]\{8\}"$'\t'"main$" > "$_wFolder/$_elfP-$_soFileP".str-symb
		if [ -s "$_wFolder/$_elfP-$_soFileP".str-symb ]; then
			echo "$_soFile:" >> "$_out".log
			cut -f1 "$_wFolder/$_elfP-$_soFileP".str-symb > "$_wFolder/$_elfP-$_soFileP".str-symb.addrs

			# Find source code locations of symbol refs, init a path from a dbg folder if set
			local _elfPath=$(_getElfDbgPath "$rfsFolder" "$_elf" "$_rdbgFolder" "$_out")

			addr2line -Cpfa -e "$_elfPath" @"$_wFolder/$_elfP-$_soFileP".str-symb.addrs >"$_wFolder/$_elfP-$_soFileP".str-symb.addr2line
			sed 's/^/\t/' <(cut -f2- "$_wFolder/$_elfP-$_soFileP".str-symb.addr2line) >> "$_out".log
			echo "$_soFile" >> "$_out" # matched libs

#			rm "$_wFolder/$_elfP-$_soFileP".str-symb.addrs "$_wFolder/$_elfP-$_soFileP".str-symb
#		else
#			rm -f "$_wFolder/$_elfP-$_soFileP".str-symb
		fi
		rm -f "$_wFolder/$_elfP-$_soFileP".str-symb
	done < "$_libs"
}


# Function: _rootFSDLoadElfAnalyzer
# Input:
# $1 - rootFS folder
# $2 - target ELF or ELF file ref name
# $3 - an output file name
# $4 - work folder
# $5 - rdbg folder
# $6 - user validation so "set" list

# Output:
# ELF file dynamically loaded library list = $rfsDLoadFolder/<output file base name>.dload = $rfsDLoadFolder/<$4 base name>
# ELF file dynamically loaded library list log = $rfsDLoadFolder/<output file base name>.dload.log

# _rootFSDLoadElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name : $3 - output file name : $4 - work folder : $5 - rootFS dbg folder : $6 - uv so set

function _rootFSDLoadElfAnalyzer()
{
	local _rfsFolder="$1"
	local _elf="$2"
	local _out="$3"
	local _wFolder="$4"
	local _rdbgFolder="$5"
	local _uvsoset="$6"

	local _outBase="$(basename "$_out")"
	local _dlinkOutBase="$rfsDLinkFolder/$_outBase".dlink
	local _dlopenOut="$rfsDLoadFolder/$_outBase".dlopen
	local _dlsymsOut="$rfsSymsFolder/$_outBase".dlsym
	local _dloadOutAll="$rfsDLoadFolder/$_outBase".dload.all
	local _symbsBase="$rfsSymsFolder/$_outBase"
	local _dloadLog="$rfsDLoadFolder/$_outBase".dload.log

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" \
	#"$FUNCNAME:" "rfsFolder" "$_rfsFolder" "elf" "$_elf" "out" "$_out" "wFolder" "$_wFolder" "rdbgFolder" "$_rdbgFolder" | tee -a "$name".log
	#printf "%-12s = %s\n%-12s = %s\n%-12s = %s\n" "dlinkOutBase" "$_dlinkOutBase" "dloadOutAll" "$_dloadOutAll" "dlsymsOut" "$_dlsymsOut" | tee -a "$name".log

	cat /dev/null > "$_dloadLog"
	cat /dev/null > "$_dlsymsOut"
	cat /dev/null > "$_dloadOutAll"

	if [ ! -s "$_dlinkOutBase" ]; then
		#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name
		# : $5 - work folder : $6 - libdl deps : $7 - rdbg folder : $8 - iter log
		_rootFSDLinkElfAnalyzer "$_rfsFolder" "$_elf" "" "$_dlinkOutBase" "$_wFolder" "" "$_rdbgFolder" ""
	fi
	
	#if an elf, check dlink list for libdl & exit if not there.
	if [ -z "$(comm -12 "$_dlinkOutBase" <(echo $libdlDefault))" ]; then
		printf "%-36s : %s\n" "$_elf" "not libdl dlinked" >> "$_dloadLog"
		return
	fi

	if [ ! -s "$rootFS".files.elf.dlapi.all ]; then
		echo "$name# ERROR : \""$rootFS".files.elf.dlapi.all\" is empty or not found! Exit." | tee -a "$name".log
		exit $ERR_OBJ_NOT_VALID
	fi

	[ ! -e "$rootFS".files.elf.dlapi.all.short ] && fllo2sh "$rootFS".files.elf.dlapi.all "$rootFS".files.elf.dlapi.all.short
	[ ! -e "$rootFS".files.exe.all.short ] && fllo2sh "$rootFS".files.exe.all "$rootFS".files.exe.all.short
	[ ! -e "$rootFS".files.so.all.short ] && fllo2sh "$rootFS".files.so.all "$rootFS".files.so.all.short

	# create a list of dlapi dependent libs and an exe
	cat /dev/null > "$rfsDLoadFolder/$_outBase".dlink.dlapi
	comm -1 "$rootFS".files.elf.dlapi.all.short <(sort <(cat "$_dlinkOutBase" <(echo "$_elf"))) | awk -F'\t' -v base="$rfsDLoadFolder/$_outBase" '{\
	if (NF == 2) {\
		printf("%s\n", $2) > base".dlink.dlapi"
	} else if (NF == 1) {\
		printf("%-36s : dlapi =\n", $1) > base".dload.log"
	}\
	}'

	ln -sf "$PWD/$rfsDLoadFolder/$_outBase".dlink.dlapi "$rfsDLoadFolder/$_outBase".dlink.dlapi.link

	local _iter=1
	cat /dev/null > "$rfsDLoadFolder/$_outBase".dload+dlink.all
	cat /dev/null > "$rfsDLoadFolder/$_outBase".dlink.dlapi.parsed
	while [ -s "$rfsDLoadFolder/$_outBase".dlink.dlapi.link ]
	do
		local _elfDLoad=
		cat /dev/null > "$rfsDLoadFolder/$_outBase".dlink.dlapi.next
		while read _elfDLoad
		do
			if [ -n "$_uvsoset" ] && [ -s "$_uvsoset" ] && [ -n "$(comm -12 "$_uvsoset" <(echo "$_elfDLoad"))" ]; then
				printf "\t%-2d: elfDLoad = %s skipped\n" "$_iter" "$_elfDLoad" | tee -a "$name".log
				continue
			fi

			printf "\t%-2d: elfDLoad = %s\n" "$_iter" "$_elfDLoad" | tee -a "$name".log
			local _elfDLoadP=$(echo $_elfDLoad | tr '/' '%')
			#[ -e $rfsDLoadFolder/$_elfDLoadP.dload ] && continue
			local _outElfBase="$(basename "$_elfDLoadP")"

			_dloadOut="$rfsDLoadFolder/$_outElfBase".dload
			_dlopenOut="$rfsDLoadFolder/$_outElfBase".dlopen
			if [ -n "$(grep ^$_elfDLoad$ "$rootFS".files.exe.all.short)" ]; then
				_dlinkOut="$rfsDLinkFolder/$_outElfBase".dlink
			else
				_dlinkOut="$rfsDLinkUnrefedSoFolder/$_outElfBase".dlink
			fi
			_dlsymsOut="$rfsSymsFolder/$_outElfBase".dlsym
			_symbsBase="$rfsSymsFolder/$_outElfBase"

			#printf "%-12s = %s\n%-12s = %s\n%-12s = %s\n" "dlinkOut" "$_dlinkOut" "dloadOut" "$_dloadOut" "dlsymsOut" "$_dlsymsOut" | tee -a "$name".log

			cat /dev/null > "$_dloadOut"
			cat /dev/null > "$_dlsymsOut"

			# build elf's list of UND symbols if not built
			if [ ! -s "$odTCDFUNDFolder/$_outElfBase".odTC-DFUND ]; then
				_buildElfDFUNDtTable "$_rfsFolder" "$_elfDLoad" "$odTCDFUNDFolder/$_outElfBase".odTC-DFUND
			fi

			# Identify an elf's obj dependencies on $libdlDefault api
			libdlApi="$(comm -12 <(cut -f2- "$odTCDFtextFolder/$libdlDefaultP".odTC-DFtext) "$odTCDFUNDFolder/$_outElfBase".odTC-DFUND)"
			if [ -z "${libdlApi}" ]; then
				#printf "%-36s : dlapi =\n" "$_elfDLoad" >> "$_dloadLog"
				continue
			fi

			printf "%-36s : dlapi = %s\n" "$_elfDLoad" "$(echo "$libdlApi" | tr '\n' ' ')" >> "$_dloadLog"

			if [[ "$libdlApi" == *dlopen* ]] && [ ! -e "$_symbsBase".str-so ]; then
				# 1. Find a list of shared objects in strings,
				strings "$_rfsFolder/$_elfDLoad" | grep "\.so" | sort -u -o "$_symbsBase".str-so
			fi
			if [[ "$libdlApi" == *dlsym* ]] && [ ! -e "$_symbsBase".vccpp ]; then
				# 1. Find a list of valid c/cpp identifiers in strings,
				strings "$_rfsFolder/$_elfDLoad" | grep "^[a-zA-Z_][a-zA-Z0-9_]*$" | sort -u -o "$_symbsBase".vccpp
			fi

			if [ ! -s "$_dlinkOut" ]; then
				#printf "dlink %s doesn't exist\n" "$_dlinkOut" >> "$name".log
				#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name
				# : $5 - work folder : $6 - libdl deps : $7 - rdbg folder : $8 - iter log
				_rootFSDLinkElfAnalyzer "$_rfsFolder" "$_elfDLoad" "" "$_dlinkOut" "$_wFolder" "" "$_rdbgFolder" ""
			#else
				#printf "dlink %s exists\n" " $_dlinkOut" >> "$name".log
			fi

			if [[ "$libdlApi" == *dlopen* ]]; then
				#_rootFSDLinkElfAnalyzer : $1 - rootFS folder : $2 - target ELF file name or "" : $3 - "empty" or ELF's refs: $4 - output file name
				# : $5 - work folder : $6 - libdl deps : $7 - rdbg folder : $8 - iter log
				_rootFSDLinkElfAnalyzer "$_rfsFolder" "$_elfDLoad" "$_symbsBase".str-so "$_symbsBase".str-so.dlink "$_wFolder" "libdl" "$_rdbgFolder" ""

				# 2. remove <this> dlapi elf and compare the result with a list of all libdl api/libdld libs (if available) to find libdl api libs only
				comm -12 <(comm -23 "$_symbsBase".str-so.dlink <(echo "$_elfDLoad")) "$rootFS".files.elf.dlapi.all.short > "$_dlopenOut"

				if [ -s "$_dlopenOut" ]; then
					cat "$_dlopenOut" >> "$_dloadOut"
					printf "\t%-28s : %s (%d)\n" "dlopen libs" "$_dlopenOut" $(wc -l "$_dlopenOut" | cut -d ' ' -f1) >> "$_dloadLog"
				else
					printf "\t%-28s : not found\n" "dlopen libs" >> "$_dloadLog"
					rm -f "$_dlopenOut"
				fi

				_logElfSymRefSources "$_rfsFolder" "$_elfDLoad" "dlopen" "$_outElfBase" "$odTCDFUNDFolder" "$_dloadLog" "$_rdbgFolder" ".libdl"
			fi

			if [[ "$libdlApi" == *dlsym* ]]; then
				# Find a list of shared objects that have strings matching valid c/cpp identifiers/symbols
				#_rootFSSymbsElfAnalyzer : $1 - elf : $2 - libs list to analyze : $3 - analysis folder : $4 - dyn symbol table folder : $5 - out file name : $6 - rdbg folder
				# Remove exe's dlink, <this> lib's dlink and this lib libraries from analysis
				comm -23 "$rootFS".files.so.all.short <(sort -u "$_dlinkOutBase" "$_dlinkOut" <(echo "$_elfDLoad")) > "$_symbsBase".libs
				_rootFSSymbsElfAnalyzer "$_elfDLoad" "$_symbsBase".libs "$rfsSymsFolder" "$odTCDFtextFolder" "$_dlsymsOut" "$_rdbgFolder"
				if [ -s "$_dlsymsOut" ]; then
					cat "$_dlsymsOut" >> "$_dloadOut"
					printf "\t%-28s : %s (%d)\n" "dlsym libs" "$_dlsymsOut" $(wc -l "$_dlsymsOut" | cut -d ' ' -f1) >> "$_dloadLog"
				else
					printf "\t%-28s : not found\n" "dlsym libs" >> "$_dloadLog"
					rm -f "$_dlsymsOut"
				fi
				rm "$_symbsBase".libs

				_logElfSymRefSources "$_rfsFolder" "$_elfDLoad" "dlsym" "$_outElfBase" "$odTCDFUNDFolder" "$_dloadLog" "$_rdbgFolder" ".libdl"

				if [ -s "$_dlsymsOut" ]; then
					local _dlsymsOutFile=
					while read _dlsymsOutFile; do
						local _dlsymsOutFileP=$(echo "$_dlsymsOutFile" | tr '/' '%')
						if [ -e "$rfsSymsFolder/$_elfDLoadP-$_dlsymsOutFileP.str-symb.addr2line" ]; then
							printf "\t\t%-20s :\t\t%s (%d)\n" "dlsym symb matches" "$rfsSymsFolder/$_elfDLoadP-$_dlsymsOutFileP.str-symb.addr2line" \
							$(wc -l "$rfsSymsFolder/$_elfDLoadP-$_dlsymsOutFileP.str-symb.addr2line" | cut -d ' ' -f1) >> "$_dloadLog"
						else
							printf "\t\t%-20s :\t\t%s (%d)\n" "dlsym symb matches" "$rfsSymsFolder/$_elfDLoadP-$_dlsymsOutFileP.str-symb.addr2line" 0 >> "$_dloadLog"
						fi
					done < "$_dlsymsOut"
				else
					rm -f "$_dlsymsOut"
				fi
			fi

			if [ -s "$_dloadOut" ]; then
				sort -u "$_dloadOut" -o "$_dloadOut"
				printf "\t%-28s : %s (%d)\n" "dloaded libs" "$_dloadOut" $(wc -l "$_dloadOut" | cut -d ' ' -f1) >> "$_dloadLog"
				cat "$_dloadOut" >> "$_dloadOutAll"

				comm -12 "$_dloadOut" "$rootFS".files.elf.dlapi.all.short >> "$rfsDLoadFolder/$_outBase".dlink.dlapi.next
			else
				printf "\t%-28s : not found\n" "dloaded libs" >> "$_dloadLog"
			fi

			cat <(echo $_elfDLoad) "$_dloadOut" "$_dlinkOut" >> $rfsDLoadFolder/$_outBase.dload+dlink.all

			echo "$_elfDLoad" >> "$rfsDLoadFolder/$_outBase".dlink.dlapi.parsed
			((_iter++))

		done < "$PWD/$rfsDLoadFolder/$_outBase".dlink.dlapi

		sort -u "$rfsDLoadFolder/$_outBase".dlink.dlapi.parsed -o "$rfsDLoadFolder/$_outBase".dlink.dlapi.parsed
		sort -u "$rfsDLoadFolder/$_outBase".dlink.dlapi.next -o "$rfsDLoadFolder/$_outBase".dlink.dlapi.next
		comm -23 "$rfsDLoadFolder/$_outBase".dlink.dlapi.next "$rfsDLoadFolder/$_outBase".dlink.dlapi.parsed > "$rfsDLoadFolder/$_outBase".dlink.dlapi

		# cleanup
		rm -f $rfsDLoadFolder/$_outBase.dlink.dlapi.next
	done

	sort -u "$_dloadOutAll" -o "$_dloadOutAll"
	sort -u "$rfsDLoadFolder/$_outBase".dload+dlink.all -o "$rfsDLoadFolder/$_outBase".dload+dlink.all

	# cleanup
	rm -f "$PWD/$rfsDLoadFolder/$_outBase".dlink.dlapi.link "$PWD/$rfsDLoadFolder/$_outBase".dlink.dlapi
	rm -f "$rootFS".files.elf.dlapi.all.short "$rootFS".files.so.dlink.dlapi.all.short
}

# Function: _rootFSElfAnalyzerValidation
# Input:
# $1 - rootFS name
# $2 - rfsElfFolder name
# $3 - process/*/maps file name
# $4 - rt validation folder name
# $5 - exe all file name
# $6 - elf all libdl-api file name
# $7 - procs to analyze if not empty, otherwise - all
# $8 - log name
# Output:

# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps file : $4 - rt validation folder
#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - procs to analyze : $8 - log name

function _rootFSElfAnalyzerValidation()
{
	local _rootFS="${1%/}"
	local _rfsElfFolder="$2"
	local _ppmFile="$3"
	local _validFolder="${4%/}"
	local _exeAllFile="$5"
	local _elfDlapiAllFile="$6"
	local _procsAnalyze="$7"
	local _log="$8"
	local _base="${9%/}"

	[ -z "$_base" ] && _base="."
	_rootFS="$_base/$_rootFS"
	_validFolder="$_base/$_validFolder"

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" \
	#"$FUNCNAME:" "rootFS" "$_rootFS" "elfFolder" "$_rfsElfFolder" "ppmFile" "$_ppmFile" "validFolder" "$_validFolder" "exeAllFile" "$_exeAllFile" \
	#"elfDlapiAllFile" "$_elfDlapiAllFile" "procsAnalyze" "$_procsAnalyze" "log" "$_log" "base" "$_base" | tee -a "$name".log

	rm -rf "$_validFolder"
	mkdir -p "$_validFolder"

	local _procPid=
	local _ename=
	local _proc=
	local _perms=
	local _offs=
	local _dev=
	local _inode=
	cat /dev/null > "$_rootFS".$fme_elf_rt_used
	grep -v "\[vdso\]" "$_ppmFile" | while read _proc _perms _offs _dev _inode _ename
	do
		[ -z "$_ename" ] && continue
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
		echo "$_ename" >> "$_rootFS".$fme_elf_rt_used
	done
	sort -u "$_rootFS".$fme_elf_rt_used -o "$_rootFS".$fme_elf_rt_used			# elfs used at run-time
	comm -13 "$_exeAllFile" "$_rootFS".$fme_elf_rt_used > "$_rootFS".$fme_so_rt_used	# libs used at run-time

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
	comm -23 <(sort "$_rootFS".procs+refs) "$_rootFS".procs.groups > "$_rootFS".$fme_rt

	# create a list of all independent run-time processes that can be analyzed
	grep -v "\->" "$_rootFS".procs+refs | sort -o "$_rootFS".$fme_nonredundant

	grep -v "$md5sumPExt\|$procPExt" "$_rootFS".$fme_nonredundant > "$_rootFS".$fme_nonredundant_si

	# create a list of run-time redundant processes not needed for analysis
	cat /dev/null > "$_rootFS".$fme_rt_redundant
	grep "\->" "$_rootFS".procs+refs | sort -k3,3 | awk -v file="$_rootFS".$fme_rt_redundant '{\
		if (entry == $3) { printf("%s\n", $0) >> file; }; entry=$3;
		}'

	#create a list of processes to analyze
	if [ -z "$_procsAnalyze" ]; then
		# analyze all nonredundant processes
		if [[ $_rootFS = /* ]]; then
			ln -sf "$_rootFS".$fme_nonredundant "$_rootFS".$fme_procs_analyze
		else
			ln -sf "$PWD/${_rootFS#$PWD}".$fme_nonredundant "$_rootFS".$fme_procs_analyze
		fi
	else
		# analyze all user-requested processes that can be analyzed (due to a possible mismatch to -ppm file)
		cat /dev/null > "$_procsAnalyze".$fme_not_available_in_ppm
		cat /dev/null > "$_procsAnalyze".analyze
		comm <(sed "s:$md5sumPExt::;s:$procPExt::" "$_rootFS".$fme_nonredundant | sort -u) <(sort -u "$_procsAnalyze" | tr '/' '%') | awk -F$'\t' -v name="$_procsAnalyze" '{\
		if (NF == 2) {\
			printf("%s\n", $2) >> name".not-available-in-ppm"
		} else if (NF == 3) {\
			printf("%s\n", $3) >> name".analyze.base"
		}\
		}'
		if [ -s "$_procsAnalyze".analyze.base ]; then
			#grep -f "$_procsAnalyze".analyze.base "$_rootFS".$fme_nonredundant > "$_procsAnalyze".analyze
			cat /dev/null > "$_procsAnalyze".analyze
			while read _proc
			do
				grep "$_proc$\|$_proc$procPExt\|$_proc$md5sumPExt" "$_rootFS".$fme_nonredundant >> "$_procsAnalyze".analyze
			done < "$_procsAnalyze".analyze.base

			ln -sf "$PWD/$_procsAnalyze".analyze "$_rootFS".$fme_procs_analyze
			rm "$_procsAnalyze".analyze.base
		else
			_logFileShort "$_rootFS".$fme_rt "${fileMetrics[$fme_rt]}" "$_log"
			_logFileShort "$_rootFS".$fme_nonredundant "${fileMetrics[$fme_nonredundant]}" "$_log"
			_logFileShort "$_rootFS".$fme_nonredundant_si "${fileMetrics[$fme_nonredundant_si]}" "$_log"
			_logFileShort "$_rootFS".$fme_rt_redundant "${fileMetrics[$fme_rt_redundant]}" "$_log"
			if [ -s "$_procsAnalyze".$fme_not_available_in_ppm ]; then
				_logFileShort "$_procsAnalyze".$fme_not_available_in_ppm "${fileMetrics[$fme_not_available_in_ppm]}" "$_log"
			else
				rm "$_procsAnalyze".$fme_not_available_in_ppm
			fi
			_logFileShort "$_rootFS".$fme_elf_rt_used "${fileMetrics[$fme_elf_rt_used]}" "$_log"
			_logFileShort "$_rootFS".$fme_exe_rt_used "${fileMetrics[$fme_exe_rt_used]}" "$_log"
			_logFileShort "$_rootFS".$fme_so_rt_used "${fileMetrics[$fme_so_rt_used]}" "$_log"

			printf "%-36s\n" "No processes to validate" | tee -a "$_log"
			rm "$_procsAnalyze".analyze*

			return
		fi
	fi

	# validate analyzed/independent run-time processes
	cat /dev/null > "$_rootFS".$fme_analyze_validated
	cat /dev/null > "$_rootFS".$fme_analyze_validated_ident
	cat /dev/null > "$_rootFS".$fme_analyze_not_validated

	cat /dev/null > "$_rootFS".$fme_analyze_validated_libdl_api
	cat /dev/null > "$_rootFS".$fme_analyze_validated_ident_libdl_api
	cat /dev/null > "$_rootFS".$fme_analyze_not_validated_libdl_api
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

		if [ ! -e "$_rfsElfFolder/$_fileE" ]; then
			echo "$name# ERROR: $FUNCNAME: missing \""$_rfsElfFolder/$_fileE"\" : Exit." | tee -a "$_log"
			return $ERR_OBJ_NOT_VALID
		fi

		comm "$_rfsElfFolder/$_fileE" "$_validFolder/$_file" | awk -F$'\t' -v name="$_validFolder/$_file" '{\
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
			echo "$_file" >> "$_rootFS".$fme_analyze_not_validated
			if [ -n "$(comm -12 "$_elfDlapiAllFile" $_rfsElfFolder/$_fileE)" ]; then
				echo "$_file" >> "$_rootFS".$fme_analyze_not_validated_libdl_api
			fi
			rm "$_validFolder/$_file".validated "$_validFolder/$_file".validated-ident
		elif [ -s "$_validFolder/$_file".validated ]; then
			# specific to "elf analyzed" - validated
			echo "$_file" >> "$_rootFS".$fme_analyze_validated
			if [ -n "$(comm -12 "$_elfDlapiAllFile" $_rfsElfFolder/$_fileE)" ]; then
				echo "$_file" >> "$_rootFS".$fme_analyze_validated_libdl_api
			fi
			rm "$_validFolder/$_file".not-validated "$_validFolder/$_file".validated-ident
		else
			# common between "elf analyzed" and "rt collected" - validated identical
			echo "$_file" >> "$_rootFS".$fme_analyze_validated_ident
			if [ -n "$(comm -12 "$_elfDlapiAllFile" $_rfsElfFolder/$_fileE)" ]; then
				echo "$_file" >> "$_rootFS".$fme_analyze_validated_ident_libdl_api
			fi
			rm "$_validFolder/$_file".not-validated "$_validFolder/$_file".validated
		fi
	done < "$_rootFS".$fme_procs_analyze

	_logFileShort "$_rootFS".$fme_rt "${fileMetrics[$fme_rt]}" "$_log"

	_logFileShort "$_rootFS".$fme_nonredundant "${fileMetrics[$fme_nonredundant]}" "$_log"
	_logFileShort "$_rootFS".$fme_nonredundant_si "${fileMetrics[$fme_nonredundant_si]}" "$_log"
	if [ -n "$_procsAnalyze" ]; then
		_logFileShort "$_procsAnalyze".analyze "Analyzed processes" "$_log"
		
		if [ -s "$_procsAnalyze".$fme_not_available_in_ppm ]; then
			_logFileShort "$_procsAnalyze".$fme_not_available_in_ppm "${fileMetrics[$fme_not_available_in_ppm]}" "$_log"
		else
			rm "$_procsAnalyze".$fme_not_available_in_ppm
		fi
	fi
	_logFileShort "$_rootFS".$fme_rt_redundant "${fileMetrics[$fme_rt_redundant]}" "$_log"

	if [ -s "$_rootFS".$fme_analyze_validated_ident ]; then
		_logFileShort "$_rootFS".$fme_analyze_validated_ident "${fileMetrics[$fme_analyze_validated_ident]}" "$_log"
	fi
	if [ -s "$_rootFS".$fme_analyze_validated ]; then
		_logFileShort "$_rootFS".$fme_analyze_validated "${fileMetrics[$fme_analyze_validated]}" "$_log"
	fi
	if [ -s "$_rootFS".$fme_analyze_not_validated ]; then
		_logFileShort "$_rootFS".$fme_analyze_not_validated "${fileMetrics[$fme_analyze_not_validated]}" "$_log"
	fi
	if [ -s "$_rootFS".$fme_analyze_validated_ident_libdl_api ]; then
		_logFileShort "$_rootFS".$fme_analyze_validated_ident_libdl_api "${fileMetrics[$fme_analyze_validated_ident_libdl_api]}" "$_log"
	fi
	if [ -s "$_rootFS".$fme_analyze_validated_ident ] && [ -s "$_rootFS".$fme_analyze_validated_ident_libdl_api ]; then
		comm -23 "$_rootFS".$fme_analyze_validated_ident "$_rootFS".$fme_analyze_validated_ident_libdl_api > "$_rootFS".$fme_analyze_validated_ident_not_libdl_api
		if [ -s "$_rootFS".$fme_analyze_validated_ident_not_libdl_api ]; then
			_logFileShort "$_rootFS".$fme_analyze_validated_ident_not_libdl_api "${fileMetrics[$fme_analyze_validated_ident_not_libdl_api]}" "$_log"
		fi
	fi
	if [ -s "$_rootFS".$fme_analyze_validated_libdl_api ]; then
		_logFileShort "$_rootFS".$fme_analyze_validated_libdl_api "${fileMetrics[$fme_analyze_validated_libdl_api]}" "$_log"
	fi
	if [ -s "$_rootFS".$fme_analyze_validated ] && [ -s "$_rootFS".$fme_analyze_validated_libdl_api ]; then
		comm -23 "$_rootFS".$fme_analyze_validated "$_rootFS".$fme_analyze_validated_libdl_api > "$_rootFS".$fme_analyze_validated_not_libdl_api
		if [ -s "$_rootFS".$fme_analyze_validated_not_libdl_api ]; then
			_logFileShort "$_rootFS".$fme_analyze_validated_not_libdl_api "${fileMetrics[$fme_analyze_validated_not_libdl_api]}" "$_log"
		fi
	fi
	if [ -s "$_rootFS".$fme_analyze_not_validated_libdl_api ]; then
		_logFileShort "$_rootFS".$fme_analyze_not_validated_libdl_api "${fileMetrics[$fme_analyze_not_validated_libdl_api]}" "$_log"
	fi
	if [ -s "$_rootFS".$fme_analyze_not_validated ] && [ -s "$_rootFS".$fme_analyze_not_validated_libdl_api ]; then
		comm -23 "$_rootFS".$fme_analyze_not_validated "$_rootFS".$fme_analyze_not_validated_libdl_api > "$_rootFS".$fme_analyze_not_validated_not_libdl_api
		if [ -s "$_rootFS".$fme_analyze_not_validated_not_libdl_api ]; then
			_logFileShort "$_rootFS".$fme_analyze_not_validated_not_libdl_api "${fileMetrics[$fme_analyze_not_validated_not_libdl_api]}" "$_log"
		fi
	fi
	_logFileShort "$_rootFS".$fme_elf_rt_used "${fileMetrics[$fme_elf_rt_used]}" "$_log"
	_logFileShort "$_rootFS".$fme_exe_rt_used "${fileMetrics[$fme_exe_rt_used]}" "$_log"
	_logFileShort "$_rootFS".$fme_so_rt_used "${fileMetrics[$fme_so_rt_used]}" "$_log"

	# Cleanup
	find "$_base" -maxdepth 1  -name "$(basename $_rootFS.$fme_procs_analyze)*" -size 0 -exec rm {} \;
	rm -f "$_rootFS".procs.groups "$_rootFS".proc-so-md5sum "$_rootFS".$fme_procs_analyze
}


# Function: _rootFSElfAnalyzerMValidation
# Input:
# $1 - rootFS name
# $2 - rfsElfFolder name
# $3 - process/*/maps files list name
# $4 - rt validation folder name
# $5 - exe all file name
# $6 - elf all libdl-api file name
# $7 - procs to analyze if not empty, otherwise - all
# $8 - log name
# $9 - work folder
# $10 - mrtv analysis ops
# Output:

# _rootFSElfAnalyzerMValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps files list : $4 - rt validation folder
#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - procs to analyze : $8 - log name : $9 - work folder : $10 - mrtv analysis ops

function _rootFSElfAnalyzerMValidation()
{
	local _rootFS="${1%/}"
	local _rfsElfFolder="$2"
	local _ppmList="$3"
	if [ -z "$_ppmList" ] || [ ! -s "$_ppmList" ]; then
		printf "%s: ERROR: File \"$_ppmList\" doesn't exist or NULL! Exit\n" "$FUNCNAME" | tee -a "$name".log
		return $ERR_OBJ_NOT_VALID
	fi
	local _rtvalidFolder="${4%/}"
	local _exeAllFile="$5"
	local _elfDlapiAllFile="$6"
	local _procsAnalyze="$7"
	local _log="$8"
	local _wFolder="${9%/}"
	local _ppmlOpts="${10}"

	local _ppmloT=
	local _ppmloC=
	local _ppmloS=
	[ "${_ppmlOpts#*t}" != "$_ppmlOpts" ] && _ppmloT=y
	[ "${_ppmlOpts#*c}" != "$_ppmlOpts" ] && _ppmloC=y
	[ "${_ppmlOpts#*s}" != "$_ppmlOpts" ] && _ppmloS=y

	_wFolderPfx=$(_mkWFolder "$_wFolder")

	#printf "%s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n%-12s = %s\n" \
	#"$FUNCNAME:" "rootFS" "$_rootFS" "elfFolder" "$_rfsElfFolder" "ppmList" "$_ppmList" "rtvalidFolder" "$_rtvalidFolder" "exeAllFile" "$_exeAllFile" \
	#"elfDlapiAllFile" "$_elfDlapiAllFile" "procsAnalyze" "$_procsAnalyze" "log" "$_log" "wFolder" "$_wFolder" "wFolderPfx" "$_wFolderPfx" "ppmlOpts" "$_ppmlOpts" | tee -a "$name".log

	local _ext=
	for _ext in $fileMetricsExts; do
		cat /dev/null > "$_wFolderPfx/$_rootFS".$_ext
	done

	local _ppmaps=
	local _valFolder=
	while read _ppmaps
	do
		if [ -n "$_ppmList" ]; then
			_valFolder="$(basename $_ppmaps)"
			printf "\n$name : ppmaps file      = $_ppmaps\n"
			#printf "$name : validation folder  = $_valFolder\n"
		fi
		# _rootFSElfAnalyzerValidation	: $1 - rootFS name : $2 - elfFolder : $3 - procs maps file : $4 - rt validation folder
		#				: $5 - exe all file : $6 - elf all libdl-api file  : $7 - procs to analyze : $8 - log name : $9 - work folder
		_rootFSElfAnalyzerValidation "$_rootFS" "$_rfsElfFolder" "$_ppmaps" "$_rtvalidFolder" \
						"$_exeAllFile" "$_elfDlapiAllFile" "$_procsAnalyze" "$_wFolderPfx/$_valFolder/$name".log "$_wFolderPfx"/$_valFolder

		if [ -n "$_ppmList" ]; then
			echo "$(cat "$name".log "$_wFolderPfx/$_valFolder/$name".log)" > "$_wFolderPfx/$_valFolder/$name".log

			# Metrics collection
			for _ext in $fileMetricsExts; do
				if [ -s "$_wFolderPfx/$_valFolder/$_rootFS".$_ext ]; then
					cat "$_wFolderPfx/$_valFolder/$_rootFS".$_ext >> "$_wFolderPfx/$_rootFS".$_ext
				fi
			done
		fi
	done < "$_ppmList"

	# Metrics analysis
	[ -n "$_ppmloT" ] && mkdir -p "$_wFolderPfx/$_rootFS".total
	[ -n "$_ppmloC" ] && mkdir -p "$_wFolderPfx/$_rootFS".common

	for _ext in $fileMetricsExts; do
		if [ -s "$_wFolderPfx/$_rootFS".$_ext ]; then
			[ -n "$_ppmloT" ] && sort -u "$_wFolderPfx/$_rootFS".$_ext -o "$_wFolderPfx/$_rootFS".total/"$_rootFS".total.$_ext
			[ -n "$_ppmloC" ] && sort "$_wFolderPfx/$_rootFS".$_ext | uniq -d > "$_wFolderPfx/$_rootFS".common/"$_rootFS".common.$_ext
			rm "$_wFolderPfx/$_rootFS".$_ext
		fi
	done

	# Total metrics analysis
	if [ -n "$_ppmloT" ]; then
		printf "\nTotal metrics\n" | tee -a "$name".log
		for _ext in $fileMetricsExts; do
			if [ -s "$_wFolderPfx/$_rootFS".total/"$_rootFS".total.$_ext ]; then
				_logFileShort "$_wFolderPfx/$_rootFS".total/"$_rootFS".total.$_ext "${fileMetrics[$_ext]}" "$name".log
			fi
		done
	fi

	# Common metrics analysis
	if [ -n "$_ppmloC" ]; then
		printf "\nCommon metrics\n" | tee -a "$name".log
		for _ext in $fileMetricsExts; do
			if [ -s "$_wFolderPfx/$_rootFS".common/"$_rootFS".common.$_ext ]; then
				_logFileShort "$_wFolderPfx/$_rootFS".common/"$_rootFS".common.$_ext "${fileMetrics[$_ext]}" "$name".log
			fi
		done
	fi

	# Specific metrics analysis
	if [ -n "$_ppmloS" ]; then
		local _outFolder=
		while read _ppmaps
		do
			_valFolder="$(basename $_ppmaps)"
			_outFolder="$_wFolderPfx/$_rootFS".spec.${_valFolder##*.}
			mkdir -p "$_outFolder"
			printf "\nSpecific $_valFolder metrics in $_outFolder\n" | tee -a "$name".log
			for _ext in $fileMetricsExts; do
				if [ -s "$_wFolderPfx/$_rootFS".common/"$_rootFS".common.$_ext ] && [ -s "$_wFolderPfx/$_valFolder/$_rootFS".$_ext ]; then
					comm -13 "$_wFolderPfx/$_rootFS".common/"$_rootFS".common.$_ext <(sort "$_wFolderPfx/$_valFolder/$_rootFS".$_ext) > \
						"$_outFolder/$_rootFS".spec.$_ext
				elif [ -s "$_wFolderPfx/$_rootFS".common/"$_rootFS".common.$_ext ]; then
					cat "$_wFolderPfx/$_rootFS".common/"$_rootFS".common.$_ext > "$_outFolder/$_rootFS".spec.$_ext
				elif [ -s "$_wFolderPfx/$_valFolder/$_rootFS".$_ext ]; then
					cat "$_wFolderPfx/$_valFolder/$_rootFS".$_ext > "$_outFolder/$_rootFS".spec.$_ext
				fi

				if [ -s "$_outFolder/$_rootFS".spec.$_ext ]; then
					_logFileShort "$_outFolder/$_rootFS".spec.$_ext "${fileMetrics[$_ext]}" "$name".log
				fi
			done
		done < "$_ppmList"
	fi

	find "$_wFolderPfx" -maxdepth 2 -size 0 -exec rm {} \;
}

