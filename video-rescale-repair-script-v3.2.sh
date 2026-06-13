#!/bin/bash

# Version variable
VRS=v3.2

###################################################################
# Script to convert videos to target resolution or repair damaged #
# video files using ffmpeg.                                       #
# Usage:                                                          #
# ./video-rescale-repair-script-vX.sh <source-dir> <target-dir>   #
###################################################################

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

# Positional parameters
SOURCE_D="$1"
DEST_D="$2"

# Function to format time (seconds to HH:MM:SS or MM:SS)
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    if [ $hours -gt 0 ]; then
        printf "%d:%02d:%02d" $hours $minutes $secs
    else
        printf "%02d:%02d" $minutes $secs
    fi
}

# Function to get video duration using ffprobe
get_video_duration() {
    local video_file="$1"
    if command -v ffprobe &> /dev/null; then
        local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
        if [[ -n "$duration" && "$duration" != "N/A" ]]; then
            printf "%.0f" "$duration"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# Function to display progress percentage and time stats
show_progress() {
    local current=$1
    local total=$2
    local start_time=$3

    # Calculate percentage
    local percent=0
    if [ $total -gt 0 ]; then
        percent=$((current * 100 / total))
        [ $percent -gt 100 ] && percent=100
    fi

    # Calculate elapsed time
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    # Calculate ETA
    local eta_text="calculating..."
    if [ $current -gt 0 ] && [ $total -gt 0 ]; then
        local remaining=$((total - current))
        if command -v bc &> /dev/null && [ $elapsed -gt 0 ]; then
            local speed=$(echo "scale=2; $current / $elapsed" | bc 2>/dev/null)
            if [ -n "$speed" ] && [ $(echo "$speed > 0" | bc) -eq 1 ]; then
                local eta=$(echo "scale=0; $remaining / $speed" | bc 2>/dev/null)
                if [ -n "$eta" ] && [ $eta -gt 0 ]; then
                    eta_text=$(format_time $eta)
                fi
            fi
        fi
    fi

    # Display stats
    printf "\r${YELLOW}Progress:${NC} %3d%% ${CYAN}|${NC} Elapsed: %s ${CYAN}|${NC} ETA: ${GREEN}%s${NC}    " \
        "$percent" "$(format_time $elapsed)" "$eta_text"
}

# Video scaling function with percentage and time stats
videos_scale() {
    # Dialog 2nd selection configuration
    local SCALE_HEIGHT=12
    local SCALE_WIDTH=70
    local SCALE_MENU_HEIGHT=9
    local BACKTITLE="Video rescale & repair script"
    local TITLE="Video rescale & repair script $VRS"
    local MENU=$'\nSelect the target video scaling resolution:'

    # Options array: Tag "Description"
    # The 'Tag' is returned if selected. Description is for display only.
    local RESOL_OPTIONS=(
        "640:360" "Low resolution"
        "720:480" "DVD resolution"
        "1280:720" "HD resolution"
        "1920:1080" "True HD resolution"
    )

    local SELECTED_RESOL=""
    while true; do
        # Invoke dialog
        SELECTED_RESOL=$(dialog --clear \
            --backtitle "$BACKTITLE" \
            --title "$TITLE" \
            --menu "$MENU" \
            $SCALE_HEIGHT $SCALE_WIDTH $SCALE_MENU_HEIGHT \
            "${RESOL_OPTIONS[@]}" \
            2>&1 >/dev/tty)

        # Capture exit status
        local exit_status=$?

        # Handle Dialog Exit Codes
        if [ $exit_status -eq 1 ] || [ $exit_status -eq 255 ]; then
            # User pressed Cancel, ESC, or Ctrl+C
            clear
            echo -e "${RED}Script halted and will exit.${NC}\n"
            exit 1
        fi

        # Handle Selection
        if [[ -n "$SELECTED_RESOL" ]]; then
            clear
            echo -e "\n${BLUE}'$SELECTED_RESOL'${NC} resolution selected\n"
            break
        fi
    done

    # Check for ffprobe
    if ! command -v ffprobe &> /dev/null; then
        echo -e "${RED}Error: ffprobe is required for progress tracking. Please install ffmpeg (includes ffprobe).${NC}\n"
        exit 1
    fi

    # Check for bc
    if ! command -v bc &> /dev/null; then
        echo -e "${YELLOW}Warning: bc is not installed. ETA calculations will be disabled.${NC}"
        echo -e "${YELLOW}Install bc for better progress display: sudo apt install bc${NC}\n"
    fi

    local total_files=${#VALID_VIDEOS_LIST[@]}
    local current_file=0
    local success_count=0
    local fail_count=0

    for VIDEO in "${VALID_VIDEOS_LIST[@]}"; do
        ((current_file++))
        FILENAME=$(basename "$VIDEO")
        OUTPUT_FILE="$DEST_D/${FILENAME%.*} [$SELECTED_RESOL].mp4"

        echo -e "\n${CYAN}[$current_file/$total_files]${NC} ${CYAN}Processing:${NC} $FILENAME"

        # Get video duration
        local total_duration=$(get_video_duration "$VIDEO")

        if [[ -z "$total_duration" || "$total_duration" -eq 0 ]]; then
            echo -e "  ${YELLOW}Warning:${NC} Cannot determine video duration. Running without progress display..."

            # Run ffmpeg normally without progress tracking
            if ffmpeg -i "$VIDEO" -vf "scale=$SELECTED_RESOL" -c:a copy -y "$OUTPUT_FILE" 2>/dev/null; then
                echo -e "  ${GREEN}✓ Successfully rescaled:${NC} $FILENAME"
                ((success_count++))
            else
                echo -e "  ${RED}✗ Failed to rescale:${NC} $FILENAME"
                ((fail_count++))
            fi
        else
            echo -e "  ${CYAN}Starting conversion...${NC}"

            # Create temporary file for ffmpeg progress
            local progress_file=$(mktemp)

            # Run ffmpeg with progress output to file
            ffmpeg -i "$VIDEO" -vf "scale=$SELECTED_RESOL" -c:a copy -y "$OUTPUT_FILE" \
                -progress "$progress_file" -nostats 2>/dev/null &
            local ffmpeg_pid=$!

            # Start time for ETA calculation
            local start_time=$(date +%s)
            local last_percent=-1

            # Monitor progress by reading the progress file periodically
            while kill -0 $ffmpeg_pid 2>/dev/null; do
                if [ -f "$progress_file" ]; then
                    # Get the latest out_time_ms
                    local out_time_ms=$(grep "out_time_ms" "$progress_file" 2>/dev/null | tail -1 | cut -d'=' -f2)

                    if [[ -n "$out_time_ms" && "$out_time_ms" != "N/A" ]]; then
                        # Convert to seconds (remove last 3 digits for ms to seconds)
                        local current_sec=$((out_time_ms / 1000000))

                        if [ $current_sec -gt 0 ]; then
                            local percent=$((current_sec * 100 / total_duration))
                            [ $percent -gt 100 ] && percent=100

                            # Update display only when percentage changes
                            if [ $percent -ne $last_percent ]; then
                                show_progress "$current_sec" "$total_duration" "$start_time"
                                last_percent=$percent
                            fi
                        fi
                    fi
                fi
                sleep 1  # Update every second to reduce CPU usage
            done

            # Clear the line and wait for ffmpeg to finish
            printf "\r%*s\r" 80 ""
            wait $ffmpeg_pid
            local ffmpeg_exit=$?

            # Clean up
            rm -f "$progress_file"

            if [ $ffmpeg_exit -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
                echo -e "  ${GREEN}✓ Successfully rescaled:${NC} $FILENAME"
                ((success_count++))
            else
                echo -e "  ${RED}✗ Failed to rescale:${NC} $FILENAME"
                ((fail_count++))
            fi
        fi
    done

    echo -e "\n${GREEN}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Video rescaling completed!${NC}"
    echo -e "  Successful: ${GREEN}$success_count${NC}"
    echo -e "  Failed: ${RED}$fail_count${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════${NC}\n"
}

# Video repair function with percentage and time stats
videos_repair () {
    # Check for ffprobe
    if ! command -v ffprobe &> /dev/null; then
        echo -e "${RED}Error: ffprobe is required for progress tracking. Please install ffmpeg (includes ffprobe).${NC}\n"
        exit 1
    fi

    # Check for bc
    if ! command -v bc &> /dev/null; then
        echo -e "${YELLOW}Warning: bc is not installed. ETA calculations will be disabled.${NC}"
        echo -e "${YELLOW}Install bc for better progress display: sudo apt install bc${NC}\n"
    fi

    local total_files=${#VALID_VIDEOS_LIST[@]}
    local current_file=0
    local success_count=0
    local fail_count=0

    for VIDEO in "${VALID_VIDEOS_LIST[@]}"; do
        ((current_file++))
        FILENAME=$(basename "$VIDEO")
        OUTPUT_FILE="$DEST_D/${FILENAME%.*} [repaired].mp4"

        echo -e "\n${CYAN}[$current_file/$total_files]${NC} ${CYAN}Repairing:${NC} $FILENAME"

        # Get video duration
        local total_duration=$(get_video_duration "$VIDEO")

        if [[ -z "$total_duration" || "$total_duration" -eq 0 ]]; then
            echo -e "  ${YELLOW}Warning:${NC} Cannot determine video duration. Running without progress display..."

            # Run ffmpeg normally without progress tracking
            if ffmpeg -i "$VIDEO" -c:v libx264 -crf 22 -preset slow -y "$OUTPUT_FILE" 2>/dev/null; then
                echo -e "  ${GREEN}✓ Successfully repaired:${NC} $FILENAME"
                ((success_count++))
            else
                echo -e "  ${RED}✗ Failed to repair:${NC} $FILENAME"
                ((fail_count++))
            fi
        else
            echo -e "  ${CYAN}Starting repair...${NC}"

            # Create temporary file for ffmpeg progress
            local progress_file=$(mktemp)

            # Run ffmpeg with progress output to file
            ffmpeg -i "$VIDEO" -c:v libx264 -crf 22 -preset slow -y "$OUTPUT_FILE" \
                -progress "$progress_file" -nostats 2>/dev/null &
            local ffmpeg_pid=$!

            # Start time for ETA calculation
            local start_time=$(date +%s)
            local last_percent=-1

            # Monitor progress by reading the progress file periodically
            while kill -0 $ffmpeg_pid 2>/dev/null; do
                if [ -f "$progress_file" ]; then
                    # Get the latest out_time_ms
                    local out_time_ms=$(grep "out_time_ms" "$progress_file" 2>/dev/null | tail -1 | cut -d'=' -f2)

                    if [[ -n "$out_time_ms" && "$out_time_ms" != "N/A" ]]; then
                        # Convert to seconds
                        local current_sec=$((out_time_ms / 1000000))

                        if [ $current_sec -gt 0 ]; then
                            local percent=$((current_sec * 100 / total_duration))
                            [ $percent -gt 100 ] && percent=100

                            # Update display only when percentage changes
                            if [ $percent -ne $last_percent ]; then
                                show_progress "$current_sec" "$total_duration" "$start_time"
                                last_percent=$percent
                            fi
                        fi
                    fi
                fi
                sleep 1  # Update every second to reduce CPU usage
            done

            # Clear the line and wait for ffmpeg to finish
            printf "\r%*s\r" 80 ""
            wait $ffmpeg_pid
            local ffmpeg_exit=$?

            # Clean up
            rm -f "$progress_file"

            if [ $ffmpeg_exit -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
                echo -e "  ${GREEN}✓ Successfully repaired:${NC} $FILENAME"
                ((success_count++))
            else
                echo -e "  ${RED}✗ Failed to repair:${NC} $FILENAME"
                ((fail_count++))
            fi
        fi
    done

    echo -e "\n${GREEN}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Video repair completed!${NC}"
    echo -e "  Successful: ${GREEN}$success_count${NC}"
    echo -e "  Failed: ${RED}$fail_count${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════${NC}\n"
}

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo -e "'Dialog' is not installed. Installing..."
    sudo apt install dialog -y
fi

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    echo -e "'Ffmpeg' is not installed. Installing..."
    sudo apt install ffmpeg -y
fi

# Check for ffprobe
if ! command -v ffprobe &> /dev/null; then
    echo -e "${YELLOW}Warning: ffprobe not found. Progress tracking requires ffprobe.${NC}"
    echo -e "${YELLOW}Please ensure ffmpeg is properly installed (includes ffprobe).${NC}\n"
    exit 1
fi

# Notify packages are available
echo -e "\n${BLUE}✓ Required packages are available to use. Ready to proceed...${NC}\n"

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
echo -e "${CYAN}══════════════════════════════════════════════${NC}\n"
echo -e "${CYAN}$SOURCE_D${NC} source dir"
echo -e "${CYAN}$DEST_D${NC} destination dir\n"

# Check if supported videos exist in source dir
shopt -s nullglob
VALID_VIDEOS_LIST=()
for ext in mp4 avi mkv webm 3gp flv wmv mts mov; do
    for file in "$SOURCE_D"/*.$ext; do
        if [[ -f "$file" ]]; then
            VALID_VIDEOS_LIST+=("$file")
        fi
    done
done

if [[ ${#VALID_VIDEOS_LIST[@]} -eq 0 ]]; then
    echo -e "\n${RED}Error:${NC} No supported video files found in $SOURCE_D."
    echo -e "Supported filetypes: mp4, avi, mkv, webm, 3gp, flv, wmv, mts, mov.\n"
    exit 1
fi

# Show found videos
echo -e "${CYAN}Found ${#VALID_VIDEOS_LIST[@]} video file(s) to process:${NC}"
for video in "${VALID_VIDEOS_LIST[@]}"; do
    echo -e "  • $(basename "$video")"
done
echo ""

####################################
# Execute rescale or repair videos #
####################################
# Dialog first selection configuration
MENU_HEIGHT=19
MENU_WIDTH=70
MENU_LIST_HEIGHT=10
BACKTITLE="Video rescale & repair script"
TITLE="Video rescale & repair script $VRS"
MENU_TEXT=$'\nSimple script using ffmpeg to batch rescale video resolutions or repair damaged video files (incomplete, broken indexes, etc).\n\nWarning: existing video files will be overwritten. Please check destination dir before proceeding. Filenames should not contain any special chars and file extensions (eg. mp4, mkv) should be in lowercase.\n\nSupported filetypes: mp4, avi, mkv, webm, 3gp, flv, wmv, mts, mov\n'

# Options array: Tag "Description"
# The 'Tag' is returned if selected. Description is for display only.
CHOICE_OPTIONS=(
    "Rescale videos"  "Change video resolution"
    "Repair videos"  "Repair video with 'slow' setting"
    "Exit" "Cancel and Exit Script"
)

while true; do
    # Invoke dialog
    SELECTED_CHOICE=$(dialog --clear \
        --backtitle "$BACKTITLE" \
        --title "$TITLE" \
        --menu "$MENU_TEXT" \
        $MENU_HEIGHT $MENU_WIDTH $MENU_LIST_HEIGHT \
        "${CHOICE_OPTIONS[@]}" \
        2>&1 >/dev/tty)

    # Capture exit status
    exit_status=$?

    # Handle Dialog Exit Codes
    if [ $exit_status -eq 1 ] || [ $exit_status -eq 255 ]; then
        # User pressed Cancel, ESC, or Ctrl+C
        clear
        echo -e "${RED}Script halted and will exit.${NC}\n"
        exit 1
    fi

    # Handle Selection
    if [[ $SELECTED_CHOICE == "Exit" ]]; then
        clear
        echo -e "${BLUE}Exit option chosen. Script will exit.${NC}\n"
        exit 0
    elif [[ $SELECTED_CHOICE == "Rescale videos" ]]; then
        clear
        videos_scale
        exit 0
    elif [[ $SELECTED_CHOICE == "Repair videos" ]]; then
        clear
        videos_repair
        exit 0
    fi
done
