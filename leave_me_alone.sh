#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Root privileges required. Enter your password:"
    read -s -p "Password: " SUDO_PASS
    echo
    echo "$SUDO_PASS" | sudo -S "$0" "$@"
    exit $?
fi

REAL_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)

DISK_BEFORE=$(df / --output=used -B1 | tail -1)
declare -A FREED_STEPS

apt_cleanup() {
    apt-get autoremove --purge -y
    apt-get autoclean -y
    apt-get clean -y
    dpkg -l 2>/dev/null | awk '/^rc/{print $2}' | xargs -r dpkg --purge 2>/dev/null || true
}

kernel_cleanup() {
    CURRENT_KERNEL=$(uname -r)
    OLD_KERNELS=$(dpkg -l 'linux-image-*' 'linux-headers-*' 2>/dev/null | awk '/^ii/{print $2}' | grep -E 'linux-(image|headers)-[0-9]' | grep -v "$CURRENT_KERNEL" || true)
    if [[ -n "$OLD_KERNELS" ]]; then
        echo "$OLD_KERNELS" | xargs -r apt-get purge -y
        update-grub 2>/dev/null || true
    fi
}

journal_cleanup() {
    if command -v journalctl &>/dev/null; then
        journalctl --vacuum-time=3d --vacuum-size=50M 2>/dev/null || true
    fi
}

tmp_cleanup() {
    find /tmp -type f -atime +2 -delete 2>/dev/null || true
    find /tmp -type d -empty -delete 2>/dev/null || true
    find /var/tmp -type f -atime +2 -delete 2>/dev/null || true
    find /var/tmp -type d -empty -delete 2>/dev/null || true
    if command -v systemd-tmpfiles &>/dev/null; then
        systemd-tmpfiles --clean 2>/dev/null || true
    fi
}

snap_cleanup() {
    if command -v snap &>/dev/null; then
        snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r name rev; do
            snap remove "$name" --revision="$rev" 2>/dev/null || true
        done
        rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
    fi
}

flatpak_cleanup() {
    if command -v flatpak &>/dev/null; then
        flatpak uninstall --unused -y 2>/dev/null || true
    fi
}

trash_cleanup() {
    local trash_dir="$REAL_HOME/.local/share/Trash"
    if [[ -d "$trash_dir" ]]; then
        find "$trash_dir" -mindepth 1 -delete 2>/dev/null || true
    fi
}

thumbnails_cleanup() {
    local thumb_dir="$REAL_HOME/.cache/thumbnails"
    if [[ -d "$thumb_dir" ]]; then
        find "$thumb_dir" -type f -delete 2>/dev/null || true
    fi
}

user_cache_cleanup() {
    local cache_dir="$REAL_HOME/.cache"
    if [[ -d "$cache_dir" ]]; then
        find "$cache_dir" -type f -atime +30 -delete 2>/dev/null || true
        find "$cache_dir" -type d -empty -delete 2>/dev/null || true
    fi
}

old_logs_cleanup() {
    find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
    find /var/log -type f -name "*.old" -delete 2>/dev/null || true
    find /var/log -type f -name "*.1" -delete 2>/dev/null || true
    find /var/log -type f -name "*.2" -delete 2>/dev/null || true
    find /var/log -type f -name "*.3" -delete 2>/dev/null || true
}

run_step() {
    local name="$1"
    shift
    local before=$(df / --output=used -B1 | tail -1)
    "$@"
    local after=$(df / --output=used -B1 | tail -1)
    local freed=$(( before - after ))
    FREED_STEPS["$name"]=$freed
    if [[ $freed -gt 0 ]]; then
        echo "  freed: $(( freed / 1024 / 1024 )) MB"
    else
        echo "  no change"
    fi
}

echo "=== Ubuntu Cleanup ==="

echo "[1/10] APT..."
run_step "APT" apt_cleanup

echo "[2/10] Old kernels..."
run_step "Kernels" kernel_cleanup

echo "[3/10] Systemd journals..."
run_step "Journald" journal_cleanup

echo "[4/10] Temporary files..."
run_step "tmp" tmp_cleanup

echo "[5/10] Snap (disabled revisions + cache)..."
run_step "Snap" snap_cleanup

echo "[6/10] Flatpak (unused)..."
run_step "Flatpak" flatpak_cleanup

echo "[7/10] Trash..."
run_step "Trash" trash_cleanup

echo "[8/10] Thumbnails..."
run_step "Thumbnails" thumbnails_cleanup

echo "[9/10] Old user cache (>30 days)..."
run_step "User cache" user_cache_cleanup

echo "[10/10] Rotated logs (/var/log/*.gz, *.old, *.1-3)..."
run_step "Old logs" old_logs_cleanup

DISK_AFTER=$(df / --output=used -B1 | tail -1)
TOTAL_FREED=$(( DISK_BEFORE - DISK_AFTER ))

echo -e "\n=== Summary ==="
for step in "APT" "Kernels" "Journald" "tmp" "Snap" "Flatpak" "Trash" "Thumbnails" "User cache" "Old logs"; do
    mb=$(( ${FREED_STEPS[$step]} / 1024 / 1024 ))
    echo "$step: $mb MB"
done
echo "Total freed: $(( TOTAL_FREED / 1024 / 1024 )) MB"
echo "Current free space:"
df -h /
