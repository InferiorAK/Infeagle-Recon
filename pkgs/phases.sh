#!/usr/bin/env bash

phase_urls() {
    harvest_urls "$DOMAIN" "$OUTDIR"
}

phase_subdomains() {
    local url_file="${OUTDIR}/urls.txt"
    if [ ! -s "$url_file" ]; then
        find_subdomains "$DOMAIN" "$OUTDIR" ""
    else
        find_subdomains "$DOMAIN" "$OUTDIR" "$url_file"
    fi
}

phase_live() {
    local force_silent="${1:-false}"
    local url_file="${INPUT_FILE:-${OUTDIR}/urls.txt}"
    local live_file="${OUTDIR}/live.txt"

    if [ ! -s "$url_file" ]; then
        log warn "No URLs to check — skipping live filter"
        return
    fi

    log phase "Phase 3: Live URL Filtering"
    local filter_args=(-f "$url_file" -o "$live_file" -c "$CONCURRENCY" -t "$TIMEOUT" --mc "$MATCH_CODES")
    filter_args+=("--no-banner")
    [ "$force_silent" = true ] && filter_args+=("-s")
    $FILTER_FOLLOW_REDIRECTS && filter_args+=("--fr")
    python3 "$FILTER_LIVE" "${filter_args[@]}"
}

phase_params() {
    local live_file="${1:-${OUTDIR}/live.txt}"
    local params_file="${OUTDIR}/params.txt"

    if [ ! -s "$live_file" ]; then
        log warn "No live URLs found — skipping param extraction"
        return
    fi

    log phase "Phase 4: Parameter Extraction"

    grep -E "(\?|&)([a-zA-Z0-9_-]+)=([^&\\s#]+)" < "$live_file" \
        > "$params_file" 2>/dev/null || true

    if [ -s "$params_file" ]; then
        log ok "Parameters extracted: ${CG}$(wc -l < "$params_file")${CN} → ${params_file}"
    else
        log warn "No parameters found"
        > "$params_file"
    fi
}

phase_interesting_wrapper() {
    log phase "Phase 5: Interesting Endpoint Filtering"
    phase_interesting "$OUTDIR"
}

phase_all() {
    phase_urls
    phase_subdomains
    phase_live true
    phase_params
    phase_interesting_wrapper
}
