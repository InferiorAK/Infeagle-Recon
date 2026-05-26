#!/usr/bin/env bash

fetch_crtsh() {
    local domain="$1" out="$2"
    silent_log info "crt.sh: harvesting certificates for ${domain}"
    curl -sf --max-time "$ARCHIVE_TIMEOUT" "https://crt.sh/?q=%25.${domain}&output=json" 2>/dev/null \
        | jq -r '.[].name_value // empty' 2>/dev/null \
        | sed 's/\*\.//g' | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -E "\.${domain}$" | sort -u > "$out" || true
}

fetch_urlscan() {
    local domain="$1" out="$2"
    silent_log info "URLScan.io: fetching scans for ${domain}"
    curl -sf --max-time "$ARCHIVE_TIMEOUT" "https://urlscan.io/api/v1/search/?q=domain:${domain}&size=10000" 2>/dev/null \
        | jq -r '.results[].page.domain // empty' 2>/dev/null \
        | grep -E "\.${domain}$" | sort -u > "$out" || true
}

fetch_anubis() {
    local domain="$1" out="$2"
    silent_log info "AnubisDB: querying subdomains for ${domain}"
    curl -sf --max-time "$ARCHIVE_TIMEOUT" "https://jldc.me/anubis/subdomains/${domain}" 2>/dev/null \
        | jq -r '.[] // empty' 2>/dev/null \
        | grep -E "\.${domain}$" | sort -u > "$out" || true
}

fetch_virustotal_subs() {
    local domain="$1" out="$2"
    > "$out"
    [ -z "$VT_API_KEY" ] && return 1

    local tmp
    tmp=$(curl -sf --max-time "$ARCHIVE_TIMEOUT" "https://www.virustotal.com/vtapi/v2/domain/report?apikey=${VT_API_KEY}&domain=${domain}" 2>/dev/null || true)
    echo "$tmp" | jq -r '.subdomains[] // empty' 2>/dev/null \
        | grep -E "\.${domain}$" | sort -u > "$out" 2>/dev/null || true
}

extract_subs_from_urls() {
    local urlfile="$1" domain="$2" out="$3"
    if [ ! -s "$urlfile" ]; then > "$out"; return; fi
    awk -F/ '{print $3}' "$urlfile" \
        | sed 's/^[^:]*://; s/@.*//' \
        | grep -E "\.${domain}$" \
        | sort -u > "$out"
}

find_subdomains() {
    local domain="$1" outdir="$2" url_file="${3:-}"
    local raw_dir="${outdir}/.raw"
    $KEEP_RAW && mkdir -p "$raw_dir"
    local sub_file="${outdir}/subdomains.txt"
    local all_subs="${raw_dir}/subs_all.txt"
    > "$all_subs"

    log phase "Phase 2: Subdomain Discovery"

    #--- Extract from URLs if available ---
    if [ -n "$url_file" ] && [ -s "$url_file" ]; then
        local subs_from_urls="${raw_dir}/subs_from_urls.txt"
        extract_subs_from_urls "$url_file" "$domain" "$subs_from_urls"
        if [ -s "$subs_from_urls" ]; then
            cat "$subs_from_urls" >> "$all_subs"
            silent_log ok "URLs source: $(wc -l < "$subs_from_urls") subdomains"
        else
            silent_log warn "URLs source: no subdomains found"
        fi
    fi

    #--- crt.sh ---
    if [ "$CRTSH_ENABLED" = true ]; then
        local crt_out="${raw_dir}/crtsh.txt"
        fetch_crtsh "$domain" "$crt_out"
        if [ -s "$crt_out" ]; then cat "$crt_out" >> "$all_subs"
            silent_log ok "crt.sh: $(wc -l < "$crt_out") subdomains"
        else silent_log warn "crt.sh: no results"; fi
    else silent_log info "crt.sh: disabled in config"; fi

    #--- URLScan.io ---
    if [ "$URLSCAN_ENABLED" = true ]; then
        local us_out="${raw_dir}/urlscan.txt"
        fetch_urlscan "$domain" "$us_out"
        if [ -s "$us_out" ]; then cat "$us_out" >> "$all_subs"
            silent_log ok "URLScan.io: $(wc -l < "$us_out") subdomains"
        else silent_log warn "URLScan.io: no results"; fi
    else silent_log info "URLScan.io: disabled in config"; fi

    #--- AnubisDB ---
    if [ "$ANUBIS_ENABLED" = true ]; then
        local an_out="${raw_dir}/anubis.txt"
        fetch_anubis "$domain" "$an_out"
        if [ -s "$an_out" ]; then cat "$an_out" >> "$all_subs"
            silent_log ok "AnubisDB: $(wc -l < "$an_out") subdomains"
        else silent_log warn "AnubisDB: no results"; fi
    else silent_log info "AnubisDB: disabled in config"; fi

    #--- VirusTotal Subdomains ---
    if [ "$VT_SUBS_ENABLED" = true ] && [ -n "$VT_API_KEY" ]; then
        local vt_subs="${raw_dir}/virustotal_subs.txt"
        fetch_virustotal_subs "$domain" "$vt_subs"
        if [ -s "$vt_subs" ]; then cat "$vt_subs" >> "$all_subs"
            silent_log ok "VirusTotal: $(wc -l < "$vt_subs") subdomains"
        else silent_log warn "VirusTotal: no subdomains"; fi
    elif [ "$VT_SUBS_ENABLED" = true ] && [ -z "$VT_API_KEY" ]; then
        silent_log info "VirusTotal: no API key — skipped"
    else
        silent_log info "VirusTotal subdomains: disabled in config"
    fi

    sort -u "$all_subs" -o "$sub_file"
    log ok "Subdomains collected: ${CG}$(wc -l < "$sub_file")${CN} → ${sub_file}"
}
