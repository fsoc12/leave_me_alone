# System cleanup script for Ubuntu/Debian-based Linux distributions.

## Description

This script performs automated cleanup of system and user temporary files, package caches, old kernels, logs, and application caches. It reports freed space for each operation and requires root privileges.

## Features

- Cleans APT package cache and removes unused dependencies
- Removes old kernels except the currently running one
- Truncates systemd journals (keeps last 3 days / 50 MB)
- Cleans `/tmp` and `/var/tmp`
- Removes disabled Snap revisions and cache
- Removes unused Flatpak packages
- Empties user trash
- Deletes cached thumbnails
- Removes user cache files older than 30 days
- Deletes rotated log files (`.gz`, `.old`, `.1`-`.3`)

## Requirements

- Bash
- Ubuntu / Debian-based distribution
- Root access (script will request sudo automatically)

## Usage
 or just run it as user — it will ask for password and re-exec with sudo

```bash
chmod +x leave_me_alone.sh
sudo ./leave_me_alone.sh
