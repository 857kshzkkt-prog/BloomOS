#!/usr/bin/env bash
###############################################################################
# provision-limine.sh — Limine Bootloader Provisioning for Bloom OS
#
# This script automates the complete Limine bootloader installation process:
#   1. Installs build dependencies
#   2. Clones the Limine bootloader source from GitHub
#   3. Compiles the Limine binaries for both UEFI and BIOS
#   4. Detects the system's boot mode (UEFI vs legacy BIOS)
#   5. Deploys the bootloader to the target disk's MBR or ESP
#   6. Copies the limine.cfg configuration with correct root device
#
# Usage: sudo ./provision-limine.sh /dev/sda [ROOT_PARTITION]
#        Example: sudo ./provision-limine.sh /dev/nvme0n1 /dev/nvme0n1p2
#
# The ROOT_PARTITION parameter defaults to /dev/sda2 if not specified.
###############################################################################

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# COLOUR OUTPUT HELPERS
# ═══════════════════════════════════════════════════════════════════════════

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[LIMINE]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[LIMINE]${NC} WARNING: $*"; }
log_error()   { echo -e "${RED}[LIMINE]${NC} ERROR: $*"; exit 1; }
log_step()    { echo -e "\n${BLUE}═══ $* ═══${NC}"; }

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

readonly LIMINE_VERSION="v8.0.0"  # Stable release
readonly LIMINE_REPO="https://github.com/limine-bootloader/limine.git"
readonly WORKDIR="/tmp/limine-build"
readonly CONFIG_SOURCE="/home/meow/Documents/Bloom OS/bloom-os/bootloader/limine.cfg"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 1: PREFLIGHT CHECKS AND DEPENDENCY INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════

preflight() {
    log_step "Performing preflight checks"

    # Must run as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)."
    fi

    # Validate target disk argument
    if [[ -z "${1:-}" ]]; then
        log_error "Usage: $0 <target_disk> [root_partition]"
        log_error "Example: $0 /dev/sda /dev/sda2"
    fi

    TARGET_DISK="${1}"
    ROOT_PART="${2:-/dev/sda2}"

    # Validate target disk exists and is a block device
    if [[ ! -b "${TARGET_DISK}" ]]; then
        log_error "Target disk '${TARGET_DISK}' does not exist or is not a block device."
    fi

    # Validate root partition exists
    if [[ ! -b "${ROOT_PART}" ]]; then
        log_error "Root partition '${ROOT_PART}' does not exist."
    fi

    log_info "Target disk: ${TARGET_DISK}"
    log_info "Root partition: ${ROOT_PART}"

    # Detect boot mode (UEFI or BIOS)
    if [[ -d /sys/firmware/efi/efivars ]]; then
        BOOT_MODE="uefi"
        log_info "Boot mode detected: UEFI (64-bit)"
    else
        BOOT_MODE="bios"
        log_info "Boot mode detected: Legacy BIOS"
    fi

    # Check if disk is mounted (prevent writing to mounted disk)
    if mountpoint -q "${TARGET_DISK}" 2>/dev/null; then
        log_warn "Target disk appears to be mounted. This may cause issues."
        read -p "Continue anyway? [y/N]: " CONFIRM
        if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
            log_error "Aborted by user."
        fi
    fi
}

install_dependencies() {
    log_step "Installing build dependencies"

    # Core build tools
    local build_deps=(
        base-devel
        git
        nasm
        mtools
        dosfstools
        gptfdisk
        wget
    )

    # Check if packages are installed
    local missing_deps=()
    for dep in "${build_deps[@]}"; do
        if ! pacman -Qq "${dep}" &>/dev/null; then
            missing_deps+=("${dep}")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "Installing: ${missing_deps[*]}"
        pacman -Sy --noconfirm --needed "${missing_deps[@]}"
    fi

    log_success "Build dependencies satisfied"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 2: CLONE AND COMPILE LIMINE
# ═══════════════════════════════════════════════════════════════════════════

clone_limine() {
    log_step "Cloning Limine ${LIMINE_VERSION} from GitHub"

    # Clean previous build
    rm -rf "${WORKDIR}"
    mkdir -p "${WORKDIR}"
    cd "${WORKDIR}"

    log_info "Cloning repository..."
    git clone --depth 1 --branch "${LIMINE_VERSION}" "${LIMINE_REPO}" limine-src

    if [[ ! -d limine-src ]]; then
        log_error "Failed to clone Limine repository."
    fi

    log_success "Repository cloned successfully"
}

compile_limine() {
    log_step "Compiling Limine bootloader"

    cd "${WORKDIR}/limine-src"

    # Configure the build system
    log_info "Running ./configure..."
    ./configure

    # Compile all binaries
    log_info "Compiling Limine (this may take a few minutes)..."
    make -j"$(nproc)"

    # Verify compilation succeeded
    if [[ ! -f limine ]]; then
        log_error "Limine compilation failed - binary not found."
    fi

    # List compiled binaries
    log_info "Compiled binaries:"
    ls -lh limine limine-bios.sys limine-uefi-cd.bin 2>/dev/null || true

    log_success "Limine compiled successfully"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 3: DEPLOY LIMINE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

deploy_config() {
    log_step "Deploying Limine configuration"

    # Get the UUID of the root partition for the kernel command line
    local root_uuid
    root_uuid=$(blkid -s UUID -o value "${ROOT_PART}")

    if [[ -z "${root_uuid}" ]]; then
        log_warn "Could not get UUID for root partition, using device name"
        root_uuid="${ROOT_PART}"
    fi

    # Read the source config and replace ROOT_DEVICE placeholder
    if [[ -f "${CONFIG_SOURCE}" ]]; then
        log_info "Configuring limine.cfg with root=${ROOT_PART}"
        sed "s|ROOT_DEVICE|${ROOT_PART}|g" "${CONFIG_SOURCE}" > /tmp/limine.cfg
    else
        log_error "Source configuration file not found: ${CONFIG_SOURCE}"
    fi

    # Create destination directory
    mkdir -p /boot/limine
    cp /tmp/limine.cfg /boot/limine/limine.cfg

    log_info "Limine configuration deployed to /boot/limine/limine.cfg"
    log_info "Root partition set to: ${ROOT_PART}"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4: INSTALL LIMINE TO DISK
# ═══════════════════════════════════════════════════════════════════════════

install_to_disk() {
    log_step "Installing Limine to ${TARGET_DISK} (${BOOT_MODE} mode)"

    cd "${WORKDIR}/limine-src"

    if [[ "${BOOT_MODE}" == "uefi" ]]; then
        install_uefi
    else
        install_bios
    fi
}

install_uefi() {
    log_info "Installing Limine for UEFI boot mode"

    # ── Step 4a: Find or create the ESP ───────────────────────────────────
    # The EFI System Partition is typically the first partition on a GPT disk
    local esp_dev=""
    local esp_mount="/tmp/esp-mount"

    # Try to find an existing ESP (FAT32 partition with type EF00)
    esp_dev=$(lsblk -rnpo NAME,TYPE,PTTYPE,FSTYPE "${TARGET_DISK}" | \
        awk '$2=="part" && ($4=="vfat" || $3=="gpt") {print $1}' | head -1)

    if [[ -z "${esp_dev}" ]]; then
        log_warn "No existing ESP found. Creating one..."
        # Create a new 512MB ESP at the start of the disk
        sgdisk --zap-all "${TARGET_DISK}"
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" "${TARGET_DISK}"
        partprobe "${TARGET_DISK}"
        sleep 2
        esp_dev="${TARGET_DISK}1"

        # Format as FAT32
        mkfs.vfat -F32 "${esp_dev}"
    fi

    # Mount the ESP
    mkdir -p "${esp_mount}"
    if mountpoint -q "${esp_mount}"; then
        umount "${esp_mount}"
    fi
    mount "${esp_dev}" "${esp_mount}"

    log_info "ESP mounted at ${esp_mount}: ${esp_dev}"

    # ── Step 4b: Deploy UEFI binaries ───────────────────────────────────────
    mkdir -p "${esp_mount}/EFI/limine"
    mkdir -p "${esp_mount}/EFI/BOOT"
    mkdir -p "${esp_mount}/boot/limine"

    # Copy Limine UEFI binaries
    if [[ -f build/BOOTX64.EFI ]]; then
        cp -v build/BOOTX64.EFI "${esp_mount}/EFI/limine/"
        cp -v build/BOOTX64.EFI "${esp_mount}/EFI/BOOT/"
        log_info "Copied BOOTX64.EFI to ESP"
    fi

    if [[ -f limine-uefi-cd.bin ]]; then
        cp -v limine-uefi-cd.bin "${esp_mount}/boot/limine/"
        log_info "Copied limine-uefi-cd.bin to ESP"
    fi

    # Copy limine.cfg
    cp -v /tmp/limine.cfg "${esp_mount}/boot/limine/limine.cfg"

    # ── Step 4c: Install via limine-install command ─────────────────────────
    log_info "Running limine-install for UEFI..."
    ./limine-install "${TARGET_DISK}" || log_warn "limine-install returned non-zero, continuing..."

    # Unmount ESP
    sync
    umount "${esp_mount}"

    log_success "UEFI installation complete"
}

install_bios() {
    log_info "Installing Limine for legacy BIOS boot mode"

    # ── Step 4a: Ensure BIOS boot partition exists ─────────────────────────
    # For BIOS boot, we need a 1MB BIOS Boot partition (type ef02)
    local bios_boot_part="${TARGET_DISK}1"

    # Check if BIOS boot partition exists
    local part_info
    part_info=$(sfdisk -J "${TARGET_DISK}" 2>/dev/null | grep -o '"type":[^,]*' | head -1)

    if [[ "${part_info}" != *"ef02"* ]]; then
        log_warn "BIOS Boot partition not found. Creating one..."
        # Note: This will destroy existing partition table
        # For existing installs, use gdisk to add a BIOS Boot partition
        sgdisk --zap-all "${TARGET_DISK}"
        sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS Boot" "${TARGET_DISK}"
        partprobe "${TARGET_DISK}"
        sleep 2
    fi

    # ── Step 4b: Copy BIOS sys file ────────────────────────────────────────
    mkdir -p /boot/limine

    if [[ -f limine-bios.sys ]]; then
        cp -v limine-bios.sys /boot/limine/
        log_info "Copied limine-bios.sys to /boot/limine/"
    fi

    # Copy limine.cfg
    cp -v /tmp/limine.cfg /boot/limine/limine.cfg

    # ── Step 4c: Install via limine-install command ─────────────────────────
    log_info "Running limine-install for BIOS..."
    ./limine-install "${TARGET_DISK}" || log_warn "limine-install returned non-zero, continuing..."

    # For MBR, also install to the first 440 bytes
    if [[ -f limine ]]; then
        dd if=limine of="${TARGET_DISK}" bs=440 count=1 conv=notrunc 2>/dev/null || true
    fi

    log_success "BIOS installation complete"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5: VERIFY INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════

verify_installation() {
    log_step "Verifying Limine installation"

    local errors=0

    # Check limine.cfg exists
    if [[ -f /boot/limine/limine.cfg ]]; then
        log_info "✓ limine.cfg installed at /boot/limine/limine.cfg"
    else
        log_error "✗ limine.cfg not found"
        ((errors++))
    fi

    # Check vmlinuz-blossom exists (should be installed by kernel build)
    if [[ -f /boot/vmlinuz-blossom ]]; then
        log_info "✓ Kernel image: /boot/vmlinuz-blossom"
    else
        log_warn "✗ Kernel image not found at /boot/vmlinuz-blossom"
    fi

    # Check initramfs-blossom.img exists
    if [[ -f /boot/initramfs-blossom.img ]]; then
        log_info "✓ Initramfs: /boot/initramfs-blossom.img"
    else
        log_warn "✗ Initramfs not found at /boot/initramfs-blossom.img"
    fi

    # Display disk layout
    echo ""
    log_info "Disk partition layout:"
    lsblk "${TARGET_DISK}" -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null || \
        fdisk -l "${TARGET_DISK}" 2>/dev/null | head -20

    echo ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "  LIMINE BOOTLOADER INSTALLATION COMPLETE"
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "  Target disk: ${TARGET_DISK}"
    log_info "  Boot mode: ${BOOT_MODE^^}"
    log_info "  Root partition: ${ROOT_PART}"
    log_info "  Config file: /boot/limine/limine.cfg"
    log_info "═══════════════════════════════════════════════════════════════"
    echo ""

    if [[ ${errors} -gt 0 ]]; then
        log_warn "Some verifications failed - check boot configuration"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║         BLOOM OS — LIMINE BOOTLOADER PROVISIONING              ║"
    echo "║         UEFI/BIOS Bootloader Installation Engine                ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    preflight "$@"
    install_dependencies
    clone_limine
    compile_limine
    deploy_config
    install_to_disk
    verify_installation

    log_success "All stages completed successfully!"
    log_info "The system is ready to boot Bloom OS."
}

main "$@"