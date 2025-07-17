#!/bin/bash

# Extracted and Modified Yet Another Bench Script FIO part by Mason Rowe
# Based on original YABS_VERSION="v2025-04-20"

# Purpose: This script focuses on benchmarking random disk performance via fio.
#          It allows specifying a custom test path.

YABS_VERSION="v2025-04-20 (FIO-only)"

echo -e '# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #'
echo -e '#              Yet-Another-Bench-Script              #'
echo -e '#                   (FIO-only)                       #'
echo -e '#                     '$YABS_VERSION'              #'
echo -e '# https://github.com/masonr/yet-another-bench-script #'
echo -e '# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #'

echo -e
date
TIME_START=$(date '+%Y%m%d-%H%M%S')
YABS_START_TIME=$(date +%s)

# override locale to eliminate parsing errors
if locale -a 2>/dev/null | grep ^C$ > /dev/null; then
	export LC_ALL=C
else
	echo -e "\nWarning: locale 'C' not detected. Test outputs may not be parsed correctly."
fi

# determine architecture of host
ARCH=$(uname -m)
if [[ $ARCH = *x86_64* ]]; then
	ARCH="x64"
elif [[ $ARCH = *i?86* ]]; then
	ARCH="x86"
elif [[ $ARCH = *aarch* || $ARCH = *arm* ]]; then
	KERNEL_BIT=$(getconf LONG_BIT)
	if [[ $KERNEL_BIT = *64* ]]; then
		ARCH="aarch64"
	else
		ARCH="arm"
	fi
	echo -e "\nARM compatibility is considered *experimental*"
else
	echo -e "Architecture not supported by YABS-FIO."
	exit 1
fi

# flags for skipping tests and custom path
unset PREFER_BIN SKIP_FIO PRINT_HELP DD_FALLBACK TEST_PATH JSON JSON_SEND JSON_RESULT JSON_FILE

# get any arguments that were passed to the script
while getopts 'bfdhjrw:s:p:' flag; do # Added 'p:'
	case "${flag}" in
		b) PREFER_BIN="True" ;;
		f) SKIP_FIO="True" ;;
		d) SKIP_FIO="True" ;; # Alias for -f
		h) PRINT_HELP="True" ;;
		j) JSON+="j" ;;
		w) JSON+="w" && JSON_FILE=${OPTARG} ;;
		s) JSON+="s" && JSON_SEND=${OPTARG} ;;
		p) TEST_PATH=${OPTARG} ;; # New flag for test path
		*) exit 1 ;;
	esac
done

# check for local fio install
if command -v fio >/dev/null 2>&1; then
    LOCAL_FIO=true
else
    unset LOCAL_FIO
fi

# check for curl/wget for downloads
if command -v curl >/dev/null 2>&1; then
    LOCAL_CURL=true
else
    unset LOCAL_CURL
fi

# print help and exit script, if help flag was passed
if [ -n "$PRINT_HELP" ]; then
	echo -e
	echo -e "Usage: ./yabs-fio.sh [-flags]"
	echo -e
	echo -e "Flags:"
	echo -e "       -b : prefer pre-compiled binaries from repo over local packages"
	echo -e "       -f/d : skips the fio disk benchmark test (effectively exits if used alone)"
	echo -e "       -h : prints this lovely message, shows any flags you passed,"
	echo -e "            shows if fio local packages have been detected, then exits"
	echo -e "       -p <path> : specify the directory for disk benchmark files (e.g., /mnt/raid0)"
	echo -e "       -j : print jsonified YABS results at conclusion of test"
	echo -e "       -w <filename> : write jsonified YABS results to disk using file name provided"
	echo -e "       -s <url> : send jsonified YABS results to URL"
	echo -e
	echo -e "Detected Arch: $ARCH"
	echo -e
	echo -e "Detected Flags:"
	[[ -n $PREFER_BIN ]] && echo -e "       -b, force using precompiled binaries from repo"
	[[ -n $SKIP_FIO ]] && echo -e "       -f/d, skipping fio disk benchmark test"
	[[ -n $TEST_PATH ]] && echo -e "       -p, disk test path: $TEST_PATH"
	echo -e
	echo -e "Local Binary Check:"
	([[ -z $LOCAL_FIO ]] && echo -e "       fio not detected, will download precompiled binary") || \
		([[ -z $PREFER_BIN ]] && echo -e "       fio detected, using local package") || \
		echo -e "       fio detected, but using precompiled binary instead"
	echo -e
	echo -e "JSON Options:"
	[[ -z $JSON ]] && echo -e "       none"
	[[ $JSON = *j* ]] && echo -e "       printing json to screen after test"
	[[ $JSON = *w* ]] && echo -e "       writing json to file ($JSON_FILE) after test"
	[[ $JSON = *s* ]] && echo -e "       sharing json YABS results to $JSON_SEND"
	echo -e
	echo -e "Exiting..."

	exit 0
fi

# Placeholder for basic system info in JSON if needed, otherwise remove
if [[ -n $JSON ]]; then
	UPTIME_S=$(awk '{print $1}' /proc/uptime)
	# Simplified for FIO-only, remove other elements
	JSON_RESULT='{"version":"'$YABS_VERSION'","time":"'$TIME_START'","os":{"arch":"'$ARCH'","uptime":'$UPTIME_S'}'
fi

# create a directory in the same location that the script is being run to temporarily store YABS-related files
DATE=$(date -Iseconds | sed -e "s/:/_/g")
YABS_PATH=./$DATE # This is for the overall temporary files, not necessarily the disk test files

# Determine the actual disk test path
if [ -z "$TEST_PATH" ]; then
    DISK_PATH=$YABS_PATH/disk
else
    DISK_PATH=$TEST_PATH/yabs_disk_test # Create a subdirectory within the specified path to avoid clutter
fi

# Test if the user has write permissions in the chosen directory and exit if not
touch "$DISK_PATH/$DATE.test" 2> /dev/null
if [ ! -f "$DISK_PATH/$DATE.test" ]; then
	echo -e
	echo -e "You do not have write permission in $DISK_PATH. Please specify an owned directory or ensure permissions."
	echo -e "Exiting..."
	exit 1
fi
rm "$DISK_PATH/$DATE.test"
mkdir -p "$DISK_PATH"

# trap CTRL+C signals to exit script cleanly
trap catch_abort INT

# catch_abort
# Purpose: This method will catch CTRL+C signals in order to exit the script cleanly and remove
#          yabs-related files.
function catch_abort() {
	echo -e "\n** Aborting YABS-FIO. Cleaning up files...\n"
	if [ -n "$TEST_PATH" ]; then
        rm -rf "$TEST_PATH/yabs_disk_test" # Clean up the specific test path
    fi
	rm -rf "$YABS_PATH" # Clean up the default YABS temp path
	unset LC_ALL
	exit 0
}

# format_speed (same as original)
function format_speed {
	RAW=$1 # disk speed in KB/s
	RESULT=$RAW
	local DENOM=1
	local UNIT="KB/s"
	if [ -z "$RAW" ]; then echo ""; return 0; fi
	if [ "$RAW" -ge 1000000 ]; then DENOM=1000000; UNIT="GB/s"; elif [ "$RAW" -ge 1000 ]; then DENOM=1000; UNIT="MB/s"; fi
	RESULT=$(awk -v a="$RESULT" -v b="$DENOM" 'BEGIN { print a / b }')
	RESULT=$(echo "$RESULT" | awk -F. '{ printf "%0.2f",$1"."substr($2,1,2) }')
	RESULT="$RESULT $UNIT"
	echo "$RESULT"
}

# format_iops (same as original)
function format_iops {
	RAW=$1 # iops
	RESULT=$RAW
	if [ -z "$RAW" ]; then echo ""; return 0; fi
	if [ "$RAW" -ge 1000 ]; then RESULT=$(awk -v a="$RESULT" 'BEGIN { print a / 1000 }'); RESULT=$(echo "$RESULT" | awk -F. '{ printf "%0.1f",$1"."substr($2,1,1) }'); RESULT="$RESULT"k; fi
	echo "$RESULT"
}

# disk_test (same as original, ensure it uses DISK_PATH)
function disk_test {
	if [[ "$ARCH" = "aarch64" || "$ARCH" = "arm" ]]; then
		FIO_SIZE=512M
	else
		FIO_SIZE=2G
	fi

	echo -en "Generating fio test file in $DISK_PATH..."
	$FIO_CMD --name=setup --ioengine=libaio --rw=read --bs=64k --iodepth=64 --numjobs=2 --size=$FIO_SIZE --runtime=1 --gtod_reduce=1 --filename="$DISK_PATH/test.fio" --direct=1 --minimal &> /dev/null
	echo -en "\r\033[0K"

	BLOCK_SIZES=("$@")

	for BS in "${BLOCK_SIZES[@]}"; do
		echo -en "Running fio random mixed R+W disk test with $BS block size in $DISK_PATH..."
		DISK_TEST=$(timeout 35 "$FIO_CMD" --name=rand_rw_"$BS" --ioengine=libaio --rw=randrw --rwmixread=50 --bs="$BS" --iodepth=64 --numjobs=2 --size="$FIO_SIZE" --runtime=30 --gtod_reduce=1 --direct=1 --filename="$DISK_PATH/test.fio" --group_reporting --minimal 2> /dev/null | grep rand_rw_"$BS")
		DISK_IOPS_R=$(echo "$DISK_TEST" | awk -F';' '{print $8}')
		DISK_IOPS_W=$(echo "$DISK_TEST" | awk -F';' '{print $49}')
		DISK_IOPS=$(awk -v a="$DISK_IOPS_R" -v b="$DISK_IOPS_W" 'BEGIN { print a + b }')
		DISK_TEST_R=$(echo "$DISK_TEST" | awk -F';' '{print $7}')
		DISK_TEST_W=$(echo "$DISK_TEST" | awk -F';' '{print $48}')
		DISK_TEST=$(awk -v a="$DISK_TEST_R" -v b="$DISK_TEST_W" 'BEGIN { print a + b }')
		DISK_RESULTS_RAW+=( "$DISK_TEST" "$DISK_TEST_R" "$DISK_TEST_W" "$DISK_IOPS" "$DISK_IOPS_R" "$DISK_IOPS_W" )

		DISK_IOPS=$(format_iops "$DISK_IOPS")
		DISK_IOPS_R=$(format_iops "$DISK_IOPS_R")
		DISK_IOPS_W=$(format_iops "$DISK_IOPS_W")
		DISK_TEST=$(format_speed "$DISK_TEST")
		DISK_TEST_R=$(format_speed "$DISK_TEST_R")
		DISK_TEST_W=$(format_speed "$DISK_TEST_W")

		DISK_RESULTS+=( "$DISK_TEST" "$DISK_TEST_R" "$DISK_TEST_W" "$DISK_IOPS" "$DISK_IOPS_R" "$DISK_IOPS_W" )
		echo -en "\r\033[0K"
	done
}

# dd_test (same as original, ensure it uses DISK_PATH)
function dd_test {
	I=0
	DISK_WRITE_TEST_RES=()
	DISK_READ_TEST_RES=()
	DISK_WRITE_TEST_AVG=0
	DISK_READ_TEST_AVG=0

	while [ $I -lt 3 ]
	do
		DISK_WRITE_TEST=$(dd if=/dev/zero of="$DISK_PATH/$DATE.test" bs=64k count=16k oflag=direct |& grep copied | awk '{ print $(NF-1) " " $(NF)}')
		VAL=$(echo "$DISK_WRITE_TEST" | cut -d " " -f 1)
		[[ "$DISK_WRITE_TEST" == *"GB"* ]] && VAL=$(awk -v a="$VAL" 'BEGIN { print a * 1000 }')
		DISK_WRITE_TEST_RES+=( "$DISK_WRITE_TEST" )
		DISK_WRITE_TEST_AVG=$(awk -v a="$DISK_WRITE_TEST_AVG" -v b="$VAL" 'BEGIN { print a + b }')

		DISK_READ_TEST=$(dd if="$DISK_PATH/$DATE.test" of=/dev/null bs=8k |& grep copied | awk '{ print $(NF-1) " " $(NF)}')
		VAL=$(echo "$DISK_READ_TEST" | cut -d " " -f 1)
		[[ "$DISK_READ_TEST" == *"GB"* ]] && VAL=$(awk -v a="$VAL" 'BEGIN { print a * 1000 }')
		DISK_READ_TEST_RES+=( "$DISK_READ_TEST" )
		DISK_READ_TEST_AVG=$(awk -v a="$DISK_READ_TEST_AVG" -v b="$VAL" 'BEGIN { print a + b }')

		I=$(( I + 1 ))
	done
	DISK_WRITE_TEST_AVG=$(awk -v a="$DISK_WRITE_TEST_AVG" 'BEGIN { print a / 3 }')
	DISK_READ_TEST_AVG=$(awk -v a="$DISK_READ_TEST_AVG" 'BEGIN { print a / 3 }')
}

# check if disk performance is being tested and the host has required space
AVAIL_SPACE=$(df -k "$DISK_PATH" | awk 'NR==2{print $4}') # Check space in the specific DISK_PATH
if [[ -z "$SKIP_FIO" && "$AVAIL_SPACE" -lt 2097152 && "$ARCH" != "aarch64" && "$ARCH" != "arm" ]]; then # 2GB = 2097152KB
	echo -e "\nLess than 2GB of space available in $DISK_PATH. Skipping disk test..."
elif [[ -z "$SKIP_FIO" && "$AVAIL_SPACE" -lt 524288 && ("$ARCH" = "aarch64" || "$ARCH" = "arm") ]]; then # 512MB = 524288KB
	echo -e "\nLess than 512MB of space available in $DISK_PATH. Skipping disk test..."
elif [ -z "$SKIP_FIO" ]; then
    # ZFS check - make sure it uses $DISK_PATH or finds the relevant mounted point correctly
    ZFSCHECK="/sys/module/zfs/parameters/spa_asize_inflation"
    if [[ -f "$ZFSCHECK" ]]; then
        mul_spa=$(( $(cat /sys/module/zfs/parameters/spa_asize_inflation) * 2 ))
        warning=0
        
        # Find relevant filesystem paths that are parent directories or the DISK_PATH itself
        long=""
        m=-1
        # Use DISK_PATH directly to check for ZFS mount
        for pathls in $(df -Th "$DISK_PATH" | awk '{print $7}' | tail -n +2)
        do
            if [[ "${DISK_PATH}" == "${pathls}"* ]]; then
                if [ "${#pathls}" -gt "$m" ];then
                    m=${#pathls}
                    long=$pathls
                fi
            fi
        done

        if [[ -n "$long" ]]; then
            avail_space_with_unit=$(df -Th | grep -w "$long" | awk '$2 == "zfs" {print $4; exit}')
            if [[ -n "$avail_space_with_unit" ]]; then
                free_space_gb_int=$(echo "$avail_space_with_unit" | awk '
                {
                    numeric_part = $0; unit = "";
                    if (match($0, /([0-9.]+)([KMGTB]?)$/)) {
                        numeric_part = substr($0, RSTART, RLENGTH - length(substr($0, RSTART + RLENGTH - 1, 1)));
                        unit = substr($0, RSTART + RLENGTH - 1, 1);
                        if (unit ~ /[0-9.]/) { unit = ""; }
                    }
                    unit = toupper(unit);
                    converted_value_gb = 0;
                    if (unit == "T") { converted_value_gb = numeric_part * 1024; } else if (unit == "G") { converted_value_gb = numeric_part; } else if (unit == "M") { converted_value_gb = numeric_part / 1024; } else if (unit == "K") { converted_value_gb = numeric_part / (1024 * 1024); } else if (unit == "B" || unit == "") { converted_value_gb = numeric_part / (1024 * 1024 * 1024); }
                    printf "%.0f\n", converted_value_gb;
                }')

                if ((free_space_gb_int < mul_spa)); then
                    warning=1
                fi
            else
                echo "Warning: Could not parse free space format for $long: '$avail_space_with_unit'"
            fi
        fi

        if [[ $warning -eq 1 ]];then
            echo -en "\nWarning! You are running YABS on a ZFS Filesystem and your disk space is too low for the fio test in $DISK_PATH. Your test results will be inaccurate. You need at least $mul_spa GB free in order to complete this test accurately. For more information, please see https://github.com/masonr/yet-another-bench-script/issues/13\n"
        fi
    fi

	echo -en "\nPreparing system for disk tests in $DISK_PATH..."

	if [[ -z "$PREFER_BIN" && -n "$LOCAL_FIO" ]]; then
		FIO_CMD=fio
	else
		if [[ -n $LOCAL_CURL ]]; then
			curl -s --connect-timeout 5 --retry 5 --retry-delay 0 https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/fio/fio_$ARCH -o "$DISK_PATH/fio"
		else
			wget -q -T 5 -t 5 -w 0 https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/fio/fio_$ARCH -O "$DISK_PATH/fio"
		fi

		if [ ! -f "$DISK_PATH/fio" ]; then
			echo -en "\r\033[0K"
			echo -e "Fio binary download failed. Running dd test as fallback...."
			DD_FALLBACK=True
		else
			chmod +x "$DISK_PATH/fio"
			FIO_CMD=$DISK_PATH/fio
		fi
	fi

	if [ -z "$DD_FALLBACK" ]; then
		echo -en "\r\033[0K"
		declare -a DISK_RESULTS DISK_RESULTS_RAW
		BLOCK_SIZES=( "4k" "64k" "512k" "1m" )
		disk_test "${BLOCK_SIZES[@]}"
	fi

	if [[ -n "$DD_FALLBACK" || ${#DISK_RESULTS[@]} -eq 0 ]]; then
		if [ -z "$DD_FALLBACK" ]; then
			echo -e "fio disk speed tests failed. Run manually to determine cause.\nRunning dd test as fallback..."
		fi

		dd_test

		if [ "$(echo "$DISK_WRITE_TEST_AVG" | cut -d "." -f 1)" -ge 1000 ]; then
			DISK_WRITE_TEST_AVG=$(awk -v a="$DISK_WRITE_TEST_AVG" 'BEGIN { print a / 1000 }')
			DISK_WRITE_TEST_UNIT="GB/s"
		else
			DISK_WRITE_TEST_UNIT="MB/s"
		fi
		if [ "$(echo "$DISK_READ_TEST_AVG" | cut -d "." -f 1)" -ge 1000 ]; then
			DISK_READ_TEST_AVG=$(awk -v a="$DISK_READ_TEST_AVG" 'BEGIN { print a / 1000 }')
			DISK_READ_TEST_UNIT="GB/s"
		else
			DISK_READ_TEST_UNIT="MB/s"
		fi

		echo -e
		echo -e "dd Sequential Disk Speed Tests (in $DISK_PATH):"
		echo -e "---------------------------------"
		printf "%-6s | %-6s %-4s | %-6s %-4s | %-6s %-4s | %-6s %-4s\n" "" "Test 1" "" "Test 2" ""  "Test 3" "" "Avg" ""
		printf "%-6s | %-6s %-4s | %-6s %-4s | %-6s %-4s | %-6s %-4s\n" "" "" "" "" "" "" "" "" ""
		printf "%-6s | %-11s | %-11s | %-11s | %-6.2f %-4s\n" "Write" "${DISK_WRITE_TEST_RES[0]}" "${DISK_WRITE_TEST_RES[1]}" "${DISK_WRITE_TEST_RES[2]}" "${DISK_WRITE_TEST_AVG}" "${DISK_WRITE_TEST_UNIT}"
		printf "%-6s | %-11s | %-11s | %-11s | %-6.2f %-4s\n" "Read" "${DISK_READ_TEST_RES[0]}" "${DISK_READ_TEST_RES[1]}" "${DISK_READ_TEST_RES[2]}" "${DISK_READ_TEST_AVG}" "${DISK_READ_TEST_UNIT}"
	else
		CURRENT_PARTITION=$(df -P "$DISK_PATH" 2>/dev/null | tail -1 | cut -d' ' -f 1)
		[[ -n $JSON ]] && JSON_RESULT+=',"partition":"'$CURRENT_PARTITION'","fio":['
		DISK_RESULTS_NUM=$((${#DISK_RESULTS[@]} / 6))
		DISK_COUNT=0

		echo -e "fio Disk Speed Tests (Mixed R/W 50/50) (Partition $CURRENT_PARTITION in $DISK_PATH):"
		echo -e "---------------------------------"

		while [[ $DISK_COUNT -lt $DISK_RESULTS_NUM ]] ; do
			if [[ $DISK_COUNT -gt 0 ]]; then printf "%-10s | %-20s | %-20s\n" "" "" ""; fi
			printf "%-10s | %-11s %8s | %-11s %8s\n" "Block Size" "${BLOCK_SIZES[DISK_COUNT]}" "(IOPS)" "${BLOCK_SIZES[DISK_COUNT+1]}" "(IOPS)"
			printf "%-10s | %-11s %8s | %-11s %8s\n" "  ------" "---" "---- " "----" "---- "
			printf "%-10s | %-11s %8s | %-11s %8s\n" "Read" "${DISK_RESULTS[DISK_COUNT*6+1]}" "(${DISK_RESULTS[DISK_COUNT*6+4]})" "${DISK_RESULTS[(DISK_COUNT+1)*6+1]}" "(${DISK_RESULTS[(DISK_COUNT+1)*6+4]})"
			printf "%-10s | %-11s %8s | %-11s %8s\n" "Write" "${DISK_RESULTS[DISK_COUNT*6+2]}" "(${DISK_RESULTS[DISK_COUNT*6+5]})" "${DISK_RESULTS[(DISK_COUNT+1)*6+2]}" "(${DISK_RESULTS[(DISK_COUNT+1)*6+5]})"
			printf "%-10s | %-11s %8s | %-11s %8s\n" "Total" "${DISK_RESULTS[DISK_COUNT*6]}" "(${DISK_RESULTS[DISK_COUNT*6+3]})" "${DISK_RESULTS[(DISK_COUNT+1)*6]}" "(${DISK_RESULTS[(DISK_COUNT+1)*6+3]})"
			if [[ -n $JSON ]]; then
				JSON_RESULT+='{"bs":"'${BLOCK_SIZES[DISK_COUNT]}'","speed_r":'${DISK_RESULTS_RAW[DISK_COUNT*6+1]}',"iops_r":'${DISK_RESULTS_RAW[DISK_COUNT*6+4]}
				JSON_RESULT+=',"speed_w":'${DISK_RESULTS_RAW[DISK_COUNT*6+2]}',"iops_w":'${DISK_RESULTS_RAW[DISK_COUNT*6+5]}',"speed_rw":'${DISK_RESULTS_RAW[DISK_COUNT*6]}
				JSON_RESULT+=',"iops_rw":'${DISK_RESULTS_RAW[DISK_COUNT*6+3]}',"speed_units":"KBps"},'
				JSON_RESULT+='{"bs":"'${BLOCK_SIZES[DISK_COUNT+1]}'","speed_r":'${DISK_RESULTS_RAW[(DISK_COUNT+1)*6+1]}',"iops_r":'${DISK_RESULTS_RAW[(DISK_COUNT+1)*6+4]}
				JSON_RESULT+=',"speed_w":'${DISK_RESULTS_RAW[(DISK_COUNT+1)*6+2]}',"iops_w":'${DISK_RESULTS_RAW[(DISK_COUNT+1)*6+5]}',"speed_rw":'${DISK_RESULTS_RAW[(DISK_COUNT+1)*6]}
				JSON_RESULT+=',"iops_rw":'${DISK_RESULTS_RAW[(DISK_COUNT+1)*6+3]}',"speed_units":"KBps"},'
			fi
			DISK_COUNT=$((DISK_COUNT + 2))
		done
		[[ -n $JSON ]] && JSON_RESULT=${JSON_RESULT::${#JSON_RESULT}-1} && JSON_RESULT+=']'
	fi
fi

echo -e
# Clean up the specific disk test path and the general YABS temp directory
if [ -n "$TEST_PATH" ]; then
    rm -rf "$TEST_PATH/yabs_disk_test"
fi
rm -rf "$YABS_PATH"

YABS_END_TIME=$(date +%s)

function calculate_time_taken() {
	end_time=$1
	start_time=$2
	time_taken=$(( end_time - start_time ))
	if [ ${time_taken} -gt 60 ]; then
		min=$(( time_taken / 60 ))
		sec=$(( time_taken % 60 ))
		echo "YABS-FIO completed in ${min} min ${sec} sec"
	else
		echo "YABS-FIO completed in ${time_taken} sec"
	fi
	[[ -n $JSON ]] && JSON_RESULT+=",\"runtime\":{\"start\":$start_time,\"end\":$end_time,\"elapsed\":$time_taken}"
}

calculate_time_taken "$YABS_END_TIME" "$YABS_START_TIME"

if [[ -n $JSON ]]; then
	JSON_RESULT+="}"
	if [[ $JSON = *w* ]]; then
		echo "$JSON_RESULT" > "$JSON_FILE"
	fi
	if [[ $JSON = *s* ]]; then
		IFS=',' read -r -a JSON_SITES <<< "$JSON_SEND"
		for JSON_SITE in "${JSON_SITES[@]}"
		do
			if [[ -n $LOCAL_CURL ]]; then
				curl -s -H "Content-Type:application/json" -X POST --data ''"$JSON_RESULT"'' "$JSON_SITE"
			else
				wget -qO- --post-data=''"$JSON_RESULT"'' --header='Content-Type:application/json' "$JSON_SITE"
			fi
		done
	fi
	if [[ $JSON = *j* ]]; then
		echo -e
		echo "$JSON_RESULT"
	fi
fi

unset LC_ALL
