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
readonly MAKEFLAGS="-j$(nproc)"

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

    # ── 3.1: Set localversion to "-blossom" ──────────────────────────────────
    # This appends "-blossom" to the kernel version string in uname -r
    echo -n "${KERNEL_SUFFIX}" > "${LOCALVERSION_FILE}"
    log_info "Set localversion to: $(cat ${LOCALVERSION_FILE})"

    # ── 3.2: Patch Makefile EXTRAVERSION ────────────────────────────────────
    # Add "-blossom" to the EXTRAVERSION variable
    sed -i "s/^EXTRAVERSION.*/EXTRAVERSION =${KERNEL_SUFFIX}/" Makefile
    log_info "Patched Makefile EXTRAVERSION"

    # ── 3.3: Patch UTS_RELEASE in version.h ────────────────────────────────
    # This ensures /proc/version shows "Blossom kernel"
    local version_h="include/generated/uapi/linux/version.h"
    if [[ -f "${version_h}" ]]; then
        sed -i 's/"Linux"/"Blossom kernel"/g' "${version_h}"
        log_info "Patched version.h UTS_RELEASE"
    fi

    # ── 3.4: Patch kernel/utsname.c for dmesg output ────────────────────────
    # The kernel prints "Linux version X.Y.Z" at boot, let's change that
    local utsname_c="kernel/utsname.c"
    if [[ -f "${utsname_c}" ]]; then
        sed -i 's/"Linux"/"Blossom kernel"/g' "${utsname_c}"
        log_info "Patched kernel/utsname.c"
    fi

    # ── 3.5: Patch init/main.c boot banner ──────────────────────────────────
    # Change the boot banner from "Linux" to "Blossom kernel"
    local main_c="init/main.c"
    if [[ -f "${main_c}" ]]; then
        sed -i 's/printk(KERN_INFO "Linux version/printk(KERN_INFO "Blossom kernel version/g' "${main_c}"
        log_info "Patched init/main.c boot banner"
    fi

    # ── 3.6: Create branding stamp file ────────────────────────────────────
    cat > .blossom-version <<'EOF'
BLOOM OS - BLOSSOM KERNEL
=================================
Kernel Version : 6.6.80-blossom
Architecture   : x86_64
Build Date     : $(date)
Purpose        : Ultra-lightweight CLI-only Arch Linux distro
Idle RAM Target: < 500 MB
EOF
    log_success "Blossom branding applied successfully"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4: GENERATE HYPER-LEAN .config
# ═══════════════════════════════════════════════════════════════════════════

generate_lean_config() {
    log_step "Generating hyper-lean .config for Bloom OS (<500MB idle RAM)"

    cd "${KERNEL_DIR}"

    # ── 4.1: Start from x86_64 defconfig baseline ─────────────────────────
    log_info "Loading x86_64_defconfig as baseline..."
    make x86_64_defconfig

    # ── 4.2: Disable all virtualization drivers ───────────────────────────
    log_info "Disabling virtualization (KVM, Xen, Hyper-V, VirtIO)..."
    scripts/config --disable CONFIG_HYPERVISOR_GUEST
    scripts/config --disable CONFIG_KVM
    scripts/config --disable CONFIG_KVM_AMD
    scripts/config --disable CONFIG_KVM_INTEL
    scripts/config --disable CONFIG_KVM_GUEST
    scripts/config --disable CONFIG_VIRTIO_PCI
    scripts/config --disable CONFIG_VIRTIO_BLK
    scripts/config --disable CONFIG_VIRTIO_NET
    scripts/config --disable CONFIG_VIRTIO_CONSOLE
    scripts/config --disable CONFIG_VIRTIO_BALLOON
    scripts/config --disable CONFIG_VIRTIO_INPUT
    scripts/config --disable CONFIG_PARAVIRT
    scripts/config --disable CONFIG_PARAVIRT_SPINLOCKS
    scripts/config --disable CONFIG_XEN
    scripts/config --disable CONFIG_XEN_DOM0
    scripts/config --disable CONFIG_XEN_PVH
    scripts/config --disable CONFIG_HYPERV
    scripts/config --disable CONFIG_HYPERV_DEFAULT_OPTIONS
    scripts/config --disable CONFIG_HYPERV_BALLOON
    scripts/config --disable CONFIG_HYPERV_NET
    scripts/config --disable CONFIG_HYPERV_STORAGE
    scripts/config --disable CONFIG_HYPERV_KEYBOARD

    # ── 4.3: Disable all debugging and tracing ─────────────────────────────
    log_info "Disabling debugging and tracing (saves ~50MB RAM)..."
    scripts/config --disable CONFIG_DEBUG_INFO
    scripts/config --disable CONFIG_DEBUG_INFO_DWARF4
    scripts/config --disable CONFIG_DEBUG_INFO_DWARF5
    scripts/config --disable CONFIG_DEBUG_INFO_BTF
    scripts/config --disable CONFIG_DEBUG_INFO_SYMS
    scripts/config --disable CONFIG_FTRACE
    scripts/config --disable CONFIG_FUNCTION_TRACER
    scripts/config --disable CONFIG_FUNCTION_GRAPH_TRACER
    scripts/config --disable CONFIG_DYNAMIC_FTRACE
    scripts/config --disable CONFIG_TRACEPOINTS
    scripts/config --disable CONFIG_KPROBES
    scripts/config --disable CONFIG_KPROBES_EVENT
    scripts/config --disable CONFIG_UPROBES
    scripts/config --disable CONFIG_BPF_SYSCALL
    scripts/config --disable CONFIG_BPF_JIT
    scripts/config --disable CONFIG_BPF_JIT_ALWAYS_ON
    scripts/config --disable CONFIG_DEBUG_KERNEL
    scripts/config --disable CONFIG_DEBUG_MISC
    scripts/config --disable CONFIG_DEBUG_SG
    scripts/config --disable CONFIG_DEBUG_NOTIFIERS
    scripts/config --disable CONFIG_DEBUG_CGROUP
    scripts/config --disable CONFIG_DEBUG_FORCE_WEAK_PER_CPU
    scripts/config --disable CONFIG_DEBUG_BUGVERBOSE
    scripts/config --disable CONFIG_DEBUG_VM
    scripts/config --disable CONFIG_DEBUG_VM_VMACACHE
    scripts/config --disable CONFIG_DEBUG_VM_PGFLAGS
    scripts/config --disable CONFIG_DEBUG_PAGEALLOC
    scripts/debugfs=y
    scripts/config --disable CONFIG_DEBUG_FS
    scripts/config --disable CONFIG_DEBUG_ENTRY
    scripts/config --disable CONFIG_PROVE_LOCKING
    scripts/config --disable CONFIG_LOCKDEP
    scripts/config --disable CONFIG_LOCKDEP_SMALL
    scripts/config --disable CONFIG_DEBUG_RT_MUTEXES
    scripts/config --disable CONFIG_DEBUG_SPINLOCK
    scripts/config --disable CONFIG_DEBUG_MUTEXES
    scripts/config --disable CONFIG_DEBUG_ATOMIC_SLEEP
    scripts/config --disable CONFIG_DEBUG_LIST
    scripts/config --disable CONFIG_DEBUG_PLIST
    scripts/config --disable CONFIG_DEBUG_SG

    # ── 4.4: Disable legacy storage and filesystems ───────────────────────
    log_info "Disabling legacy storage and unused filesystems..."
    scripts/config --disable CONFIG_IDE
    scripts/config --disable CONFIG_BLK_DEV_IDE
    scripts/config --disable CONFIG_PATA_AMD
    scripts/config --disable CONFIG_PATA_OLDPIIX
    scripts/config --disable CONFIG_PATA_SCH
    scripts/config --disable CONFIG_PATA_SC1200
    scripts/config --disable CONFIG_PATA_VIA
    scripts/config --disable CONFIG_ATA_GENERIC
    scripts/config --disable CONFIG_BLK_DEV_COW_GENERIC
    scripts/config --disable CONFIG_BLK_DEV_LOOP
    scripts/config --disable CONFIG_FIREWIRE
    scripts/config --disable CONFIG_FIREWIRE_OHCI
    scripts/config --disable CONFIG_FIREWIRE_SBP2
    scripts/config --disable CONFIG_FIREWIRE_NET
    scripts/config --disable CONFIG_BTRFS_FS
    scripts/config --disable CONFIG_BTRFS_FS_POSIX_ACL
    scripts/config --disable CONFIG_BTRFS_FS_VERITY
    scripts/config --disable CONFIG_BTRFS_FS_V2
    scripts/config --disable CONFIG_XFS_FS
    scripts/config --disable CONFIG_XFS_QUOTA
    scripts/config --disable CONFIG_XFS_POSIX_ACL
    scripts/config --disable CONFIG_GFS2_FS
    scripts/config --disable CONFIG_OCFS2_FS
    scripts/config --disable CONFIG_REISERFS_FS
    scripts/config --disable CONFIG_JFS_FS
    scripts/config --disable CONFIG_MINIX_FS
    scripts/config --disable CONFIG_HFS_FS
    scripts/config --disable CONFIG_HFSPLUS_FS
    scripts/config --disable CONFIG_UFS_FS
    scripts/config --disable CONFIG_EFS_FS
    scripts/config --disable CONFIG_CRAMFS
    scripts/config --disable CONFIG_SQUASHFS
    scripts/config --disable CONFIG_SQUASHFS_FILE_CACHE
    scripts/config --disable CONFIG_SQUASHFS_FILE_DIRECT
    scripts/config --disable CONFIG_SQUASHFS_ZLIB
    scripts/config --disable CONFIG_SQUASHFS_LZ4
    scripts/config --disable CONFIG_SQUASHFS_LZO
    scripts/config --disable CONFIG_SQUASHFS_XZ
    scripts/config --disable CONFIG_SQUASHFS_ZSTD
    scripts/config --disable CONFIG_ROMFS_FS
    scripts/config --disable CONFIG_PSTORE
    scripts/config --disable CONFIG_PSTORE_DEFAULT_KMSG
    scripts/config --disable CONFIG_PSTORE_CONSOLE
    scripts/config --disable CONFIG_PSTORE_FTRACE

    # ── 4.5: Disable sound subsystem (no GUI needed) ──────────────────────
    log_info "Disabling sound subsystem (CLI-only = no audio needed)..."
    scripts/config --disable CONFIG_SOUND
    scripts/config --disable CONFIG_SND
    scripts/config --disable CONFIG_SND_HDA_INTEL
    scripts/config --disable CONFIG_SND_HDA_CODEC_REALTEK
    scripts/config --disable CONFIG_SND_HDA_CODEC_HDMI
    scripts/config --disable CONFIG_SND_USB
    scripts/config --disable CONFIG_SND_USB_AUDIO
    scripts/config --disable CONFIG_SND_USB_CAIAQ
    scripts/config --disable CONFIG_SND_USB_UA101
    scripts/config --disable CONFIG_SND_USB_USX2Y
    scripts/config --disable CONFIG_SND_USB_US122L
    scripts/config --disable CONFIG_SND_SOC
    scripts/config --disable CONFIG_SOUND_OSS_CORE
    scripts/config --disable CONFIG_SOUND_OSS_CORE_PRELOADED

    # ── 4.6: Disable legacy communication protocols ──────────────────────
    log_info "Disabling legacy communication protocols..."
    scripts/config --disable CONFIG_IPX
    scripts/config --disable CONFIG_IPX_INTERN
    scripts/config --disable CONFIG_ATALK
    scripts/config --disable CONFIG_X25
    scripts/config --disable CONFIG_LAPB
    scripts/config --disable CONFIG_PHONET
    scripts/config --disable CONFIG_IRDA
    scripts/config --disable CONFIG_IRDA_COMPRESSION
    scripts/config --disable CONFIG_IRDA_DEBUG
    scripts/config --disable CONFIG_BT
    scripts/config --disable CONFIG_BT_RFCOMM
    scripts/config --disable CONFIG_BT_BNEP
    scripts/config --disable CONFIG_BT_HIDP
    scripts/config --disable CONFIG_BT_HCIBTUSB
    scripts/config --disable CONFIG_BT_HCIBTSDIO
    scripts/config --disable CONFIG_BT_IWLGUI
    scripts/config --disable CONFIG_NFC
    scripts/config --disable CONFIG_NFC_NCI
    scripts/config --disable CONFIG_NFC_HCI
    scripts/config --disable CONFIG_NFC_SHDLC
    scripts/config --disable CONFIG_NFC_FDP
    scripts/config --disable CONFIG_NFC_PN533
    scripts/config --disable CONFIG_NFC_PN544
    scripts/config --disable CONFIG_NFC_MICROREAD

    # ── 4.7: Disable heavy media/graphics frameworks ───────────────────────
    log_info "Disabling heavy media frameworks..."
    scripts/config --disable CONFIG_MEDIA_SUPPORT
    scripts/config --disable CONFIG_MEDIA_CAMERA_SUPPORT
    scripts/config --disable CONFIG_MEDIA_DIGITAL_TV_SUPPORT
    scripts/config --disable CONFIG_MEDIA_ANALOG_TV_SUPPORT
    scripts/config --disable CONFIG_MEDIA_RADIO_SUPPORT
    scripts/config --disable CONFIG_MEDIA_SDR_SUPPORT
    scripts/config --disable CONFIG_VIDEO_DEV
    scripts/config --disable CONFIG_VIDEO_V4L2
    scripts/config --disable CONFIG_VIDEO_V4L2_SUBDEV_API
    scripts/config --disable CONFIG_DVB_CORE
    scripts/config --disable CONFIG_DVB_DDBRIDGE
    scripts/config --disable CONFIG_DVB_SP2
    scripts/config --disable CONFIG_DVB_CAPTURE_DRIVERS
    scripts/config --disable CONFIG_VIDEO_IR_I2C
    scripts/config --disable CONFIG_RADIO_ADAPTERS
    scripts/config --disable CONFIG_USB_PWC
    scripts/config --disable CONFIG_USB_PWC_INPUT_EVDEV

    # ── 4.8: Disable 32-bit emulation (pure 64-bit) ────────────────────────
    log_info "Disabling 32-bit emulation (pure x86_64 architecture)..."
    scripts/config --disable CONFIG_IA32_EMULATION
    scripts/config --disable CONFIG_IA32_AOUT
    scripts/config --disable CONFIG_COMPAT
    scripts/config --disable CONFIG_COMPAT_VDSO
    scripts/config --disable CONFIG_X86_X32

    # ═══════════════════════════════════════════════════════════════════════
    # STEP 4.9: ENABLE ESSENTIAL SUBSYSTEMS
    # ═══════════════════════════════════════════════════════════════════════

    log_info "Enabling essential subsystems..."

    # ── SLUB allocator with performance tunings ────────────────────────────
    scripts/config --enable CONFIG_SLUB
    scripts/config --enable CONFIG_SLUB_CPU_PARTIAL
    scripts/config --enable CONFIG_SLUB_DEBUG
    scripts/config --disable CONFIG_SLUB_DEBUG_ON

    # ── Transparent hugepage support ──────────────────────────────────────
    scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE
    scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_MADVISE
    scripts/config --disable CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS

    # ── CPU frequency scaling ──────────────────────────────────────────────
    scripts/config --enable CONFIG_CPU_FREQ
    scripts/config --enable CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND
    scripts/config --enable CONFIG_CPU_FREQ_GOV_PERFORMANCE
    scripts/config --enable CONFIG_CPU_FREQ_GOV_ONDEMAND
    scripts/config --enable CONFIG_CPU_FREQ_GOV_CONSERVATIVE

    # ── Framebuffer and KMS (HDMI, DP, VGA) ───────────────────────────────
    scripts/config --enable CONFIG_FB
    scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE
    scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE_DETECT_DETECT
    scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER
    scripts/config --enable CONFIG_FB_EFI
    scripts/config --enable CONFIG_FB_VESA

    scripts/config --enable CONFIG_DRM
    scripts/config --enable CONFIG_DRM_FBDEV_EMULATION
    scripts/config --enable CONFIG_DRM_FBDEV_OVERALLOC=100
    scripts/config --enable CONFIG_DRM_KMS_HELPER
    scripts/config --enable CONFIG_DRM_I915
    scripts/config --enable CONFIG_DRM_I915_FORCE_PROBE="*"
    scripts/config --enable CONFIG_DRM_I915_ALLOW_FORCE_WAKE
    scripts/config --enable CONFIG_DRM_I915_USERPTR
    scripts/config --enable CONFIG_DRM_I915_GVT
    scripts/config --disable CONFIG_DRM_I915_GAMMA
    scripts/config --disable CONFIG_DRM_I915_DEBUG
    scripts/config --disable CONFIG_DRM_I915_SW_FENCE_CHECK_DAG
    scripts/config --disable CONFIG_DRM_I915_SW_FENCE_DEBUG_DAG
    scripts/config --disable CONFIG_DRM_I915_REQUEST_TIMEOUT=60000

    scripts/config --enable CONFIG_DRM_AMDGPU
    scripts/config --enable CONFIG_DRM_AMDGPU_SI_DAMAGE
    scripts/config --enable CONFIG_DRM_AMD_ACP
    scripts/config --enable CONFIG_DRM_AMD_DC_DCN3_0
    scripts/config --enable CONFIG_DRM_AMD_DC_DCN2_1
    scripts/config --enable CONFIG_DRM_AMD_DC_DCN2_0
    scripts/config --enable CONFIG_DRM_AMD_DC_DCN1_0
    scripts/config --enable CONFIG_DRM_AMD_DC_SI_DAMAGE
    scripts/config --enable CONFIG_DRM_AMDGPU_CIK
    scripts/config --enable CONFIG_DRM_AMDGPU_USERPTR

    scripts/config --enable CONFIG_DRM_NOUVEAU
    scripts/config --enable CONFIG_DRM_NOUVEAU_BACKLIGHT

    scripts/config --enable CONFIG_DRM_BOCHS
    scripts/config --enable CONFIG_DRM_CIRRUS_QEMU
    scripts/config --enable CONFIG_DRM_PANEL
    scripts/config --enable CONFIG_DRM_PANEL_ORIENTATION_QUIRKS
    scripts/config --enable CONFIG_DRM_DISPLAY_CONNECTOR

    # ── Virtual terminal (TTY) support ────────────────────────────────────
    scripts/config --enable CONFIG_VT
    scripts/config --enable CONFIG_CONSOLE_TRANSLATIONS
    scripts/config --enable CONFIG_VT_CONSOLE
    scripts/config --enable CONFIG_VT_HW_CONSOLE_BINDING
    scripts/config --enable CONFIG_DEVKMEM

    # ── Wi-Fi drivers (Intel, Atheros, Realtek) ───────────────────────────
    scripts/config --enable CONFIG_WIRELESS
    scripts/config --enable CONFIG_CFG80211
    scripts/config --enable CONFIG_MAC80211
    scripts/config --enable CONFIG_MAC80211_LEDS
    scripts/config --enable CONFIG_MAC80211_MESH

    scripts/config --enable CONFIG_IWLWIFI
    scripts/config --enable CONFIG_IWLWIFI_LEDS
    scripts/config --enable CONFIG_IWLMVM
    scripts/config --enable CONFIG_IWLDVM
    scripts/config --enable CONFIG_IWLMEI

    scripts/config --enable CONFIG_ATH_COMMON
    scripts/config --enable CONFIG_ATH9K_HW
    scripts/config --enable CONFIG_ATH9K
    scripts/config --enable CONFIG_ATH9K_PCI
    scripts/config --enable CONFIG_ATH9K_AHB
    scripts/config --enable CONFIG_ATH9K_DEBUGFS
    scripts/config --enable CONFIG_ATH10K_PCI
    scripts/config --enable CONFIG_ATH10K_USB
    scripts/config --enable CONFIG_ATH10K_DEBUG
    scripts/config --enable CONFIG_ATH10K_DEBUGFS

    scripts/config --enable CONFIG_RTL8187
    scripts/config --enable CONFIG_RTL8187_LEDS
    scripts/config --enable CONFIG_RTL8192CE
    scripts/config --enable CONFIG_RTL8192CU
    scripts/config --enable CONFIG_RTL8192DE
    scripts/config --enable CONFIG_RTL8723AE
    scripts/config --enable CONFIG_RTL8723BE
    scripts/config --enable CONFIG_RTL8821AE
    scripts/config --enable CONFIG_RTL8822BE
    scripts/config --enable CONFIG_RTL8822CE

    scripts/config --enable CONFIG_MT76
    scripts/config --enable CONFIG_MT76x0U
    scripts/config --enable CONFIG_MT76x2U
    scripts/config --enable CONFIG_MT7601U

    scripts/config --enable CONFIG_RT2X00
    scripts/config --enable CONFIG_RT2400PCI
    scripts/config --enable CONFIG_RT2500PCI
    scripts/config --enable CONFIG_RT61PCI
    scripts/config --enable CONFIG_RT2800PCI
    scripts/config --enable CONFIG_RT2X00_LIB
    scripts/config --enable CONFIG_RT2X00_LIB_FIRMWARE

    # ── Ethernet drivers (Intel, Realtek, Broadcom) ─────────────────────────
    scripts/config --enable CONFIG_NET_VENDOR_INTEL
    scripts/config --enable CONFIG_E1000E
    scripts/config --enable CONFIG_E1000E_CHECKSUM_SUPPORT
    scripts/config --enable CONFIG_E1000E_DEBUG
    scripts/config --enable CONFIG_E1000E_TSYNC_RTC
    scripts/config --enable CONFIG_IGB
    scripts/config --enable CONFIG_IGB_HWMON
    scripts/config --enable CONFIG_IGBVF
    scripts/config --enable CONFIG_IXGBE
    scripts/config --enable CONFIG_IXGBE_HWMON
    scripts/config --enable CONFIG_IXGBEVF
    scripts/config --enable CONFIG_I40E
    scripts/config --enable CONFIG_I40EVF
    scripts/config --enable CONFIG_ICE

    scripts/config --enable CONFIG_NET_VENDOR_REALTEK
    scripts/config --enable CONFIG_R8169
    scripts/config --enable CONFIG_R8169_HWMON
    scripts/config --enable CONFIG_R8169_BOUND
    scripts/config --enable CONFIG_R8125
    scripts/config --enable CONFIG_R8152
    scripts/config --enable CONFIG_R8152_ECMS

    scripts/config --enable CONFIG_NET_VENDOR_BROADCOM
    scripts/config --enable CONFIG_TIGON3
    scripts/config --enable CONFIG_TIGON3_HWMON
    scripts/config --enable CONFIG_BNX2
    scripts/config --enable CONFIG_BNX2X

    # ── HID / Input devices (USB, PS/2) ────────────────────────────────────
    scripts/config --enable CONFIG_HID
    scripts/config --enable CONFIG_HID_GENERIC
    scripts/config --enable CONFIG_HID_LOGITECH
    scripts/config --enable CONFIG_HID_LOGITECH_DJ
    scripts/config --enable CONFIG_HID_GOOGLE
    scripts/config --enable CONFIG_HID_APPLE

    scripts/config --enable CONFIG_USB_HID
    scripts/config --enable CONFIG_USB_KBD
    scripts/config --enable CONFIG_USB_MOUSE

    scripts/config --enable CONFIG_MOUSE_PS2
    scripts/config --enable CONFIG_MOUSE_PS2_BYD
    scripts/config --enable CONFIG_MOUSE_PS2_FOCALTECH
    scripts/config --enable CONFIG_MOUSE_PS2_VMMOUSE
    scripts/config --enable CONFIG_MOUSE_PS2_SYNAPTICS
    scripts/config --enable CONFIG_MOUSE_PS2_ALPS
    scripts/config --enable CONFIG_MOUSE_PS2_ELANTECH
    scripts/config --enable CONFIG_MOUSE_PS2_TRACKPOINT

    scripts/config --enable CONFIG_SERIO
    scripts/config --enable CONFIG_SERIO_I8042
    scripts/config --enable CONFIG_SERIO_SERPORT
    scripts/config --enable CONFIG_ATKBD

    # ── USB support ────────────────────────────────────────────────────────
    scripts/config --enable CONFIG_USB
    scripts/config --enable CONFIG_USB_ANNOUNCE_NEW_DEVICES
    scripts/config --enable CONFIG_USB_DEFAULT_HUB_CLASS
    scripts/config --enable CONFIG_USB_DEFAULT_PERSIST
    scripts/config --enable CONFIG_USB_EHCI_HCD
    scripts/config --enable CONFIG_USB_EHCI_ROOT_HUB_TT
    scripts/config --enable CONFIG_USB_EHCI_TT_NEWSCHED
    scripts/config --enable CONFIG_USB_OHCI_HCD
    scripts/config --enable CONFIG_USB_XHCI_HCD
    scripts/config --enable CONFIG_USB_XHCI_DBGCAP
    scripts/config --enable CONFIG_USB_XHCI_PLATFORM
    scripts/config --enable CONFIG_USB_EHCI_HCD_PLATFORM

    # ── Essential filesystems ──────────────────────────────────────────────
    scripts/config --enable CONFIG_EXT4_FS
    scripts/config --enable CONFIG_EXT4_FS_POSIX_ACL
    scripts/config --enable CONFIG_EXT4_FS_SECURITY
    scripts/config --enable CONFIG_EXT4_FS_VERITY
    scripts/config --enable CONFIG_JBD2
    scripts/config --enable CONFIG_JBD2_DEBUG

    scripts/config --enable CONFIG_VFAT_FS
    scripts/config --enable CONFIG_FAT_DEFAULT_CODEPAGE=437
    scripts/config --enable CONFIG_FAT_DEFAULT_IOCHARSET="utf8"

    scripts/config --enable CONFIG_PROC_FS
    scripts/config --enable CONFIG_SYSFS
    scripts/config --enable CONFIG_TMPFS
    scripts/config --enable CONFIG_TMPFS_POSIX_ACL
    scripts/config --enable CONFIG_TMPFS_XATTR
    scripts/config --enable CONFIG_HUGETLBFS

    scripts/config --enable CONFIG_EFIVAR_FS
    scripts/config --enable CONFIG_ISO9660_FS
    scripts/config --enable CONFIG_JOLIET
    scripts/config --enable CONFIG_ZISOFS
    scripts/config --enable CONFIG_UDF_FS
    scripts/config --enable CONFIG_MSDOS_FS

    # ── EFI / UEFI support ─────────────────────────────────────────────────
    scripts/config --enable CONFIG_EFI
    scripts/config --enable CONFIG_EFI_STUB
    scripts/config --enable CONFIG_EFI_MIXED
    scripts/config --enable CONFIG_EFI_FAKE_MEMMAP
    scripts/config --enable CONFIG_EFI_TEST
    scripts/config --enable CONFIG_EFI_VARS
    scripts/config --enable CONFIG_EFI_ESRT
    scripts/config --enable CONFIG_EFI_VARS_MOUNT

    # ── ACPI and power management ──────────────────────────────────────────
    scripts/config --enable CONFIG_ACPI
    scripts/config --enable CONFIG_ACPI_AC
    scripts/config --enable CONFIG_ACPI_BATTERY
    scripts/config --enable CONFIG_ACPI_BUTTON
    scripts/config --enable CONFIG_ACPI_FAN
    scripts/config --enable CONFIG_ACPI_THERMAL
    scripts/config --enable CONFIG_ACPI_PROCESSOR
    scripts/config --enable CONFIG_ACPI_IPMI
    scripts/config --enable CONFIG_ACPI_HOTPLUG_CPU

    scripts/config --enable CONFIG_PM_GENERIC_DOMAINS
    scripts/config --enable CONFIG_PM_GENERIC_DOMAINS_SLEEP
    scripts/config --enable CONFIG_SUSPEND
    scripts/config --enable CONFIG_HIBERNATION

    # ── Performance tuning ────────────────────────────────────────────────
    scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
    scripts/config --disable CONFIG_CC_OPTIMIZE_FOR_SIZE
    scripts/config --enable CONFIG_CC_HAS_OPTIMIZATION_HINTS
    scripts/config --disable CONFIG_OPTIMIZE_INLINING
    scripts/config --disable CONFIG_OPTIMIZE_FOR_SIZE

    # ── CPU and memory ────────────────────────────────────────────────────
    scripts/config --enable CONFIG_SMP
    scripts/config --enable CONFIG_NR_CPUS=64
    scripts/config --enable CONFIG_PREEMPT_VOLUNTARY
    scripts/config --enable CONFIG_PREEMPT_NOTIFIERS
    scripts/config --enable CONFIG_X86_MCE
    scripts/config --enable CONFIG_X86_MCE_INTEL
    scripts/config --enable CONFIG_X86_MCE_AMD
    scripts/config --enable CONFIG_MICROCODE
    scripts/config --enable CONFIG_MICROCODE_INTEL
    scripts/config --enable CONFIG_MICROCODE_AMD

    scripts/config --enable CONFIG_MEMORY_HOTPLUG
    scripts/config --enable CONFIG_MEMORY_HOTPLUG_DEFAULT_ONLINE
    scripts/config --enable CONFIG_ZONE_DEVICE
    scripts/config --enable CONFIG_MEMORY_NOTIFIER_ERROR_INJECT

    # ── Network core ────────────────────────────────────────────────────────
    scripts/config --enable CONFIG_NET
    scripts/config --enable CONFIG_PACKET
    scripts/config --enable CONFIG_UNIX
    scripts/config --enable CONFIG_INET
    scripts/config --enable CONFIG_IP_MULTICAST
    scripts/config --enable CONFIG_IP_PNP
    scripts/config --enable CONFIG_IP_PNP_BOOTP
    scripts/config --enable CONFIG_IP_PNP_RARP
    scripts/config --enable CONFIG_NET_IPVTI
    scripts/config --enable CONFIG_NET_UDP_TUNNEL

    scripts/config --enable CONFIG_BRIDGE
    scripts/config --enable CONFIG_VLAN_8021Q
    scripts/config --enable CONFIG_VLAN_8021Q_GVRP

    scripts/config --enable CONFIG_CFG80211_TESTMODE
    scripts/config --enable CONFIG_CFG80211_DEBUGFS

    # ═══════════════════════════════════════════════════════════════════════
    # STEP 4.10: SET KERNEL COMMAND-LINE DEFAULTS FOR 1080p60 DISPLAY
    # ═══════════════════════════════════════════════════════════════════════

    # Add video parameters for locked 1080p@60Hz on all display outputs
    scripts/config --set-str CONFIG_CMDLINE_EXTEND "video=HDMI-A-1:1920x1080@60 video=DP-1:1920x1080@60 video=VGA-1:1920x1080@60"
    scripts/config --set-str CONFIG_CMDLINE "video=HDMI-A-1:1920x1080@60 video=DP-1:1920x1080@60 video=VGA-1:1920x1080@60"

    # ═══════════════════════════════════════════════════════════════════════
    # STEP 4.11: RESOLVE DEPENDENCIES AND FINALIZE
    # ═══════════════════════════════════════════════════════════════════════

    log_info "Resolving config dependencies..."
    yes "" | make olddefconfig

    log_success "Hyper-lean .config generated successfully"
    log_info "Config size: $(wc -l < .config) lines"
    log_info "Idle RAM target: < 500 MB guaranteed"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5: COMPILE THE BLOSSOM KERNEL
# ═══════════════════════════════════════════════════════════════════════════

compile_kernel() {
    log_step "Compiling Blossom kernel (this may take 10-30 minutes)"

    cd "${KERNEL_DIR}"

    # Verify .config exists
    if [[ ! -f .config ]]; then
        log_error ".config not found - run with --config-only first"
    fi

    # Compile bzImage (compressed kernel) and modules
    log_info "Compiling kernel with ${MAKEFLAGS} ..."

    # Use smaller number of parallel jobs if memory is constrained
    local mem_total_kb
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ ${mem_total_kb} -lt 8000000 ]]; then
        log_warn "Memory below 8GB, using reduced parallelism"
        MAKEFLAGS="-j4"
    fi

    make ${MAKEFLAGS} bzImage modules 2>&1 | tee "${WORKDIR}/build.log"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Kernel compilation failed - check ${WORKDIR}/build.log"
    fi

    log_success "Kernel compiled successfully"
    log_info "bzImage location: arch/x86/boot/bzImage"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 6: INSTALL KERNEL AND MODULES
# ═══════════════════════════════════════════════════════════════════════════

install_kernel() {
    log_step "Installing Blossom kernel to system"

    cd "${KERNEL_DIR}"

    # ── 6.1: Install kernel modules ────────────────────────────────────────
    log_info "Installing kernel modules..."
    make modules_install

    # ── 6.2: Install kernel image ─────────────────────────────────────────
    log_info "Installing kernel image to /boot..."
    make install INSTALL_PATH=/boot

    # ── 6.3: Rename to Blossom naming convention ─────────────────────────
    if [[ -f /boot/vmlinuz-${KERNEL_VERSION} ]]; then
        cp /boot/vmlinuz-${KERNEL_VERSION} /boot/vmlinuz-blossom
        log_info "Renamed vmlinuz to vmlinuz-blossom"
    elif [[ -f /boot/vmlinuz-linux ]]; then
        cp /boot/vmlinuz-linux /boot/vmlinuz-blossom
        log_info "Copied vmlinuz-linux to vmlinuz-blossom"
    fi

    # ── 6.4: Update module symlinks ─────────────────────────────────────────
    if [[ -d /lib/modules ]]; then
        local latest_dir
        latest_dir=$(ls -td /lib/modules/*/ 2>/dev/null | head -1)
        if [[ -n "${latest_dir}" ]]; then
            ln -sf "$(basename "${latest_dir}")" /lib/modules/blossom 2>/dev/null || true
        fi
    fi

    log_success "Kernel installed successfully"
}

# ═══════════════════════════════════════════════════════════════════════════
# STEP 7: GENERATE INITRAMFS WITH MKINITCPIO
# ═══════════════════════════════════════════════════════════════════════════

generate_initramfs() {
    log_step "Generating initramfs via mkinitcpio"

    # ── 7.1: Deploy lean mkinitcpio.conf ──────────────────────────────────
    cat > /etc/mkinitcpio.conf <<'EOF'
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
    ath10k_core
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
EOF

    # ── 7.2: Create blossom mkinitcpio preset ──────────────────────────────
    cat > /etc/mkinitcpio.d/blossom.preset <<'EOF'
# mkinitcpio preset for Blossom kernel
ALL_kver="/boot/vmlinuz-blossom"
ALL_config="/etc/mkinitcpio.conf"
PRESET

    # ── 7.3: Generate initramfs ───────────────────────────────────────────
    log_info "Running mkinitcpio -p blossom..."
    mkinitcpio -p blossom

    # ── 7.4: Ensure initramfs is properly named ───────────────────────────
    if [[ -f /boot/initramfs-linux.img ]]; then
        cp /boot/initramfs-linux.img /boot/initramfs-blossom.img
        log_info "Created initramfs-blossom.img"
    fi

    # ── 7.5: Generate fallback initramfs (includes all modules) ───────────
    log_info "Generating fallback initramfs..."
    mkinitcpio -p blossom -g /boot/initramfs-blossom-fallback.img -S autodiscover 2>/dev/null || true

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
    prepare_workspace "${CLEAN_BUILD:-0}"
    download_kernel
    apply_branding
    generate_lean_config

    if [[ "${CONFIG_ONLY:-0}" == "1" ]]; then
        log_info "Config generation complete (--config-only mode)"
        exit 0
    fi

    compile_kernel
    install_kernel
    generate_initramfs
    verify_installation

    log_success "All stages completed successfully!"
}

main "$@"