#!/bin/bash
#

ESH_HEADER_NAME="Name"
ESH_HEADER_TYPE="Type"
ESH_HEADER_SIZE="Size"
ESH_HEADER_1=$(printf "%-20s\t%-14s\t%-8s\t%-8s\n" $ESH_HEADER_NAME $ESH_HEADER_TYPE $ESH_HEADER_SIZE)
ESH_HEADER_2=$(printf "%-20s\t%-14s\t%-8s\t%-8s\t%-8s\n" $ESH_HEADER_NAME $ESH_HEADER_TYPE $ESH_HEADER_SIZE#1 $ESH_HEADER_SIZE#2 $ESH_HEADER_SIZE#1-#2)

ESH_HEADER_ADDR="Address"
ESH_HEADER_FOFF="FileOffset"
ESH_HEADER_TEXT_NAME="FunctionName"
ESH_HEADER_TEXT_1=$(printf "%-10s\t%-9s\t%s\n" $ESH_HEADER_ADDR $ESH_HEADER_SIZE $ESH_HEADER_TEXT_NAME)
ESH_HEADER_TEXT_2=$(printf "%-10s\t%-10s\t%-9s\t%s\n" $ESH_HEADER_SIZE#1 $ESH_HEADER_SIZE#2 $ESH_HEADER_SIZE#1-#2 $ESH_HEADER_TEXT_NAME)
ESH_HEADER_TEXT=$(printf "%-10s\t%s\n" $ESH_HEADER_SIZE $ESH_HEADER_TEXT_NAME)
ESH_HEADER_OBJ_1=$(printf "%-10s\t%-9s\t%s\n" $ESH_HEADER_ADDR $ESH_HEADER_SIZE $ESH_HEADER_NAME)

ESH_HEADER_SECNAME="SectionName"
ESH_HEADER_AXSECS=$(printf "%-10s\t%-9s\t%s\n" $ESH_HEADER_ADDR $ESH_HEADER_SIZE $ESH_HEADER_SECNAME)

ELF_PSEC_STARTOF_TEXT="<start_of_exec_secs>"
ELF_PSEC_ENDOF_TEXT="<end_of_exec_secs>"

