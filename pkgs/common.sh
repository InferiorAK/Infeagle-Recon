#!/usr/bin/env bash

# --- Clean exit on Ctrl+C ---
_STTY_SAVE=$(stty -g 2>/dev/null || true)
trap 'stty "$_STTY_SAVE" 2>/dev/null || true; echo -e "\n  ${CR}[-]${CN} Aborted by user"; exit 1' INT

# --- Colors ---
CO="\033[38;5;208m"
CG="\033[0;32m"
CR="\033[0;31m"
CC="\033[0;36m"
CY="\033[0;33m"
CM="\033[0;35m"
CN="\033[0m"
BOLD="\033[1m"

# --- Logging ---
log() {
    local level="$1"; shift
    case "$level" in
        info)  echo -e "  ${CC}[*]${CN} $*" ;;
        ok)    echo -e "  ${CG}[+]${CN} $*" ;;
        warn)  echo -e "  ${CY}[!]${CN} $*" ;;
        err)   echo -e "  ${CR}[-]${CN} $*" ;;
        phase) echo -e "\n  ${CO}── $*${CN}" ;;
    esac
}

silent_log() {
    $SILENT && return 0
    log "$@"
}

# --- Config Loader ---
load_config() {
    local conf_file="$1"
    if [ -f "$conf_file" ]; then
        # General
        OUTPUT_BASE=$(jq -r '.general.output_base // "recon"' "$conf_file")
        KEEP_RAW=$(jq -r '.general.keep_raw // true' "$conf_file")

        # VT key
        VT_API_KEY=$(jq -r '.virustotal_api_key // ""' "$conf_file")

        # Archives
        ARCHIVE_TIMEOUT=$(jq -r '.archive.timeout // 180' "$conf_file")
        CC_ENABLED=$(jq -r '.archive.commoncrawl.enabled // true' "$conf_file")
        CC_INDEX=$(jq -r '.archive.commoncrawl.index // "latest"' "$conf_file")
        CC_MAX_PAGES=$(jq -r '.archive.commoncrawl.max_pages // 0' "$conf_file")
        WB_ENABLED=$(jq -r '.archive.wayback.enabled // true' "$conf_file")
        VT_URLS_ENABLED=$(jq -r '.archive.virustotal_urls.enabled // true' "$conf_file")

        # Subdomain sources
        CRTSH_ENABLED=$(jq -r '.subdomains.crtsh.enabled // true' "$conf_file")
        URLSCAN_ENABLED=$(jq -r '.subdomains.urlscan.enabled // true' "$conf_file")
        ANUBIS_ENABLED=$(jq -r '.subdomains.anubis.enabled // true' "$conf_file")
        VT_SUBS_ENABLED=$(jq -r '.subdomains.virustotal.enabled // true' "$conf_file")

        # Live filter
        FILTER_CONCURRENCY=$(jq -r '.filter.concurrency // 20' "$conf_file")
        FILTER_TIMEOUT=$(jq -r '.filter.timeout // 10' "$conf_file")
        FILTER_MATCH_CODES=$(jq -r '.filter.match_codes // "200,302"' "$conf_file")
        FILTER_FOLLOW_REDIRECTS=$(jq -r '.filter.follow_redirects // false' "$conf_file")

        # Rate limit
        PAGINATION_WAIT=$(jq -r '.rate_limit.pagination_wait // 1' "$conf_file")
        SOURCE_DELAY=$(jq -r '."rate_limit".source_delay // 0' "$conf_file")
    else
        OUTPUT_BASE="recon"
        KEEP_RAW=true
        VT_API_KEY=""
        ARCHIVE_TIMEOUT=180
        CC_ENABLED=true
        CC_INDEX="latest"
        CC_MAX_PAGES=0
        WB_ENABLED=true
        VT_URLS_ENABLED=true
        CRTSH_ENABLED=true
        URLSCAN_ENABLED=true
        ANUBIS_ENABLED=true
        VT_SUBS_ENABLED=true
        FILTER_CONCURRENCY=20
        FILTER_TIMEOUT=10
        FILTER_MATCH_CODES="200,302"
        FILTER_FOLLOW_REDIRECTS=false
        PAGINATION_WAIT=1
        SOURCE_DELAY=0
    fi
}

# --- Dependencies Check ---
check_deps() {
    local missing=()
    command -v curl    &>/dev/null || missing+=("curl")
    command -v jq      &>/dev/null || missing+=("jq")
    command -v python3 &>/dev/null || missing+=("python3")

    if [ ${#missing[@]} -gt 0 ]; then
        log err "Missing dependencies: ${missing[*]}"
        log info "Install: sudo apt install curl jq python3"
        exit 1
    fi

    if [ ! -f "$FILTER_LIVE" ]; then
        log err "filter_live.py not found at ${FILTER_LIVE}"
        exit 1
    fi
}

# --- Banner ---
BANNER="${CO}┌───────────────────────────────────────────────────────────────────────┐${CN}
${CC}│${CN}                                                                       ${CC}│${CN}
${CC}│${CN}  ${CO}  ██╗███╗   ██╗███████╗███████╗ █████╗  ██████╗ ██╗     ███████╗     ${CN}${CC}│${CN}
${CC}│${CN}  ${CO}  ██║████╗  ██║██╔════╝██╔════╝██╔══██╗██╔════╝ ██║     ██╔════╝     ${CN}${CC}│${CN}
${CC}│${CN}  ${CO}  ██║██╔██╗ ██║█████╗  █████╗  ███████║██║  ███╗██║     █████╗       ${CN}${CC}│${CN}
${CC}│${CN}  ${CO}  ██║██║╚██╗██║██╔══╝  ██╔══╝  ██╔══██║██║   ██║██║     ██╔══╝       ${CN}${CC}│${CN}
${CC}│${CN}  ${CO}  ██║██║ ╚████║██║     ███████╗██║  ██║╚██████╔╝███████╗███████╗     ${CN}${CC}│${CN}
${CC}│${CN}  ${CO}  ╚═╝╚═╝  ╚═══╝╚═╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝     ${CN}${CC}│${CN}
${CC}│${CN}                                                                       ${CC}│${CN}
${CC}│${CN}    ${CO}Infeagle-Recon${CN}  —  ${CG}v1.1                                            ${CC}│${CN}
${CC}│${CN}    ${CG}Passive Reconnaissance Suite${CN}                                       ${CC}│${CN}
${CC}│${CN}                                                                       ${CC}│${CN}
${CC}│${CN}    ${CO}Author${CN}   InferiorAK                                                ${CC}│${CN}
${CC}│${CN}    ${CO}GitHub${CN}   github.com/InferiorAK                                     ${CC}│${CN}
${CC}│${CN}    ${CO}Web${CN}      inferiorak.integratedhawkers.com                          ${CC}│${CN}
${CC}│${CN}                                                                       ${CC}│${CN}
${CC}│${CN}    ${CO}Phases${CN}   URLs → Subdomains → Live → Params → Interesting           ${CC}│${CN}
${CC}│${CN}                                                                       ${CC}│${CN}
${CO}└───────────────────────────────────────────────────────────────────────┘${CN}"

