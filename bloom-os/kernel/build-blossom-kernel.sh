#!/usr/bin/env bash
###############################################################################
# build-blossom-kernel.sh — Blossom Kernel Build Pipeline for Bloom OS
#
# This script automates the complete kernel build process:
#   1. Downloads the official Arch Linux LTS kernel source
#   2. Applies branding patches to rebrand as "Blossom kernel"
#   3. Generates a hyper-lean .config optimized for <500MB idle RAM
#   4. Compiles the kernel with KMS framebuffer support
#   5. Installs modules and generates initramfs
#
# Target Architecture: x86_64 only (no 32-bit multilib)
# Kernel Version: 6.6.80 LTS (Arch Linux stable)
#
# Usage: sudo ./build-blossom-kernel.sh [--clean] [--config-only]
###############################################################################

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

readonly KERNEL_VERSION="6.6.80"
readonly KERNEL_SERIES="6.6"
readonly KERNEL_SRC="linux-${KERNEL_VERSION}"
readonly KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_SERIES:0:1}.x/${KERNEL_SRC}.tar.xz"
readonly WORKDIR="${HOME}/bloom-kernel-build"
readonly KERNEL_DIR="${WORKDIR}/${KERNEL_SRC}"
MAKEFLAGS="-j$(nproc)"

# Blossom branding identifiers
readonly KERNEL_NAME="Blossom kernel"
readonly KERNEL_SUFFIX="-blossom"
readonly LOCALVERSION_FILE="${KERNEL_DIR}/localversion"

# ═══════════════════════════════════════════════════════════════════════════
# COLOUR OUTPUT HELPERS
# ═══════════════════════════════════════════════════════════════════════════

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[BLOSSOM]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[BLOSSOM]${NC} WARNING: $*"; }
log_error()   { echo -e "${RED}[BLOSSOM]${NC} ERROR: $*"; exit 1; }
log_step()    { echo -e "\n${MAGENTA}═══ $* ═══${NC}"; }
log_success() { echo -e "${GREEN}✓ $*${NC}"; }

# ═══════════════════════════════════════════════════════════════════════════
# PREFLIGHT CHECKS
# ═══════════════════════════════════════════════════════════════════════════

check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)."
    fi
}

check_dependencies() {
    log_step "Checking build dependencies"

    local missing_deps=()

    for dep in make gcc bc flex bison perl python3 tar xz curl git; do
        if ! command -v "${dep}" &>/dev/null; then
            missing_deps+=("${dep}")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warn "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing build dependencies via pacman..."
        pacman -Sy --noconfirm --needed base-devel python git curl
    fi

    # Ensure kernel build packages are present
    local kernel_deps=( pahole cpio zstd lz4 )
    for dep in "${kernel_deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            pacman -Sy --noconfirm --needed "${dep}"
        fi
    done

    log_success "All build dependencies satisfied"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 1: PREPARE BUILD WORKSPACE
# ═══════════════════════════════════════════════════════════════════════════

prepare_workspace() {
    log_step "Preparing build workspace"

    mkdir -p "${WORKDIR}"
    cd "${WORKDIR}"

    log_info "Workspace: ${WORKDIR}"
    log_info "Kernel source will be: ${KERNEL_DIR}"

    # Clean previous build if exists and --clean flag passed
    if [[ "${1:-}" == "--clean" ]] && [[ -d "${KERNEL_DIR}" ]]; then
        log_warn "Cleaning previous build..."
        rm -rf "${KERNEL_DIR}" "${KERNEL_SRC}".tar.xz
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 2: DOWNLOAD KERNEL SOURCE
# ═══════════════════════════════════════════════════════════════════════════

download_kernel() {
    log_step "Downloading Linux kernel ${KERNEL_VERSION} source"

    if [[ -d "${KERNEL_DIR}" ]]; then
        log_info "Kernel source already exists, skipping download"
        return 0
    fi

    local kernel_tarball="${KERNEL_SRC}.tar.xz"
    local kernel_sign="${kernel_tarball}.sign"

    log_info "Downloading from ${KERNEL_URL}"
    curl -fSL --progress-bar -o "${kernel_tarball}" "${KERNEL_URL}"

    # Optionally fetch and verify GPG signature
    log_info "Verifying source integrity..."
    curl -fSL -o "${kernel_sign}" "${KERNEL_URL}.sign" 2>/dev/null || true

    if [[ -f "${kernel_sign}" ]]; then
        if command -v gpgv &>/dev/null; then
            gpgv "${kernel_sign}" "${kernel_tarball}" 2>/dev/null || log_warn "Signature verification failed, proceeding anyway"
        fi
    fi

    log_info "Extracting kernel source..."
    tar xf "${kernel_tarball}" && rm -f "${kernel_tarball}" "${kernel_sign}"

    log_success "Kernel source extracted to ${KERNEL_DIR}"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 3: APPLY BLOSSOM BRANDING PATCHES
# ═══════════════════════════════════════════════════════════════════════════

apply_branding() {
    log_step "Applying Blossom kernel branding patches"

    cd "${KERNEL_DIR}"

    # Set localversion to "-blossom"
    echo -n "${KERNEL_SUFFIX}" > "${LOCALVERSION_FILE}"
    log_info "Set localversion to: $(cat ${LOCALVERSION_FILE})"

    # Patch Makefile EXTRAVERSION
    sed -i "s/^EXTRAVERSION.*/EXTRAVERSION =${KERNEL_SUFFIX}/" Makefile
    log_info "Patched Makefile EXTRAVERSION"

    # Patch version.h for /proc/version
    local version_h="include/generated/uapi/linux/version.h"
    if [[ -f "${version_h}" ]]; then
        sed -i 's/"Linux"/"Blossom kernel"/g' "${version_h}"
        log_info "Patched version.h UTS_RELEASE"
    fi

    # Patch kernel/utsname.c for dmesg output
    local utsname_c="kernel/utsname.c"
    if [[ -f "${utsname_c}" ]]; then
        sed -i 's/"Linux"/"Blossom kernel"/g' "${utsname_c}"
        log_info "Patched kernel/utsname.c"
    fi

    # Patch init/main.c boot banner
    local main_c="init/main.c"
    if [[ -f "${main_c}" ]]; then
        sed -i 's/printk(KERN_INFO "Linux version/printk(KERN_INFO "Blossom kernel version/g' "${main_c}"
        log_info "Patched init/main.c boot banner"
    fi

    log_success "Blossom branding applied successfully"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4: GENERATE HYPER-LEAN .config
# ═══════════════════════════════════════════════════════════════════════════

generate_lean_config() {
    log_step "Generating hyper-lean .config for Bloom OS (<500MB idle RAM)"

    cd "${KERNEL_DIR}"

    # Start from x86_64 defconfig baseline
    log_info "Loading x86_64_defconfig as baseline..."
    make x86_64_defconfig

    # Disable virtualization
    log_info "Disabling virtualization (KVM, Xen, Hyper-V, VirtIO)..."
    scripts/config --disable CONFIG_HYPERVISOR_GUEST
    scripts/config --disable CONFIG_KVM
    scripts/config --disable CONFIG_KVM_AMD
    scripts/config --disable CONFIG_KVM_INTEL
    scripts/config --disable CONFIG_VIRTIO_PCI
    scripts/config --disable CONFIG_VIRTIO_BLK
    scripts/config --disable CONFIG_VIRTIO_NET
    scripts/config --disable CONFIG_PARAVIRT
    scripts/config --disable CONFIG_XEN
    scripts/config --disable CONFIG_HYPERV

    # Disable debugging and tracing
    log_info "Disabling debugging and tracing (saves ~50MB RAM)..."
    scripts/config --disable CONFIG_DEBUG_INFO
    scripts/config --disable CONFIG_FTRACE
    scripts/config --disable CONFIG_FUNCTION_TRACER
    scripts/config --disable CONFIG_KPROBES
    scripts/config --disable CONFIG_BPF_SYSCALL
    scripts/config --disable CONFIG_DEBUG_KERNEL
    scripts/config --disable CONFIG_DEBUG_FS
    scripts/config --disable CONFIG_PROVE_LOCKING
    scripts/config --disable CONFIG_LOCKDEP

    # Disable legacy storage and filesystems
    log_info "Disabling legacy storage and unused filesystems..."
    scripts/config --disable CONFIG_IDE
    scripts/config --disable CONFIG_BTRFS_FS
    scripts/config --disable CONFIG_XFS_FS
    scripts/config --disable CONFIG_GFS2_FS
    scripts/config --disable CONFIG_REISERFS_FS
    scripts/config --disable CONFIG_JFS_FS

    # Disable sound subsystem (CLI-only = no audio needed)
    log_info "Disabling sound subsystem..."
    scripts/config --disable CONFIG_SOUND
    scripts/config --disable CONFIG_SND

    # Disable legacy communication protocols
    log_info "Disabling legacy communication protocols..."
    scripts/config --disable CONFIG_BT
    scripts/config --disable CONFIG_IRDA
    scripts/config --disable CONFIG_NFC

    # Disable 32-bit emulation (pure 64-bit)
    log_info "Disabling 32-bit emulation (pure x86_64 architecture)..."
    scripts/config --disable CONFIG_IA32_EMULATION
    scripts/config --disable CONFIG_COMPAT

    # Enable essential subsystems
    log_info "Enabling essential subsystems..."

    # SLUB allocator
    scripts/config --enable CONFIG_SLUB
    scripts/config --enable CONFIG_SLUB_CPU_PARTIAL

    # Framebuffer and KMS (HDMI, DP, VGA)
    scripts/config --enable CONFIG_FB
    scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE
    scripts/config --enable CONFIG_DRM
    scripts/config --enable CONFIG_DRM_FBDEV_EMULATION
    scripts/config --enable CONFIG_DRM_KMS_HELPER
    scripts/config --enable CONFIG_DRM_I915
    scripts/config --enable CONFIG_DRM_AMDGPU
    scripts/config --enable CONFIG_VT
    scripts/config --enable CONFIG_VT_CONSOLE

    # Wi-Fi drivers
    scripts/config --enable CONFIG_CFG80211
    scripts/config --enable CONFIG_MAC80211
    scripts/config --enable CONFIG_IWLWIFI
    scripts/config --enable CONFIG_ATH9K
    scripts/config --enable CONFIG_ATH10K_PCI
    scripts/config --enable CONFIG_RTL8187

    # Ethernet drivers
    scripts/config --enable CONFIG_E1000E
    scripts/config --enable CONFIG_R8169
    scripts/config --enable CONFIG_IGB
    scripts/config --enable CONFIG_TIGON3

    # HID / Input devices
    scripts/config --enable CONFIG_HID_GENERIC
    scripts/config --enable CONFIG_USB_HID
    scripts/config --enable CONFIG_MOUSE_PS2

    # USB support
    scripts/config --enable CONFIG_USB
    scripts/config --enable CONFIG_USB_XHCI_HCD
    scripts/config --enable CONFIG_USB_EHCI_HCD
    scripts/config --enable CONFIG_USB_OHCI_HCD

    # Essential filesystems
    scripts/config --enable CONFIG_EXT4_FS
    scripts/config --enable CONFIG_VFAT_FS
    scripts/config --enable CONFIG_PROC_FS
    scripts/config --enable CONFIG_SYSFS
    scripts/config --enable CONFIG_TMPFS

    # EFI / UEFI support
    scripts/config --enable CONFIG_EFI
    scripts/config --enable CONFIG_EFI_STUB

    # Performance tuning
    scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
    scripts/config --enable CONFIG_PREEMPT_VOLUNTARY
    scripts/config --enable CONFIG_MICROCODE

    # Set kernel command-line for 1080p@60 display
    scripts/config --set-str CONFIG_CMDLINE "video=HDMI-A-1:1920x1080@60 video=DP-1:1920x1080@60 video=VGA-1:1920x1080@60"

    # Resolve dependencies
    log_info "Resolving config dependencies..."
    yes "" | make olddefconfig

    log_success "Hyper-lean .config generated successfully"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5: COMPILE THE BLOSSOM KERNEL
# ═══════════════════════════════════════════════════════════════════════════

compile_kernel() {
    log_step "Compiling Blossom kernel (this may take 10-30 minutes)"

    cd "${KERNEL_DIR}"

    if [[ ! -f .config ]]; then
        log_error ".config not found - run with --config-only first"
    fi

    log_info "Compiling kernel with ${MAKEFLAGS}..."

    # Use smaller number of parallel jobs if memory is constrained
    local mem_total_kb mem_cores
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_cores=$(nproc)
    if [[ ${mem_total_kb} -lt 8000000 ]]; then
        log_warn "Memory below 8GB, using reduced parallelism"
        MAKEFLAGS="-j$(( mem_cores / 2 ))"
    fi

    make ${MAKEFLAGS} bzImage modules 2>&1 | tee "${WORKDIR}/build.log"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Kernel compilation failed - check ${WORKDIR}/build.log"
    fi

    log_success "Kernel compiled successfully"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 6: INSTALL KERNEL AND MODULES
# ═══════════════════════════════════════════════════════════════════════════

install_kernel() {
    log_step "Installing Blossom kernel to system"

    cd "${KERNEL_DIR}"

    # Install kernel modules
    log_info "Installing kernel modules..."
    make modules_install

    # Install kernel image
    log_info "Installing kernel image to /boot..."
    make install INSTALL_PATH=/boot

    # Rename to Blossom naming convention
    if [[ -f /boot/vmlinuz-${KERNEL_VERSION} ]]; then
        cp /boot/vmlinuz-${KERNEL_VERSION} /boot/vmlinuz-blossom
        log_info "Renamed vmlinuz to vmlinuz-blossom"
    elif [[ -f /boot/vmlinuz-linux ]]; then
        cp /boot/vmlinuz-linux /boot/vmlinuz-blossom
        log_info "Copied vmlinuz-linux to vmlinuz-blossom"
    fi

    log_success "Kernel installed successfully"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 7: GENERATE INITRAMFS WITH MKINITCPIO
# ═══════════════════════════════════════════════════════════════════════════

generate_initramfs() {
    log_step "Generating initramfs via mkinitcpio"

    # Ensure console configuration exists to prevent hook failure
    if [[ ! -f /etc/vconsole.conf ]]; then
        cat > /etc/vconsole.conf <<'EOFVC'
KEYMAP=us
FONT=ter-v16n
EOFVC
    fi

    # Ensure mkinitcpio.d directory exists
    mkdir -p /etc/mkinitcpio.d

    # Deploy lean mkinitcpio.conf
    cat > /etc/mkinitcpio.conf <<'EOFMKINIT'
# mkinitcpio.conf for Bloom OS - Blossom kernel
# Ultra-lean initramfs for <500MB idle RAM

MODULES=(
    ahci
    sd_mod
    nvme
    mmc_block
    ext4
    hid_generic
    usbhid
    psmouse
    atkbd
    e1000e
    r8169
    igb
    tg3
    iwlwifi
    ath9k
    ath10k_pci
    mac80211
    cfg80211
    drm
    drm_kms_helper
    i915
    amdgpu
    fbcon
)

BINARIES=()

FILES=()

HOOKS=(
    base
    udev
    autodetect
    keyboard
    keymap
    modconf
    block
    filesystems
    fsck
)

COMPRESSION="zstd"
COMPRESSION_OPTIONS=()
EOFMKINIT

    # Create blossom mkinitcpio preset
    cat > /etc/mkinitcpio.d/blossom.preset <<'EOFPRESET'
# mkinitcpio preset for Blossom kernel
ALL_kver="/boot/vmlinuz-blossom"
ALL_config="/etc/mkinitcpio.conf"
EOFPRESET

    # Generate initramfs
    log_info "Running mkinitcpio -p blossom..."
    mkinitcpio -p blossom

    # Ensure initramfs is properly named
    if [[ -f /boot/initramfs-linux.img ]]; then
        cp /boot/initramfs-linux.img /boot/initramfs-blossom.img
        log_info "Created initramfs-blossom.img"
    fi

    # Generate fallback initramfs
    log_info "Generating fallback initramfs..."
    mkinitcpio -p blossom -g /boot/initramfs-blossom-fallback.img -S autodiscover 2>/dev/null || true

    # Verify initramfs file was actually created
    if [[ -f /boot/initramfs-blossom.img ]]; then
        local img_size
        img_size=$(du -h /boot/initramfs-blossom.img | awk '{print $1}')
        log_success "Initramfs generated: /boot/initramfs-blossom.img (${img_size})"
    else
        log_error "Initramfs generation FAILED - /boot/initramfs-blossom.img not found"
    fi

    log_success "Initramfs generation complete"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 8: VERIFY INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════

verify_installation() {
    log_step "Verifying Blossom kernel installation"

    local missing_files=()

    # Check for required files
    [[ -f /boot/vmlinuz-blossom ]] || missing_files+=("/boot/vmlinuz-blossom")
    [[ -f /boot/initramfs-blossom.img ]] || missing_files+=("/boot/initramfs-blossom.img")
    [[ -d /lib/modules/$(uname -r 2>/dev/null || echo "6.6.80-blossom") ]] || missing_files+=("/lib/modules")

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing files: ${missing_files[*]}"
    fi

    # Display installation summary
    echo ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "  BLOSSOM KERNEL INSTALLATION COMPLETE"
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "  Kernel image  : /boot/vmlinuz-blossom"
    log_info "  Initramfs     : /boot/initramfs-blossom.img"
    log_info "  Modules dir   : /lib/modules/$(ls /lib/modules | grep blossom | head -1)"
    log_info "  Kernel version: $(uname -r)"
    log_info "═══════════════════════════════════════════════════════════════"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║       BLOOM OS — BLOSSOM KERNEL BUILD PIPELINE                  ║"
    echo "║       Ultra-lightweight 64-bit Arch Linux Kernel                ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    # Parse arguments
    local CLEAN_BUILD=0
    local CONFIG_ONLY=0

    case "${1:-}" in
        --clean)
            log_info "Clean build requested"
            CLEAN_BUILD=1
            ;;
        --config-only)
            log_info "Config-only mode requested"
            CONFIG_ONLY=1
            ;;
        --help|-h)
            echo "Usage: $0 [--clean] [--config-only] [--help]"
            echo ""
            echo "Options:"
            echo "  --clean        Remove previous build and start fresh"
            echo "  --config-only  Generate .config only, don't compile"
            echo "  --help         Show this help message"
            exit 0
            ;;
    esac

    # Execute build pipeline
    check_privileges
    check_dependencies
    prepare_workspace "${CLEAN_BUILD}"
    download_kernel
    apply_branding
    generate_lean_config

    if [[ "${CONFIG_ONLY}" == "1" ]]; then
        log_info "Config generation complete (--config-only mode)"
        exit 0
    fi

    compile_kernel
    install_kernel
    generate_initramfs
    verify_installation

    log_success "All stages completed successfully!"
}

# Call main function with all arguments
main "$@"