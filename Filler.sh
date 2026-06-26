#!/bin/bash
# Kindle Disk Filler Utility for Linux/macOS
# Author: iiroak (https://github.com/iiroak)
# This tool fills the disk to prevent automatic updates on tablets
# that have not been registered. Useful for jailbreak preparation.

set -e

echo ""
echo "  +=============================================================+"
echo "  |           Kindle Disk Filler Utility v2.0                  |"
echo "  +============================================================+"
echo "  |  Fills disk to prevent auto-updates on unregistered        |"
echo "  |  tablets. Useful for jailbreak preparation.                |"
echo "  +============================================================+"
echo ""

dir="fill_disk"
mkdir -p "$dir"

die() {
    set +xe
    echo '================================ DIE ===============================' >&2
    echo >&2 "$*"
    echo >&2 "Call stack:"
    local n=$((${#BASH_LINENO[@]} - 1))
    local i=0
    while [ $i -lt $n ]; do
        echo >&2 "    [$i] -- line ${BASH_LINENO[i]} -- ${FUNCNAME[i + 1]}"
        i=$((i + 1))
    done
    echo >&2 '================================ END ==============================='
    [[ $- == *i* ]] && return 1 || exit 1
}

find_next_free_index() {
    local index=0
    while true; do
        if [ ! -f "$dir/file_$index" ]; then
            echo "$index"
            return
        fi
        index=$((index + 1))
    done
}

get_free_mb() {
    df -Pm $dir | awk 'NR==2 {print $4}'
}

totalFreeMB=$(get_free_mb)
files_created=0
files_deleted=0

interrupt() {
    printf '\n[!] Interrupted.\n'
    printf '    Files created: %d, files deleted: %d\n' "$files_created" "$files_deleted"
    printf '    Target directory: %s\n' "$dir"
    exit 1
}
trap interrupt INT TERM

create_file () {
    local size=$1 path=$2

    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "$size" "$path"  && return
    fi
    if command -v mkfile    >/dev/null 2>&1; then
        mkfile "$size" "$path"        && return
    fi

    dd if=/dev/zero of="$path" bs="$size" count=1 status=none
}

render_progress() {
    local percent=$1
    local status=$2
    local detail=$3
    local width=32
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    local bar empty_bar

    bar=$(printf '%*s' "$filled" '' | tr ' ' '=')
    empty_bar=$(printf '%*s' "$empty" '' | tr ' ' '-')

    printf '\r\033[2K  [%s%s] %3d%%  %s%s' "$bar" "$empty_bar" "$percent" "$status" "$detail"
}

free_space() {
    echo "[!] Start freeing space..."
    local freeMB=$(get_free_mb)
    while true; do
        if [[ $freeMB -ge $minFreeMB ]]; then
            break
        fi

        local info=$(ls -1Ss --block-size=M "$dir"/ | tail -n 1)
        [[ -z "$info" ]] && break
        local file="${dir}"/$(echo "$info" | awk '{print $2}')
        local size=$(echo "$info" | awk '{print $1}')

        [[ -e "${file}" ]] || die "File does not exist: '${file}'"
        rm "${file}" && files_deleted=$((files_deleted+1))

        freeMB=$(get_free_mb)
        echo "[>] File ${file} (${size}) deleted, now space: ${freeMB}, target space: ${minFreeMB}"
    done
}

fill_disk() {
    echo "[!] Start filling disk..."

    local i=$(find_next_free_index)
    while true; do
        local freeMB=$(get_free_mb)
        fillableMB=$((freeMB - minFreeMB))

        if [ "$fillableMB" -le 0 ]; then
            break
        fi

        if [ "$fillableMB" -ge 1024 ]; then
            local fileSize=1G
        elif [ "$fillableMB" -ge 100 ]; then
            fileSize=100M
        elif [ "$fillableMB" -ge 10 ]; then
            fileSize=10M
        else
            fileSize="${fillableMB}M"
        fi

        filePath="$dir/file_$i"

        usedMB=$((totalFreeMB - freeMB))
        percent=$((usedMB * 100 / targetFillMB))
        [ $percent -gt 100 ] && percent=100
        [ $percent -lt 0 ] && percent=0

        render_progress "$percent" "Creating: " "file_$i ($fileSize)"

        create_file "$fileSize" "$filePath"

        if [ ! -f "$filePath" ]; then
            break
        fi

        i=$(find_next_free_index)
        freeMB=$(get_free_mb)

        usedMB=$((totalFreeMB - freeMB))
        percent=$((usedMB * 100 / targetFillMB))
        [ $percent -gt 100 ] && percent=100
        [ $percent -lt 0 ] && percent=0

        remainingLabel="${freeMB} MB"
        [ $freeMB -ge 1024 ] && remainingLabel="$(awk "BEGIN {printf \"%.1f\", $freeMB/1024}") GB"

        files_created=$((files_created+1))
        render_progress "$percent" "Done:     " "file_$((i-1)) | Free: $remainingLabel"
    done
}

echo "How much free space (in MB) do you want to leave on disk?"
echo "It is highly recommended to leave only 20-50 MB (no more) to prevent updates."
echo ""
echo "  [1] 20 MB (default)"
echo "  [2] 50 MB"
echo "  [3] 100 MB"
echo "  [4] Custom value"
echo ""
read -p "  Enter your choice (1-4) [1]: " choice

case "$choice" in
    2) minFreeMB=50 ;;
    3) minFreeMB=100 ;;
    4)
        read -p "  Enter the minimum free space in MB (e.g., 30): " custom
        if [[ "$custom" =~ ^[0-9]+$ ]] && [ "$custom" -gt 0 ]; then
            minFreeMB=$custom
        else
            echo "Invalid input. Using default (20 MB)."
            minFreeMB=20
        fi
        ;;
    *) minFreeMB=20 ;;
esac

echo ""
echo "[>] Starting disk fill process..."
echo ""

totalFreeMB=$(get_free_mb)
if [[ $totalFreeMB -eq $minFreeMB ]]; then
    echo "[!] The requested free space is equal to the current free space. Nothing to do."
    echo ""
    read -p "Press Enter to exit..." _
    exit 0
fi

# If free space is below target, free space
if [[ $totalFreeMB -lt $minFreeMB ]]; then
    free_space
fi

totalFreeMB=$(get_free_mb)
targetFillMB=$((totalFreeMB - minFreeMB))

if [ "$targetFillMB" -gt 0 ]; then
    fill_disk
fi

printf '\n'
printf "  +---------------------------------------------------------+\n"
printf "  |  Disk fill complete!                                    |\n"
printf "  |  Files deleted: % 4d                                    |\n" $files_deleted
printf "  |  Files created: % 4d                                    |\n" $files_created
printf "  |  Target directory: %10s                           |\n" "$dir"
printf "  +---------------------------------------------------------+"
printf "\n"
read -p "Press Enter to exit..." _
