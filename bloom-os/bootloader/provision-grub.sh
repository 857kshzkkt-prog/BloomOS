#!/usr/bin/env bash
###############################################################################
# provision-grub.sh — GRUB Bootloader Provisioning for Bloom OS
#
# Standalone script to install GRUB to a target disk after a manual install
# or repair. Detects boot mode (BIOS vs UEFI) and installs accordingly.
#
# Usage: sudo ./provision-grub.sh <target_disk> <root_partition> [boot_partition]
#
# Examples:
#   sudo ./provision-grub.sh /dev/sda /dev/sda2 /dev/sda1
#   sudo ./provision-grub.sh /dev/nvme0n1 /dev/nvme0n1p2 /dev/nvme0n1p1
#
# If boot_partition is omitted and --use-esp is passed, it configures for UEFI
# with the ESP mounted at /boot.
###############################################################################

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[GRUB]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[GRUB]${NC} WARNING: $*"; }
log_error()   { echo -e "${RED}[GRUB]${NC} ERROR: $*"; exit 1; }
log_step()    { echo -e "\n${BLUE}═══ $* ═══${NC}"; }

preflight() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)."
    fi

    TARGET_DISK="${1:-}"
    ROOT_PART="${2:-}"
    BOOT_PART="${3:-}"

    if [[ -z "${TARGET_DISK}" || -z "${ROOT_PART}" ]]; then
        log_error "Usage: $0 <target_disk> <root_partition> [boot_partition]"
    fi

    if [[ ! -b "${TARGET_DISK}" ]]; then
        log_error "Target disk '${TARGET_DISK}' does not exist."
    fi
    if [[ ! -b "${ROOT_PART}" ]]; then
        log_error "Root partition '${ROOT_PART}' does not exist."
    fi

    if [[ -d /sys/firmware/efi/efivars ]]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi

    log_info "Target disk: ${TARGET_DISK}"
    log_info "Root partition: ${ROOT_PART}"
    log_info "Boot partition: ${BOOT_PART:-"(none — using ESP)"}"
    log_info "Boot mode: ${BOOT_MODE^^}"
}

validate_mounts() {
    if ! mountpoint -q /mnt; then
        log_error "/mnt is not mounted. Mount root partition first."
    fi
    if ! mountpoint -q /mnt/boot; then
        log_error "/mnt/boot is not mounted. Mount boot/ESP partition first."
    fi
}

install_grub() {
    log_step "Installing GRUB to ${TARGET_DISK}"

    local root_uuid boot_uuid
    root_uuid=$(blkid -s UUID -o value "${ROOT_PART}")
    boot_uuid=$(blkid -s UUID -o value "${BOOT_PART:-$(blkid -s UUID -o value "${ROOT_PART}")}")

    if [[ "${BOOT_MODE}" == "uefi" ]]; then
        arch-chroot /mnt grub-install --target=x86_64-efi --boot-directory=/boot \
            --efi-directory=/boot --recheck
    else
        arch-chroot /mnt grub-install --target=i386-pc --boot-directory=/boot \
            --recheck "${TARGET_DISK}"
    fi

    log_info "Deploying custom kernel entries..."

    cat > /mnt/etc/grub.d/40_custom << GRUBEOF
#!/bin/sh
exec tail -n +3 \$0

menuentry 'Bloom OS (Blossom kernel)' --class linux --class bloom {
    search --no-floppy --fs-uuid --set=root ${boot_uuid}
    linux /vmlinuz-blossom root=UUID=${root_uuid} rw quiet loglevel=3
    initrd /initramfs-blossom.img
}

menuentry 'Bloom OS (stock kernel)' --class linux --class bloom {
    search --no-floppy --fs-uuid --set=root ${boot_uuid}
    linux /vmlinuz-linux root=UUID=${root_uuid} rw quiet loglevel=3
    initrd /initramfs-linux.img
}
GRUBEOF

    chmod +x /mnt/etc/grub.d/40_custom

    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

    log_success "GRUB installed and configured"
}

verify() {
    log_step "Verifying GRUB installation"

    if [[ -f /mnt/boot/grub/grub.cfg ]]; then
        log_info "Config: /boot/grub/grub.cfg"
    else
        log_warn "Config not found at /boot/grub/grub.cfg"
    fi

    if [[ -f /mnt/boot/vmlinuz-blossom ]]; then
        log_info "Kernel: /boot/vmlinuz-blossom"
    else
        log_warn "Kernel not found at /boot/vmlinuz-blossom"
    fi

    if [[ -f /mnt/boot/initramfs-blossom.img ]]; then
        log_info "Initramfs: /boot/initramfs-blossom.img"
    fi

    echo ""
    grep -A 5 "menuentry 'Bloom OS" /mnt/boot/grub/grub.cfg 2>/dev/null || \
        log_warn "Custom entries not found in grub.cfg"

    echo ""
    log_info "═══════════════════════════════════════════════════"
    log_info "  GRUB INSTALLATION COMPLETE"
    log_info "═══════════════════════════════════════════════════"
    log_info "  Disk: ${TARGET_DISK}"
    log_info "  Boot: ${BOOT_MODE^^}"
    log_info "  Root: ${ROOT_PART}"
    log_info "═══════════════════════════════════════════════════"
}

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║    BLOOM OS — GRUB BOOTLOADER PROVISIONING          ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    preflight "$@"
    validate_mounts
    install_grub
    verify

    log_info "Run 'exit; umount -R /mnt; reboot' when ready"
}

main "$@"
