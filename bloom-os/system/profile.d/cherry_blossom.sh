#!/usr/bin/env bash
###############################################################################
# cherry_blossom.sh — Cherry Blossom Terminal Banner for Bloom OS
#
# This script displays a beautiful Japanese Cherry Blossom (Sakura) ASCII art
# along with system statistics every time a terminal session is initialized.
#
# Installation: Copy to /etc/profile.d/cherry_blossom.sh
#               Add to /etc/skel/.bashrc for new users
#
# Features:
#   - Multi-line ASCII art Sakura tree
#   - System statistics dashboard
#   - RAM usage display (<500MB target indicator)
#   - Kernel version and uptime display
#   - Auto-clears screen on each login
###############################################################################

# ═══════════════════════════════════════════════════════════════════════════
# BANNER COLOUR CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

# Sakura theme colours
readonly SAKURA_PINK='#ffb7c5'
readonly SAKURA_DARK='#1a0a0e'
readonly SAKURA_HIGHLIGHT='#ff69b4'
readonly BORDER_COLOR='#c71585'

# ANSI colour codes
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'
readonly C_PINK='\033[0;35m'
readonly C_LIGHT_PINK='\033[1;35m'
readonly C_CYAN='\033[0;36m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_RED='\033[0;31m'

# ═══════════════════════════════════════════════════════════════════════════
# CHERRY BLOSSOM ASCII ART — The Sakura Tree
# ═══════════════════════════════════════════════════════════════════════════

display_sakura_art() {
    cat <<'SAKURA_ART'


                                    ⬤
                                   ⬤⬤
                                  ⬤⬤⬤
                                 ⬤⬤⬤⬤
                                ⬤⬤⬤⬤⬤
                               ⬤⬤⬤⬤⬤⬤
                              ⬤⬤⬤⬤⬤⬤⬤
                             ⬤⬤⬤⬤⬤⬤⬤⬤
                            ⬤⬤⬤⬤⬤⬤⬤⬤⬤
                           ⬤⬤⬤⬤⬤⬤⬤⬤⬤⬤
                          ⬤⬤⬤⬤⬤⬤⬤⬤⬤⬤⬤
                         ═══════════════════════
                        ╔═══════════════════════╗
                       ╔╝ ════════════════════ ╚╗
                      ╔╝   ════════════════════  ╚╗
                     ╔╝     ════════════════════   ╚╗
                    ╔╝       ═════════════════════  ╚╗
                   ╔╝         ═════════════════════   ╚╗
                  ╔╝           ═════════════════════   ╚╗
                 ╔╝             ═════════════════════   ╚╗
                ╔╝               ═════════════════════   ╚╗
               ╔╝                 ═════════════════════   ╚╗
              ╔╝                   ═════════════════════   ╚╗
             ╔╝                     ═════════════════════   ╚╗
            ╔╝                       ═════════════════════   ╚╗
           ╔╝                         ═════════════════════   ╚╗
          ╔╝                           ═════════════════════   ╚╗
         ╔╝                             ═════════════════════   ╚╗
        ╔╝                               ═════════════════════   ╚╗
       ╔╝                                 ═════════════════════   ╚╗
      ╔╝                                   ═════════════════════   ╚╗
     ╔╝                                     ═════════════════════   ╚╗
    ╔╝                                       ═════════════════════   ╚╗
   ╔╝                                         ═════════════════════   ╚╗
  ╔╝                                           ═════════════════════   ╚╗
 ╔╝                                             ═════════════════════   ╚╗
╔╝                                               ═════════════════════   ╚╗
╚═══════════════════════════════════════════════════════════════════════╝
    ║                                                       ║
    ║      ❀ Sakura Bloom — Japanese Cherry Blossom ❀     ║
    ║                                                       ║
    ║           🌸 PEACE • BEAUTY • TRANQUILITY 🌸         ║
    ║                                                       ║
SAKURA_ART
}

# ═══════════════════════════════════════════════════════════════════════════
# SYSTEM STATISTICS DISPLAY
# ═══════════════════════════════════════════════════════════════════════════

display_system_stats() {
    # ═══════════════════════════════════════════════════════════════════════
    # Gather System Metrics
    # ═══════════════════════════════════════════════════════════════════════

    # Kernel version
    local kernel_version
    kernel_version=$(uname -r)

    # Hostname
    local hostname
    hostname=$(hostname)

    # RAM statistics
    local mem_total_kb mem_available_kb mem_used_kb mem_percent
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used_kb=$((mem_total_kb - mem_available_kb))
    mem_percent=$((mem_used_kb * 100 / mem_total_kb))

    # Convert to MB for display
    local mem_used_mb mem_total_mb
    mem_used_mb=$((mem_used_kb / 1024))
    mem_total_mb=$((mem_total_kb / 1024))

    # Process count
    local process_count
    process_count=$(ps -e --no-headers | wc -l)

    # System uptime
    local uptime_seconds uptime_days uptime_hours uptime_minutes
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    uptime_days=$((uptime_seconds / 86400))
    uptime_hours=$(( (uptime_seconds % 86400) / 3600 ))
    uptime_minutes=$(( (uptime_seconds % 3600) / 60 ))

    # Load average
    local load_1min load_5min load_15min
    read load_1min load_5min load_15min < /proc/loadavg

    # Disk usage
    local disk_total disk_used disk_percent
    disk_total=$(df -BG / | tail -1 | awk '{print $2}')
    disk_used=$(df -BG / | tail -1 | awk '{print $3}')
    disk_percent=$(df -BG / | tail -1 | awk '{print $5}')

    # ═══════════════════════════════════════════════════════════════════════
    # Display Statistics Dashboard
    # ═══════════════════════════════════════════════════════════════════════

    echo ""
    echo -e "${C_PINK}╔══════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}                                                                              ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_LIGHT_PINK}██╗   ██╗ ██████╗ ██╗   ██╗██╗     ███████╗███████╗${C_RESET}                        ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_LIGHT_PINK}██║   ██║██╔═══██╗██║   ██║██║     ██╔════╝██╔════╝${C_RESET}                        ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_LIGHT_PINK}██║   ██║██║   ██║██║   ██║██║     ███████╗█████╗  ${C_RESET}                        ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_LIGHT_PINK}██║   ██║██║   ██║██║   ██║██║     ╚════██║██╔══╝  ${C_RESET}                        ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_LIGHT_PINK}╚██████╔╝╚██████╔╝╚██████╔╝███████╗███████║███████╗${C_RESET}                        ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_LIGHT_PINK} ╚═════╝  ╚═════╝  ╚═════╝ ╚══════╝╚══════╝╚══════╝${C_RESET}                        ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}                                                                              ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}╔═══════════════════════════════════════════════════════════════════════╗${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_YELLOW}BLOOM OS${C_RESET} — ${C_GREEN}64-bit Ultra-Lightweight Arch Linux Distribution${C_RESET}              ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}                                                                          ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}╠═══════════════════════════════════════════════════════════════════════╣${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}Kernel${C_RESET}    : ${C_CYAN}${kernel_version}${C_RESET}                                      ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}Hostname${C_RESET} : ${C_CYAN}${hostname}${C_RESET}                                          ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}                                                                          ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"

    # RAM display with colour based on usage
    if [[ ${mem_percent} -lt 50 ]]; then
        echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}RAM Usage${C_RESET} : ${C_GREEN}${mem_used_mb} MB / ${mem_total_mb} MB${C_RESET} (${mem_percent}%)                    ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    elif [[ ${mem_percent} -lt 75 ]]; then
        echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}RAM Usage${C_RESET} : ${C_YELLOW}${mem_used_mb} MB / ${mem_total_mb} MB${C_RESET} (${mem_percent}%)                    ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    else
        echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}RAM Usage${C_RESET} : ${C_RED}${mem_used_mb} MB / ${mem_total_mb} MB${C_RESET} (${mem_percent}%)                    ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    fi

    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}Processes${C_RESET}: ${C_CYAN}${process_count}${C_RESET} active processes                                   ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}Uptime${C_RESET}   : ${C_CYAN}${uptime_days}d ${uptime_hours}h ${uptime_minutes}m${C_RESET}                                      ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}Load Avg${C_RESET}  : ${C_CYAN}${load_1min} (1m) ${load_5min} (5m) ${load_15min} (15m)${C_RESET}                  ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}   ${C_LIGHT_PINK}●${C_RESET} ${C_BOLD}Disk${C_RESET}      : ${C_CYAN}${disk_used} / ${disk_total} used${C_RESET} (${disk_percent})                                ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}║${C_RESET}                                                                          ${C_CYAN}║${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}   ${C_BOLD}${C_CYAN}╚═══════════════════════════════════════════════════════════════════════╝${C_RESET}   ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}║${C_RESET}                                                                              ${C_PINK}║${C_RESET}"
    echo -e "${C_PINK}╚══════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""

    # Additional information
    echo -e "  ${C_DIM}Run '${C_CYAN}bloom${C_DIM}' to manage packages${C_RESET}"
    echo -e "  ${C_DIM}Run '${C_CYAN}bloom sync${C_DIM}' to update package database${C_RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# BANNER DISPLAY LOGIC
# ═══════════════════════════════════════════════════════════════════════════

# Only display on interactive shells (prevent duplicate displays)
if [[ -n "${BASH_VERSION:-}" ]]; then
    # Check if this is an interactive shell
    if [[ $- == *i* ]] || [[ -t 0 ]]; then
        # Only show once per session (check environment variable)
        if [[ -z "${BLOOM_BANNER_DISPLAYED:-}" ]]; then
            export BLOOM_BANNER_DISPLAYED=1

            # Clear screen for clean display
            clear

            # Display the cherry blossom art
            display_sakura_art

            # Display system statistics
            display_system_stats
        fi
    fi
fi

# For ZSH compatibility
if [[ -n "${ZSH_VERSION:-}" ]]; then
    if [[ -n "${TERM:-}" ]] && [[ -t 1 ]]; then
        if [[ -z "${BLOOM_BANNER_DISPLAYED:-}" ]]; then
            export BLOOM_BANNER_DISPLAYED=1
            clear
            display_sakura_art
            display_system_stats
        fi
    fi
fi

# Cleanup function (optional, for manual re-display)
bloom-banner() {
    export BLOOM_BANNER_DISPLAYED=
    clear
    display_sakura_art
    display_system_stats
}

# Export functions for manual use
export -f display_sakura_art 2>/dev/null || true
export -f display_system_stats 2>/dev/null || true
export -f bloom-banner 2>/dev/null || true

###############################################################################
# End of cherry_blossom.sh
###############################################################################