#!/usr/bin/env bash
set -euo pipefail

# ======================== PATHS ========================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKGS_DIR="${SCRIPT_DIR}/pkgs"
CONF_FILE="${SCRIPT_DIR}/conf.json"
FILTER_LIVE="${PKGS_DIR}/filter_live.py"
RECON_BASE="${SCRIPT_DIR}/recon"
OUTPUT_BASE="${RECON_BASE}"

# ======================== SOURCE MODULES ========================
for mod in common urls subfind phases interesting; do
    [ -f "${PKGS_DIR}/${mod}.sh" ] && source "${PKGS_DIR}/${mod}.sh" || {
        echo "[-] Missing pkgs/${mod}.sh"; exit 1; }
done

# ======================== DEFAULTS ========================
DOMAIN=""; OUTDIR=""; INPUT_FILE=""; SINGLE_URL=""
SILENT=false; CONCURRENCY=20; TIMEOUT=10; MATCH_CODES="200,302"
CMD=""

# ======================== HELPERS ========================
setup_output_dir() {
    if [ -z "$OUTDIR" ]; then
        local base="${OUTPUT_BASE:-${RECON_BASE}}"
        [[ "$base" != /* ]] && base="${SCRIPT_DIR}/${base}"
        [ -n "$DOMAIN" ] && OUTDIR="${base}/${DOMAIN}" || OUTDIR="${base}/default"
    fi
    mkdir -p "$OUTDIR"
    $KEEP_RAW && mkdir -p "${OUTDIR}/.raw"
}

show_banner() {
    $SILENT && return
    echo -e "$BANNER"
    [ -n "$DOMAIN" ] && echo -e "  ${CC}Target:${CN}  ${BOLD}${DOMAIN}${CN}"
    echo -e "  ${CC}Output:${CN}  ${OUTDIR}"; echo ""
}

handle_url_input() {
    if [ -n "$SINGLE_URL" ]; then
        echo "$SINGLE_URL" > "${OUTDIR}/urls.txt"
        INPUT_FILE="${OUTDIR}/urls.txt"
        return 0
    fi
    if [ -n "$INPUT_FILE" ]; then
        [ -f "$INPUT_FILE" ] || { log err "File not found: ${INPUT_FILE}"; exit 1; }
        cp "$INPUT_FILE" "${OUTDIR}/urls.txt"
        return 0
    fi
    return 1
}

parse_shared() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -d) DOMAIN="$2"; shift 2 ;;
            -o) OUTDIR="$2"; shift 2 ;;
            -f|--file) INPUT_FILE="$2"; shift 2 ;;
            -u|--url) SINGLE_URL="$2"; shift 2 ;;
            -q|--silent) SILENT=true; shift ;;
            -c) CONCURRENCY="$2"; shift 2 ;;
            -t) TIMEOUT="$2"; shift 2 ;;
            --mc) MATCH_CODES="$2"; shift 2 ;;
            -h|--help) return 2 ;;
            *) return 1 ;;
        esac
    done
}

run_checks() {
    check_deps
    setup_output_dir
}

summary() {
    $SILENT && return
    echo ""; echo -e "  ${CO}┌────────────────────────────────────────────${CN}"
    echo -e "  ${CC}│${CN}  ${CO}${BOLD}Infeagle-Recon Complete:${CN} ${CG}${DOMAIN:-.}${CN}"
    echo -e "  ${CO}├────────────────────────────────────────────${CN}"
    local f label path
    for entry in "subdomains.txt:Subdomains" "urls.txt:URLs Harvested" "live.txt:Live Endpoints" "params.txt:Parameters"; do
        f="${entry%%:*}"; label="${entry##*:}"; path="${OUTDIR}/${f}"
        [ -f "$path" ] && echo -e "  ${CC}│${CN}  ${CC}${label}:${CN} ${CG}$(wc -l < "$path")${CN}"
    done
    local ifile="${OUTDIR}/interesting.txt"
    if [ -f "$ifile" ] && [ -s "$ifile" ]; then
        echo -e "  ${CO}├────────────────────────────────────────────${CN}"
        local total=0 name cnt
        while IFS= read -r line; do
            name=$(echo "$line" | sed 's/^  ┌─ //;s/ ([0-9]*) .*$//')
            cnt=$(echo "$line" | grep -o '([0-9]*)' | tr -d '()')
            [ -n "$cnt" ] && echo -e "  ${CC}│${CN}  ${CC}${name}:${CN} ${CG}${cnt}${CN}" && total=$((total + cnt))
        done < <(grep "^  ┌─ " "$ifile")
        while IFS= read -r name; do
            [ "$name" = "Interesting Endpoints" ] && continue
            cnt=$(grep -A1 "^--- ${name} ---" "$ifile" | grep "Count" | grep -o '[0-9][0-9]*$')
            cnt=${cnt:-0}
            [ "$cnt" -gt 0 ] 2>/dev/null || continue
            echo -e "  ${CC}│${CN}  ${CC}${name}:${CN} ${CG}${cnt}${CN}"
            total=$((total + cnt))
        done < <(grep "^--- " "$ifile" | sed 's/^--- //;s/ ---$//')
        echo -e "  ${CC}│${CN}  ${CO}${BOLD}Interesting Total:${CN} ${CG}${total}${CN}"
    fi
    echo -e "  ${CO}├────────────────────────────────────────────${CN}"
    echo -e "  ${CC}│${CN}  ${CC}Output:${CN} ${CY}${OUTDIR}${CN}"
    echo -e "  ${CO}└────────────────────────────────────────────${CN}"; echo ""
}

# ======================== GLOBAL HELP ========================
global_help() {
    echo -e "${CO}Infeagle-Recon${CN} — Passive Reconnaissance Suite"
    echo -e "Author: ${CC}InferiorAK${CN}"
    echo ""
    echo -e "Usage: ${BOLD}$(basename "$0")${CN} ${CC}<command>${CN} [options]"
    echo ""
    echo -e "${CY}Commands:${CN}"
    echo -e "  ${BOLD}urls${CN}         URL harvesting phase only (from archives)"
    echo -e "  ${BOLD}full${CN}         Run all phases"
    echo -e "  ${BOLD}sub${CN}          Subdomain discovery"
    echo -e "  ${BOLD}live${CN}         Live URL filter with probe"
    echo -e "  ${BOLD}param${CN}        Parameter extraction"
    echo -e "  ${BOLD}inter${CN}        Filter interesting endpoints/assets/tokens"
    echo ""
    echo -e "${CY}Global flags:${CN}"
    echo -e "  ${BOLD}-d${CN} ${CC}<domain>${CN}   Target domain"
    echo -e "  ${BOLD}-o${CN} ${CC}<dir>${CN}      Output directory (default: recon/<domain>)"
    echo -e "  ${BOLD}-f${CN} ${CC}<file>${CN}     Input file (skip archive harvest)"
    echo -e "  ${BOLD}-u${CN} ${CC}<url>${CN}      Single URL (skip archive harvest)"
    echo -e "  ${BOLD}-q${CN},${BOLD}--silent${CN}   Suppress banner"
    echo -e "  ${BOLD}-h${CN}            Show this help"
    echo ""
    echo -e "${CY}Run ${BOLD}$(basename "$0") <command> --help${CN} ${CY}for command-specific options${CN}"
    echo ""
    echo -e "${CY}Config:${CN}  Edit ${CC}conf.json${CN} for VirusTotal API key and defaults"
    exit 0
}

# ======================== COMMAND: URLS ========================
help_urls() {
    echo -e "${CO}Infeagle-Recon${CN} — ${BOLD}urls${CN}"
    echo "URL harvesting phase only — collect URLs from archives"
    echo ""
    echo -e "Usage: ${BOLD}$(basename "$0") urls${CN} ${CC}-d <domain>${CN} [options]"
    echo ""
    echo -e "${CY}Options:${CN}"
    echo -e "  ${BOLD}-d${CN} ${CC}<domain>${CN}   Target domain ${CR}(required)${CN}"
    echo -e "  ${BOLD}-o${CN} ${CC}<dir>${CN}      Output directory"
    echo -e "  ${BOLD}-q${CN},${BOLD}--silent${CN}  Suppress banner"
    exit 0
}

cmd_urls() {
    load_config "$CONF_FILE"
    local _r=0
    parse_shared "$@" || _r=$?
    if [ "$_r" -eq 2 ]; then help_urls; fi
    if [ "$_r" -eq 1 ]; then log err "Unknown option for urls"; help_urls; fi
    [ -z "$DOMAIN" ] && { log err "Domain required (-d)"; help_urls; }
    run_checks
    show_banner
    phase_urls
    summary
}

# ======================== COMMAND: FULL ========================
help_full() {
    echo -e "${CO}Infeagle-Recon${CN} — ${BOLD}full${CN}"
    echo "Run all phases: URL harvest → subdomain discovery → live filter → params → inter"
    echo ""
    echo -e "Usage: ${BOLD}$(basename "$0") full${CN} ${CC}-d <domain>${CN} [options]"
    echo ""
    echo -e "${CY}Options:${CN}"
    echo -e "  ${BOLD}-d${CN} ${CC}<domain>${CN}   Target domain ${CR}(required)${CN}"
    echo -e "  ${BOLD}-o${CN} ${CC}<dir>${CN}      Output directory"
    echo -e "  ${BOLD}-q${CN},${BOLD}--silent${CN}  Suppress banner"
    echo -e "  ${BOLD}-c${CN} ${CC}<n>${CN}        Concurrency for live filter (default: 20)"
    echo -e "  ${BOLD}-t${CN} ${CC}<sec>${CN}      Timeout for live filter (default: 10s)"
    echo -e "  ${BOLD}--mc${CN} ${CC}<codes>${CN}  Match status codes (default: 200,302)"
    exit 0
}

cmd_full() {
    load_config "$CONF_FILE"
    local _r=0
    parse_shared "$@" || _r=$?
    if [ "$_r" -eq 2 ]; then help_full; fi
    if [ "$_r" -eq 1 ]; then log err "Unknown option for full"; help_full; fi
    [ -z "$DOMAIN" ] && { log err "Domain required (-d)"; help_full; }
    run_checks
    show_banner
    phase_urls
    find_subdomains "$DOMAIN" "$OUTDIR" "${OUTDIR}/urls.txt"
    phase_live true
    phase_params
    phase_interesting "$OUTDIR"
    summary
}

# ======================== COMMAND: SUB ========================
help_sub() {
    echo -e "${CO}Infeagle-Recon${CN} — ${BOLD}sub${CN}"
    echo "Passive subdomain discovery from URLs + dedicated sources"
    echo ""
    echo -e "Usage: ${BOLD}$(basename "$0") sub${CN} ${CC}-d <domain>${CN} [options]"
    echo ""
    echo -e "${CY}Options:${CN}"
    echo -e "  ${BOLD}-d${CN} ${CC}<domain>${CN}   Target domain ${CR}(required)${CN}"
    echo -e "  ${BOLD}-o${CN} ${CC}<dir>${CN}      Output directory"
    echo -e "  ${BOLD}-f${CN} ${CC}<file>${CN}     URLs file to extract subdomains from"
    echo -e "  ${BOLD}-q${CN},${BOLD}--silent${CN}  Suppress banner"
    exit 0
}

cmd_sub() {
    load_config "$CONF_FILE"
    local _r=0
    parse_shared "$@" || _r=$?
    if [ "$_r" -eq 2 ]; then help_sub; fi
    if [ "$_r" -eq 1 ]; then log err "Unknown option for sub"; help_sub; fi
    [ -z "$DOMAIN" ] && { log err "Domain required (-d)"; help_sub; }
    run_checks
    show_banner
    local url_file="${OUTDIR}/urls.txt"
    if [ -n "$INPUT_FILE" ]; then
        [ -f "$INPUT_FILE" ] || { log err "File not found: $INPUT_FILE"; exit 1; }
        cp "$INPUT_FILE" "$url_file"
    fi
    [ -s "$url_file" ] && find_subdomains "$DOMAIN" "$OUTDIR" "$url_file" \
        || find_subdomains "$DOMAIN" "$OUTDIR" ""
    summary
}

# ======================== COMMAND: LIVE ========================
help_live() {
    echo -e "${CO}Infeagle-Recon${CN} — ${BOLD}live${CN}"
    echo "Live URL filter — probe URLs and save responding endpoints"
    echo ""
    echo -e "Usage: ${BOLD}$(basename "$0") live${CN} [options]"
    echo ""
    echo -e "${CY}Options:${CN}"
    echo -e "  ${BOLD}-f${CN} ${CC}<file>${CN}     Input URLs file ${CR}(required if no -u)${CN}"
    echo -e "  ${BOLD}-u${CN} ${CC}<url>${CN}      Single URL to probe"
    echo -e "  ${BOLD}-o${CN} ${CC}<dir>${CN}      Output directory"
    echo -e "  ${BOLD}-c${CN} ${CC}<n>${CN}        Concurrency (default: 20)"
    echo -e "  ${BOLD}-t${CN} ${CC}<sec>${CN}      Timeout (default: 10s)"
    echo -e "  ${BOLD}--mc${CN} ${CC}<codes>${CN}  Match codes (default: 200,302)"
    echo -e "  ${BOLD}-q${CN},${BOLD}--silent${CN}  Suppress banner"
    exit 0
}

cmd_live() {
    load_config "$CONF_FILE"
    local _r=0
    parse_shared "$@" || _r=$?
    if [ "$_r" -eq 2 ]; then help_live; fi
    if [ "$_r" -eq 1 ]; then log err "Unknown option for live"; help_live; fi
    [ -z "$INPUT_FILE" ] && [ -z "$SINGLE_URL" ] && {
        log err "Provide URLs via -f <file> or -u <url>"; help_live; }
    run_checks
    show_banner
    if [ -n "$SINGLE_URL" ]; then
        echo "$SINGLE_URL" > "${OUTDIR}/urls.txt"
        INPUT_FILE="${OUTDIR}/urls.txt"
    elif [ -n "$INPUT_FILE" ]; then
        [ -f "$INPUT_FILE" ] || { log err "File not found: $INPUT_FILE"; exit 1; }
        cp "$INPUT_FILE" "${OUTDIR}/urls.txt"
    fi
    phase_live $SILENT
    summary
}

# ======================== COMMAND: PARAM ========================
help_param() {
    echo -e "${CO}Infeagle-Recon${CN} — ${BOLD}param${CN}"
    echo "Extract URL parameters from live endpoints"
    echo ""
    echo -e "Usage: ${BOLD}$(basename "$0") param${CN} ${CC}-d <domain>${CN} [options]"
    echo -e "       ${BOLD}$(basename "$0") param${CN} ${CC}-f <file>${CN} [options]"
    echo ""
    echo -e "${CY}Options:${CN}"
    echo -e "  ${BOLD}-d${CN} ${CC}<domain>${CN}   Target domain (reads from recon/<domain>/live.txt)"
    echo -e "  ${BOLD}-f${CN} ${CC}<file>${CN}     Live URLs file to extract params from"
    echo -e "  ${BOLD}-o${CN} ${CC}<dir>${CN}      Output directory"
    echo -e "  ${BOLD}-q${CN},${BOLD}--silent${CN}  Suppress banner"
    exit 0
}

cmd_param() {
    load_config "$CONF_FILE"
    local _r=0
    parse_shared "$@" || _r=$?
    if [ "$_r" -eq 2 ]; then help_param; fi
    if [ "$_r" -eq 1 ]; then log err "Unknown option for param"; help_param; fi
    [ -z "$DOMAIN" ] && [ -z "$INPUT_FILE" ] && {
        log err "Provide a domain (-d) or a live URLs file (-f)"; help_param; }
    run_checks
    show_banner
    if [ -n "$INPUT_FILE" ]; then
        phase_params "$INPUT_FILE"
    else
        phase_params
    fi
    summary
}

# ======================== COMMAND: INTERESTING ========================
help_inter() {
    echo -e "${CO}Infeagle-Recon${CN} — ${BOLD}inter${CN}"
    echo "Filter interesting endpoints, assets, tokens, and credentials from existing outputs."
    echo "Scans urls.txt, subdomains.txt, live.txt, and params.txt in the output directory."
    echo ""
    echo -e "${CY}Note:${CN} Run other phases (${BOLD}full${CN}, ${BOLD}urls${CN}, ${BOLD}sub${CN}, ${BOLD}live${CN}) first to generate the input files."
    echo ""
    echo -e "Usage: ${BOLD}$(basename "$0") inter${CN} ${CC}-d <domain>${CN} [options]"
    echo ""
    echo -e "${CY}Options:${CN}"
    echo -e "  ${BOLD}-d${CN} ${CC}<domain>${CN}   Target domain ${CR}(required)${CN}"
    echo -e "  ${BOLD}-o${CN} ${CC}<dir>${CN}      Output directory"
    echo -e "  ${BOLD}-q${CN},${BOLD}--silent${CN}  Suppress banner"
    exit 0
}

cmd_interesting() {
    load_config "$CONF_FILE"
    local _r=0
    parse_shared "$@" || _r=$?
    if [ "$_r" -eq 2 ]; then help_inter; fi
    if [ "$_r" -eq 1 ]; then log err "Unknown option for inter"; help_inter; fi
    [ -z "$DOMAIN" ] && { log err "Domain required (-d)"; help_inter; }
    run_checks
    show_banner
    phase_interesting "$OUTDIR"
    $SILENT && return
    local ifile="${OUTDIR}/interesting.txt"
    if [ -f "$ifile" ] && [ -s "$ifile" ]; then
        echo ""
        echo -e "  ${CO}┌────────────────────────────────────────────${CN}"
        echo -e "  ${CC}│${CN}  ${CO}${BOLD}Interesting Complete:${CN} ${CG}${DOMAIN}${CN}"
        echo -e "  ${CO}├────────────────────────────────────────────${CN}"
        local total=0 name cnt
        while IFS= read -r line; do
            name=$(echo "$line" | sed 's/^  ┌─ //;s/ ([0-9]*) .*$//')
            cnt=$(echo "$line" | grep -o '([0-9]*)' | tr -d '()')
            [ -n "$cnt" ] && echo -e "  ${CC}│${CN}  ${CC}${name}:${CN} ${CG}${cnt}${CN}" && total=$((total + cnt))
        done < <(grep "^  ┌─ " "$ifile")
        while IFS= read -r name; do
            [ "$name" = "Interesting Endpoints" ] && continue
            cnt=$(grep -A1 "^--- ${name} ---" "$ifile" | grep "Count" | grep -o '[0-9][0-9]*$')
            cnt=${cnt:-0}
            [ "$cnt" -gt 0 ] 2>/dev/null || continue
            echo -e "  ${CC}│${CN}  ${CC}${name}:${CN} ${CG}${cnt}${CN}"
            total=$((total + cnt))
        done < <(grep "^--- " "$ifile" | sed 's/^--- //;s/ ---$//')
        echo -e "  ${CO}├────────────────────────────────────────────${CN}"
        echo -e "  ${CC}│${CN}  ${CO}${BOLD}Total Findings:${CN} ${CG}${total}${CN}"
        echo -e "  ${CO}└────────────────────────────────────────────${CN}"
        echo ""
    fi
}

# ======================== MAIN DISPATCH ========================
main() {
    [ $# -eq 0 ] && global_help

    local cmd="$1"; shift
    case "$cmd" in
        full|--full)  cmd_full "$@" ;;
        sub|--sub)    cmd_sub "$@" ;;
        live|--live)  cmd_live "$@" ;;
        param|--param) cmd_param "$@" ;;
        urls|--urls)  cmd_urls "$@" ;;
        inter|--inter|interesting|--interesting) cmd_interesting "$@" ;;
        -h|--help|help) global_help ;;
        -d) # if -d is first arg, default to full
            set -- "$cmd" "$@"
            cmd_full "$@" ;;
        *)  log err "Unknown command: ${cmd}"; global_help ;;
    esac
}

main "$@"
