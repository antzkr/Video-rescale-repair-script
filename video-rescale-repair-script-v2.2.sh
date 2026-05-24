#!/bin/bash

# Version variable
VRS=2.2

# Changelog: rewrite to include positional parameter support,
# ffmpeg installed check, supported file extension check, and
# successful result display.

###################################################################
# Script to convert videos to target resolution or repair damaged #
# video files using ffmpeg.                                       #
# Usage:                                                          #
# ./video-rescale-repair-script-vX.sh <source-dir> <target-dir>   #
###################################################################

# Exit script on error
set -e

# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Reset
NC='\033[0m' # No Color

# Position parameters
SOURCE_D="$1"
DEST_D="$2"

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    echo -e "${RED}Error: ffmpeg is not installed. Please install ffmpeg first.${NC}"
    echo -e "${YELLOW}Ubuntu/Debian: sudo apt install ffmpeg${NC}"
    echo -e "${YELLOW}MacOS: brew install ffmpeg${NC}"
    echo -e "${YELLOW}Other: https://ffmpeg.org/download.html${NC}\n"
    exit 1
fi

# Notify ffmpeg is installed
echo -e "\n${BLUE}✓ ffmpeg is installed. Ready to proceed.${NC}\n"

# Correct usage check
if [[ -z "$SOURCE_D" || -z "$DEST_D" ]]; then
    echo -e "${YELLOW}Usage:${NC} ./video-rescale-repair-script-v$VRS.sh ${CYAN}<source-dir> <target-dir>${NC}\n"
    exit 1
fi

# Validate the source directory
if [[ ! -d "$SOURCE_D" ]]; then
    echo -e "\n${RED}Error:${NC} $SOURCE_D is not a valid directory. Please check.\n" >&2
    exit 1
fi

# Validate the destination directory
if [[ ! -d "$DEST_D" ]]; then
    echo -e "\n${RED}Error:${NC} $DEST_D is not a valid directory. Please check.\n" >&2
    exit 1
fi

# Check if source is readable
if [[ ! -r "$SOURCE_D" ]]; then
    echo -e "\n${RED}Error:${NC} Cannot read from $SOURCE_D directory. Please check permissions.\n"
    exit 1
fi

# Check if destination is writable
if [[ ! -w "$DEST_D" ]]; then
    echo -e "\n${RED}Error:${NC} Cannot write to $DEST_D directory. Please check permissions.\n"
    exit 1
fi

# Path confirmation
echo -e "${CYAN}$SOURCE_D${NC} selected as source directory."
echo -e "${CYAN}$DEST_D${NC} selected as destination directory.\n"

# Check if supported videos exist in source dir
shopt -s nullglob
VALID_VIDEOS_LIST=()
for ext in mp4 avi mkv webm; do
    for file in "$SOURCE_D"/*.$ext; do
        if [[ -f "$file" ]]; then
            VALID_VIDEOS_LIST+=("$file")
        fi
    done
done

if [[ ${#VALID_VIDEOS_LIST[@]} -eq 0 ]]; then
    echo -e "\n${RED}Error:${NC} No supported video files found in $SOURCE_D."
    echo -e "Supported video filetypes: mp4, avi, mkv, webm.\n"
    exit 1
fi

# Optional - Display found videos before execution
#echo -e "${GREEN}Found ${#VALID_VIDEOS_LIST[@]} video file(s) to process:${NC}"
#for video in "${VALID_VIDEOS_LIST[@]}"; do
#    echo -e "  • $(basename "$video")"
#done
#echo ""

# Video scaling function
videos_scale () {
    echo -e "${YELLOW}Select the target video scaling: ${NC}"
    PS3="Choice: "
    select RESOL in "640:360" "720:480" "1280:720" "1920:1080"; do
        if [[ -n "$RESOL" ]]; then
            echo -e "\n${BLUE}$RESOL${NC} resolution selected\n"
            break
        else
            echo -e "${RED}Invalid selection.${NC} Please choose a number from the list."
        fi
    done

    # Process each video file
    #echo -e "${BLUE}Rescaling videos in $SOURCE_D ...${NC}\n"
    for VIDEO in "${VALID_VIDEOS_LIST[@]}"; do
        FILENAME=$(basename "$VIDEO")
        OUTPUT_FILE="$DEST_D/${FILENAME%.*} [$RESOL].mp4"
        echo -e "${CYAN}Processing: $FILENAME${NC}"
        if ffmpeg -i "$VIDEO" -vf "scale=$RESOL" -c:a copy -y "$OUTPUT_FILE" 2>/dev/null; then
            echo -e "${GREEN}✓ Successfully rescaled:${NC} ${FILENAME}"
        else
            echo -e "${RED}✗ Failed to rescale:${NC} ${FILENAME}" >&2
        fi
        echo ""
    done
    echo -e "${GREEN}✓ Video rescaling completed.\n"
}

# Video repair function
videos_repair () {
    #echo -e "${BLUE}Repairing videos in $SOURCE_D ...${NC}\n"
    # Process each video file
    for VIDEO in "${VALID_VIDEOS_LIST[@]}"; do
        FILENAME=$(basename "$VIDEO")
        OUTPUT_FILE="$DEST_D/${FILENAME%.*} [repaired].mp4"
        echo -e "${CYAN}Repairing: $FILENAME${NC}"
        if ffmpeg -i "$VIDEO" -c:v libx264 -crf 22 -preset slow -y "$OUTPUT_FILE" 2>/dev/null; then
            echo -e "${GREEN}✓ Successfully repaired:${NC} ${FILENAME}"
        else
            echo -e "${RED}✗ Failed to repair:${NC} ${FILENAME}" >&2
        fi
        echo ""
    done
    echo -e "${GREEN}✓ Video repair completed.\n"
}

# Execute rescale or repair videos
echo -e "\n${YELLOW}══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}   Video Rescale & Repair Script v$VRS${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}\n"

echo -e "${YELLOW}Select from the following options:${NC}"
PS3="Choice: "
select CHOICE1 in "Rescale videos" "Repair videos" "Exit"; do
    if [[ "$CHOICE1" == "Exit" ]]; then
        echo -e "\n${BLUE}Exiting script. Goodbye!${NC}\n"
        exit 0
    elif [[ "$CHOICE1" == "Rescale videos" ]]; then
        echo
        videos_scale
        exit 0
    elif [[ "$CHOICE1" == "Repair videos" ]]; then
        echo
        videos_repair
        exit 0
    else
        echo -e "${RED}Invalid selection. Please choose a number from the list.${NC}"
    fi
done