#!/usr/bin/env bash

get_latest_cc_index() {
    if [ "$CC_INDEX" != "latest" ]; then
        echo "$CC_INDEX"
        return
    fi
    curl -sf "https://index.commoncrawl.org/" 2>/dev/null \
        | jq -r '[.[].id] | sort | .[-1] // "CC-MAIN-2026-17"' 2>/dev/null \
        || echo "CC-MAIN-2026-17"
}

fetch_commoncrawl() {
    local query="$1" index="$2" outfile="$3"
    local tmpfile="${outfile}.tmp"
    > "$tmpfile"

    local pages
    pages=$(curl -sf --max-time "$ARCHIVE_TIMEOUT" "https://index.commoncrawl.org/${index}-index?url=${query}&showNumPages=true" 2>/dev/null \
        | jq -r '.pages // 0' 2>/dev/null || echo 0)

    if [ "$pages" -le 0 ] 2>/dev/null; then
        silent_log warn "No pages for query: ${query} (index: ${index})"
        rm -f "$tmpfile"; return
    fi

    if [ "$CC_MAX_PAGES" -gt 0 ] 2>/dev/null && [ "$pages" -gt "$CC_MAX_PAGES" ]; then
        silent_log info "CommonCrawl: ${pages} pages found, limiting to ${CC_MAX_PAGES}"
        pages=$CC_MAX_PAGES
    fi

    silent_log info "CommonCrawl: ${pages} page(s) for ${query}"
    for ((p=0; p<pages; p++)); do
        curl -sf --max-time "$ARCHIVE_TIMEOUT" "https://index.commoncrawl.org/${index}-index?url=${query}&output=json&page=${p}" 2>/dev/null \
            | jq -r '.url // empty' 2>/dev/null >> "$tmpfile" || true
        sleep "$PAGINATION_WAIT"
    done

    if [ -s "$tmpfile" ]; then sort -u "$tmpfile" -o "$outfile"; fi
    rm -f "$tmpfile"
}

fetch_wayback() {
    local query="$1" outfile="$2"
    local tmpfile="${outfile}.tmp"

    curl -sf --max-time "$ARCHIVE_TIMEOUT" "http://web.archive.org/cdx/search/cdx?url=${query}&output=json&collapse=urlkey" 2>/dev/null \
        | jq -r '.[1:][][2] // empty' 2>/dev/null > "$tmpfile" || true

    if [ -s "$tmpfile" ]; then sort -u "$tmpfile" -o "$outfile"
    else > "$outfile"; fi
    rm -f "$tmpfile"
}

fetch_virustotal_urls() {
    local domain="$1" out="$2"
    > "$out"
    [ -z "$VT_API_KEY" ] && return 1

    local tmp
    tmp=$(curl -sf --max-time "$ARCHIVE_TIMEOUT" "https://www.virustotal.com/vtapi/v2/domain/report?apikey=${VT_API_KEY}&domain=${domain}" 2>/dev/null || true)
    {
        echo "$tmp" | jq -r '.detected_urls[].url // empty' 2>/dev/null
        echo "$tmp" | jq -r '.undetected_urls[][0] // empty' 2>/dev/null
    } | grep -F ".${domain}" | sort -u > "$out" 2>/dev/null || true
}

harvest_urls() {
    local domain="$1" outdir="$2"
    local raw_dir="${outdir}/.raw"
    $KEEP_RAW && mkdir -p "$raw_dir"
    local url_file="${outdir}/urls.txt"
    local all_urls="${raw_dir}/urls_all.txt"
    > "$all_urls"

    log phase "Phase 1: URL Harvesting from Archives"

    #--- CommonCrawl ---
    if [ "$CC_ENABLED" = true ]; then
        local cc_index
        cc_index=$(get_latest_cc_index)
        silent_log info "CommonCrawl index: ${cc_index}"

        local cc_domain="${raw_dir}/commoncrawl_domain.txt"
        fetch_commoncrawl "${domain}/*" "$cc_index" "$cc_domain"
        if [ -s "$cc_domain" ]; then cat "$cc_domain" >> "$all_urls"
            silent_log ok "CommonCrawl (${domain}): $(wc -l < "$cc_domain") URLs"
        else silent_log warn "CommonCrawl (${domain}): no URLs"; fi

        local cc_wild="${raw_dir}/commoncrawl_wild.txt"
        fetch_commoncrawl "*.${domain}/*" "$cc_index" "$cc_wild"
        if [ -s "$cc_wild" ]; then cat "$cc_wild" >> "$all_urls"
            silent_log ok "CommonCrawl (*.${domain}): $(wc -l < "$cc_wild") URLs"
        else silent_log warn "CommonCrawl (*.${domain}): no URLs"; fi
    else
        silent_log info "CommonCrawl: disabled in config"
    fi

    #--- Wayback Machine ---
    if [ "$WB_ENABLED" = true ]; then
        local wb_domain="${raw_dir}/wayback_domain.txt"
        fetch_wayback "${domain}/*" "$wb_domain"
        if [ -s "$wb_domain" ]; then cat "$wb_domain" >> "$all_urls"
            silent_log ok "Wayback (${domain}): $(wc -l < "$wb_domain") URLs"
        else silent_log warn "Wayback (${domain}): no URLs"; fi

        local wb_wild="${raw_dir}/wayback_wild.txt"
        fetch_wayback "*.${domain}/*" "$wb_wild"
        if [ -s "$wb_wild" ]; then cat "$wb_wild" >> "$all_urls"
            silent_log ok "Wayback (*.${domain}): $(wc -l < "$wb_wild") URLs"
        else silent_log warn "Wayback (*.${domain}): no URLs"; fi

    else
        silent_log warn "Wayback: disabled in config"
    fi

    #--- VirusTotal URLs ---
    if [ "$VT_URLS_ENABLED" = true ] && [ -n "$VT_API_KEY" ]; then
        local vt_urls="${raw_dir}/virustotal_urls.txt"
        fetch_virustotal_urls "$domain" "$vt_urls"
        if [ -s "$vt_urls" ]; then cat "$vt_urls" >> "$all_urls"
            silent_log ok "VirusTotal: $(wc -l < "$vt_urls") URLs"
        else
            silent_log warn "VirusTotal: no URLs"
        fi
    elif [ "$VT_URLS_ENABLED" = true ] && [ -z "$VT_API_KEY" ]; then
        silent_log info "VirusTotal: no API key — skipped"
    else
        silent_log info "VirusTotal URLs: disabled in config"
    fi

    sort -u "$all_urls" -o "$url_file"
    log ok "URLs harvested: ${CG}$(wc -l < "$url_file")${CN} → ${url_file}"
}
