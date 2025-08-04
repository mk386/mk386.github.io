#!/bin/bash

DEVICE="/dev/sda"
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

printf "%-4s | %-15s | %-20s | %-8s | %-16s | %-21s | %-11s | %-6s | %-8s\n" \
  "Slot" "Serial Number" "Model" "Size" "Power-On Hours" "Reallocated Sectors" "Temp (°C)" "Health" "Status"
printf -- "-----|-----------------|----------------------|----------|------------------|-----------------------|------------|--------|--------\n"

for SLOT in {0..11}; do
    OUTPUT=$(smartctl -a -d megaraid,$SLOT $DEVICE 2>/dev/null)

    SERIAL=$(echo "$OUTPUT" | grep -i "Serial number" | awk -F: '{print $2}' | xargs)
    MODEL=$(echo "$OUTPUT" | grep -i "Product:" | awk -F: '{print $2}' | xargs)
    SIZE=$(echo "$OUTPUT" | grep "User Capacity" | sed -E 's/.*\[([0-9.]+ [A-Z]+)\]/\1/')
    HOURS=$(echo "$OUTPUT" | grep "number of hours powered up" | awk -F= '{print $2}' | xargs)
    TEMP=$(echo "$OUTPUT" | grep "Current Drive Temperature" | awk -F: '{print $2}' | xargs | cut -d' ' -f1)
    REALLOC=$(echo "$OUTPUT" | grep "reassigned" | grep "Total new blocks" | awk -F= '{print $2}' | xargs)
    HEALTH=$(echo "$OUTPUT" | grep "SMART Health Status" | awk -F: '{print $2}' | xargs)

    [[ -z "$SERIAL" ]] && SERIAL="N/A"
    [[ -z "$MODEL" ]] && MODEL="N/A"
    [[ -z "$SIZE" ]] && SIZE="N/A"
    [[ -z "$HOURS" ]] && HOURS="N/A"
    [[ -z "$TEMP" ]] && TEMP="N/A"
    [[ -z "$REALLOC" ]] && REALLOC="0"
    [[ -z "$HEALTH" ]] && HEALTH="N/A"

    STATUS="GOOD"
    COLOR="$NC"

    # 重新分配區塊數異常
    if [[ "$REALLOC" =~ ^[0-9]+$ ]] && [ "$REALLOC" -ge 10 ]; then
        STATUS="WARN"
        COLOR="$YELLOW"
    fi

    # 健康狀態異常
    if [[ "$HEALTH" != "OK" ]]; then
        STATUS="FAIL"
        COLOR="$RED"
    fi

    # 高溫警告
    if [[ "$TEMP" =~ ^[0-9]+$ ]] && [ "$TEMP" -ge 45 ]; then
        STATUS="HOT"
        COLOR="$RED"
    fi

    printf "${COLOR}%-4s | %-15s | %-20s | %-8s | %-16s | %-21s | %-11s | %-6s | %-8s${NC}\n" \
      "$SLOT" "$SERIAL" "$MODEL" "$SIZE" "$HOURS" "$REALLOC" "$TEMP C" "$HEALTH" "$STATUS"
done


