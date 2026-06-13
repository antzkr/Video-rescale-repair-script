# Video Rescale and Repair Script

Version 3.2

# Changelog:
# rewrite to include positional parameter support, ffmpeg installed check, supported file extension check, show successful result, percentage & ETA display, added support
# for more filetypes, color tweaks, ncurses-style menus with dialog.

# PURPOSE

A simple bash script to convert videos to target resolution or repair damaged video files using ffmpeg.

Minimal system resource usage and is well suited to running in a headless environment (ie. no GUI).

# SYSTEM REQUIREMENTS

As long as your system can run ffmpeg, the minimal system requirements are sufficient. The more CPU and RAM you have, the faster the video conversion will be.

# INSTALLATION

Execute script with the first parameter to the source videos directory and the second parameter to the destination videos directory. Script cam be run as unprviledged user:
./video-rescale-repair-script-vX.sh <source-dir> <target-dir>
