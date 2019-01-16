#!/bin/bash
#

# Error codes
ERR_NOT_A_ERROR=0
ERR_UNKNOWN_PARAM=1
ERR_PARAM_NOT_SET=2
ERR_OBJ_NOT_FOUND=3
ERR_OBJ_NOT_VALID=4
ERR_INTERNAL_ERROR=5

declare -A exitStatus
# Errors:
exitStatus[$ERR_NOT_A_ERROR]="success"
exitStatus[$ERR_UNKNOWN_PARAM]="error: unknown parameter"
exitStatus[$ERR_PARAM_NOT_SET]="error: parameter is not set"
exitStatus[$ERR_OBJ_NOT_FOUND]="error: object is not found"
exitStatus[$ERR_OBJ_NOT_VALID]="error: object is not valid"
exitStatus[$ERR_INTERNAL_ERROR]="error: internal"
# Signals: 128 + <signal#>
exitStatus[129]="signal: SIGHUP"
exitStatus[130]="signal: SIGINT"
exitStatus[131]="signal: SIGQUIT"
exitStatus[134]="signal: SIGABRT"
exitStatus[143]="signal: SIGTERM"

# Function: setTrapHandler
# Input:
# $1	- trap handler name
# $2...	- a list of signal(s) to trap

function setTrapHandler()
{
	trapHandlerName="$1"
	shift
	while [ "$1" != "" ]; do
		echo "setTrapHandler: $trapHandlerName $1" "$1"
		trap "$trapHandlerName $1" "$1" &>/dev/null
		shift
	done
}

# Function: setTrapHandlerWithParams
# Input:
# $1	- trap handler name
# $2	- a number of signals to trap
# $3...	- a list of signal(s) to trap
# $4...	- a list of params(s) to pass to the trap handler

function setTrapHandlerWithParams()
{
	#echo "trapHandlerName = $1 : numberOfsignals = $2"
	trapHandlerName="$1"
	shift
	numberOfsignals=$1
	shift
	if [ "$numberOfsignals" -gt 0 ]; then
		signalList=$(echo "$* " | cut -d ' ' -f1-$numberOfsignals)
		#echo "signalList = $signalList"
		params=$(echo "$* " | cut -d ' ' -f"$((++numberOfsignals))"-)
		#echo "params = $params"
		for signal in $signalList; do
			#echo "$trapHandlerName $signal $params" $signal
			trap "$trapHandlerName $signal $params" $signal &>/dev/null
		done
	fi
}

# Function: exitProcessing
# Input:
# $1	- an exit code
# $2	- an error status

function exitProcessing()
{
	errorStatus=$2
	if [ -z $exitCode ]; then
		if [ "$errorStatus" -ne "0" ]; then
			# Error processing
			exitCode=$errorStatus
		else
			# Signal & normal exit processing
			exitCode=$1
			[ "$exitCode" -ne "0" ] && ((exitCode+=128))
		fi
		echo "$name : exit code = $exitCode - ${exitStatus[$exitCode]}" | tee -a "$name".log
	fi
}
