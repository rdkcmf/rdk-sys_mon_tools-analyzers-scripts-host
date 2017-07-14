#!/bin/bash
#

ESH_HEADER_NAME="Name"
ESH_HEADER_TYPE="Type"
ESH_HEADER_SPACE="Space"
ESH_HEADER_SIZE="Size"
ESH_HEADER_ADDR="Address"
ESH_HEADER_FOFF="FileOffset"
ESH_HEADER_TEXT_NAME="FunctionName"
ESH_HEADER_SECNAME="SectionName"

# Headers
#							Name		Type		Size
ESH_HEADER_1=$(printf "%-20s\t%-14s\t%-8s\t%-8s\n" $ESH_HEADER_NAME $ESH_HEADER_TYPE $ESH_HEADER_SIZE)
#							Name		Type		Size#1		Size#2		Size#1-Size#2
ESH_HEADER_2=$(printf "%-20s\t%-14s\t%-8s\t%-8s\t%-8s\n" $ESH_HEADER_NAME $ESH_HEADER_TYPE $ESH_HEADER_SIZE#1 $ESH_HEADER_SIZE#2 $ESH_HEADER_SIZE#1-#2)
#							Address		Size		FunctionName
ESH_HEADER_TEXT_1=$(printf "%-10s\t%-9s\t%s\n" $ESH_HEADER_ADDR $ESH_HEADER_SIZE $ESH_HEADER_TEXT_NAME)
#							Size#1		Size#2		Size#1-Size#2		FunctionName
ESH_HEADER_TEXT_2=$(printf "%-10s\t%-10s\t%-9s\t%s\n" $ESH_HEADER_SIZE#1 $ESH_HEADER_SIZE#2 $ESH_HEADER_SIZE#1-#2 $ESH_HEADER_TEXT_NAME)
#							Size		FunctionName
ESH_HEADER_TEXT=$(printf "%-10s\t%s\n" $ESH_HEADER_SIZE $ESH_HEADER_TEXT_NAME)
#							Address		Size		Name
ESH_HEADER_OBJ_1=$(printf "%-10s\t%-9s\t%s\n" $ESH_HEADER_ADDR $ESH_HEADER_SIZE $ESH_HEADER_NAME)
#							Size#1		Size#2		Size#1-Size#2		Name
ESH_HEADER_OBJ_2=$(printf "%-10s\t%-10s\t%-9s\t%s\n" $ESH_HEADER_SIZE#1 $ESH_HEADER_SIZE#2 $ESH_HEADER_SIZE#1-#2 $ESH_HEADER_NAME)
#							Address		Size		SectionName
ESH_HEADER_AXSECS=$(printf "%-10s\t%-9s\t%s\n" $ESH_HEADER_ADDR $ESH_HEADER_SIZE $ESH_HEADER_SECNAME)
#							SectionName	Address		Size		Name
ESH_HEADER_ODDS=$(printf "%-10s\t%-9s\t%-9s\t%s\n" $ESH_HEADER_SECNAME $ESH_HEADER_ADDR $ESH_HEADER_SIZE $ESH_HEADER_NAME)
#							Address		Space		Size			Space-Size			Name
ESH_HEADER_SSD=$(printf "%-10s\t%-9s\t%-9s\t%s-%s\t%s\n" $ESH_HEADER_ADDR $ESH_HEADER_SPACE $ESH_HEADER_SIZE $ESH_HEADER_SPACE $ESH_HEADER_SIZE $ESH_HEADER_NAME)

