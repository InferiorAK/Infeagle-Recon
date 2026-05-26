#!/usr/bin/env bash

ENDPOINT_RE='/(('\
'admin|dashboard|cpanel|console|panel|manage|administrator'\
'|admin-console|webadmin|superadmin'\
')|('\
'login|signin|auth|oauth|saml|sso|2fa|mfa|otp'\
'|forgot|reset|register|verify|activate|logout'\
')|('\
'graphql|playground|graphiql|introspection|swagger'\
'|api-docs|openapi\\.json|swagger\\.json|swagger-ui'\
')|('\
'\\.env|\\.git/|\\.svn/|\\.DS_Store|\\.hg/'\
'|config\\.json|secrets\\.json|credentials'\
'|database\\.yml|database\\.json|settings\\.json'\
')|('\
'backup|dump|export|sql\\.gz|db\\.sql|dump\\.sql'\
')|('\
'upload|uploads|file-manager|elfinder|filebrowser|filemanager'\
')|('\
'phpinfo|phpmyadmin|adminer|pma'\
')|('\
'crossdomain\\.xml|clientaccesspolicy\\.xml'\
'|robots\\.txt|sitemap\\.xml|security\\.txt|humans\\.txt'\
')|('\
'jenkins|jira|confluence|sonarqube|nexus|artifactory'\
')|('\
'grafana|prometheus|kibana|elasticsearch|sentry'\
')|('\
'actuator|health|metrics|info|env|beans|mappings|heapdump|threaddump'\
')|('\
'wp-admin|wp-content|wp-json|wp-includes|xmlrpc\\.php|wp-config'\
')|('\
'redirect|return_url|next|forward|proxy|callback|webhook'\
')|('\
'websocket|ws|wss|socket\\.io|sse'\
')|('\
's3|bucket|storage|aws|gcs|azure|cloudfront'\
')|('\
'debug|staging|beta|sandbox|dev|internal|test'\
')|('\
'version|api-version|changelog|release-notes|CHANGELOG'\
')|('\
'\\.well-known/|security\\.txt'\
')|('\
'cgi-bin|php-cgi|fcgi'\
'))'

TOKEN_RE='[?&]('\
'token|jwt|access_token|refresh_token|id_token|session_token'\
'|api_key|apikey|api-key|apiKey'\
'|secret|secret_key|client_secret|consumer_secret|private_key'\
'|password|passwd|pwd|pass'\
'|auth|authorization|bearer|signature|sig|hash|hmac'\
'|nonce|code|state|scope'\
'|accesskey|access_key|accessKey|access-token'\
'|redirect_uri|redirect_url|callback_url|return_url|return-to'\
'|client_id|client_secret|grant_type|code_verifier|code_challenge'\
'|csrf|xsrf|cvv|cvc'\
'|otp|mfa|2fa'\
'|aws_access_key_id|aws_secret_access_key'\
'|google_application_credentials|privateKey|publicKey|apiSecret'\
')='

EMAIL_RE='[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}'

# Static asset noise filter — excludes images, fonts, media, archives,
# and common asset directories (applied before endpoint categorization).
# Extensions are matched with EOL/query/hash boundaries to avoid partial matches.
NOISE_EXT_RE='\.(webp|png|jpg|jpeg|gif|svg|ico|bmp|tif|tiff|avif)([?#[:space:]]|$)'\
'|\.(js|jsx|ts|tsx|css|scss|sass|less|map)([?#[:space:]]|$)'\
'|\.(woff|woff2|ttf|otf|eot)([?#[:space:]]|$)'\
'|\.(pdf|doc|docx|xls|xlsx|ppt|pptx)([?#[:space:]]|$)'\
'|\.(zip|tar|gz|rar|7z)([?#[:space:]]|$)'\
'|\.(mp[34]|avi|mov|wmv|flv|webm)([?#[:space:]]|$)'\
'|/images/|/img/|/assets/|/static/|/fonts/|/icons/|/favicon/|/locale/|/i18n/|/translations/|/uploads/'

COMBINED_CATEGORIES=(
    "Admin Panels:admin|dashboard|cpanel|console|panel|administrator|admin-console|webadmin|superadmin|/manage/|/management/"
    "Auth / Login Pages:login|signin|auth|oauth|saml|sso|2fa|mfa|otp|forgot|reset|register|verify|activate|logout"
    "API Endpoints:graphql|playground|graphiql|introspection|swagger|api-docs|openapi\\.json|swagger\\.json|swagger-ui|api/|/v[0-9]/"
    "Sensitive Files:\\.env|\\.git/|\\.svn/|\\.DS_Store|\\.hg/|config\\.json|secrets\\.json|credentials|database\\.yml|database\\.json|settings\\.json|backup|dump|export|sql\\.gz|db\\.sql|dump\\.sql"
    "Dev / Debug:phpinfo|phpmyadmin|adminer|pma([^a-zA-Z0-9]|$)|actuator|health|metrics|env|beans|mappings|heapdump|threaddump|debug|staging|beta|sandbox|internal|(/dev/|/dev[?#]|/dev$)|(/test/|/test[?#]|/test$)|(/stage/|/stage[?#]|/stage$)"
    "DevOps / Enterprise:jenkins|jira|confluence|sonarqube|nexus|artifactory|grafana|prometheus|kibana|elasticsearch|sentry"
    "CMS:wp-admin|wp-content|wp-json|wp-includes|xmlrpc\\.php|wp-config|wordpress|joomla|drupal|magento"
    "Cloud / Storage:s3([^a-zA-Z0-9]|$)|bucket|storage|aws([^a-zA-Z0-9]|$)|gcs([^a-zA-Z0-9]|$)|azure|cloudfront|upload|uploads"
    "Redirect / SSRF:redirect|return_url|next|forward|proxy|callback|webhook|return-to"
    "WebSockets:websocket|ws([^a-zA-Z0-9]|$)|wss([^a-zA-Z0-9]|$)|socket\\.io|sse([^a-zA-Z0-9]|$)"
    "File Operations:file-manager|elfinder|filebrowser|filemanager|download|file\\.php|download\\.php"
    "Info Disclosure:crossdomain\\.xml|clientaccesspolicy\\.xml|robots\\.txt|sitemap\\.xml|security\\.txt|humans\\.txt|version|changelog|release-notes|phpinfo|\.well-known/"
)

# Print a ┌─ box header for a section with name and count
box_header() {
    local label="$1" count="$2" box_w=60
    local text=" ${label} (${count}) "
    local pad=$((box_w - ${#text} - 1))
    [ "$pad" -lt 2 ] && pad=2
    local fill
    printf -v fill '%.0s─' $(seq 1 "$pad")
    echo ""
    echo "  ┌─${text}${fill}┐"
}

extract_by_regex() {
    local infile="$1" regex="$2"
    [ ! -s "$infile" ] && return 1
    grep -iE "$regex" "$infile" 2>/dev/null || true
    [ "$(wc -l < "$infile")" -gt 0 ] 2>/dev/null && return 0 || return 1
}

phase_interesting() {
    local outdir="$1"
    local interesting_file="${outdir}/interesting.txt"
    > "$interesting_file"

    log phase "Phase 5: Interesting Endpoint Filtering"

    local url_file="${outdir}/urls.txt"
    local sub_file="${outdir}/subdomains.txt"
    local live_file="${outdir}/live.txt"
    local param_file="${outdir}/params.txt"

    local raw_dir="${outdir}/.raw"
    mkdir -p "$raw_dir"

    local combined_urls="${raw_dir}/.combined_urls.tmp"
    > "$combined_urls"

    for f in "$url_file" "$live_file"; do
        [ -f "$f" ] && [ -s "$f" ] && cat "$f" >> "$combined_urls"
    done
    sort -u "$combined_urls" -o "$combined_urls" 2>/dev/null || true

    {
        echo "# Infeagle-Recon Interesting Findings"
        echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Target:    ${DOMAIN:-N/A}"
        echo "# Output:    ${outdir}"
        echo "==========================================="
        echo ""
    } > "$interesting_file"

    local found_any=false

    # --- Categorized Endpoints (from urls.txt + live.txt combined) ---
    if [ -s "$combined_urls" ]; then
        # Pre-filter: remove static assets so categories show only actionable URLs
        local filtered_urls="${raw_dir}/.filtered_urls.tmp"
        grep -viE "$NOISE_EXT_RE" "$combined_urls" > "$filtered_urls" 2>/dev/null || true
        [ ! -s "$filtered_urls" ] && { rm -f "$filtered_urls"; log warn "All URLs filtered out as static assets"; }

        local cat_tmp="${raw_dir}/.cat_endpoints.tmp"
        > "$cat_tmp"

        local entry cat_name cat_regex
        for entry in "${COMBINED_CATEGORIES[@]}"; do
            cat_name="${entry%%:*}"
            cat_regex="${entry#*:}"
            grep -iE "$cat_regex" "$filtered_urls" >> "$cat_tmp" 2>/dev/null || true
        done

        if [ -s "$cat_tmp" ]; then
            sort -u "$cat_tmp" -o "$cat_tmp"
            local total_cat
            total_cat=$(wc -l < "$cat_tmp")
            {
                echo "--- Interesting Endpoints ---"
                echo "  Count : ${total_cat}"
                echo "-----------------------------------"
            } >> "$interesting_file"

            for entry in "${COMBINED_CATEGORIES[@]}"; do
                cat_name="${entry%%:*}"
                cat_regex="${entry#*:}"
                local sub_tmp="${raw_dir}/.sub_$(echo "$cat_name" | tr -c 'a-zA-Z0-9' '_').tmp"
                grep -iE "$cat_regex" "$filtered_urls" > "$sub_tmp" 2>/dev/null || true
                if [ -s "$sub_tmp" ]; then
                    local sub_count
                    sub_count=$(wc -l < "$sub_tmp")
                    {
                        box_header "$cat_name" "$sub_count"
                        while IFS= read -r line; do
                            echo "    ${line}"
                        done < "$sub_tmp"
                    } >> "$interesting_file"
                fi
                rm -f "$sub_tmp"
            done

            found_any=true
        fi
        rm -f "$cat_tmp" "$filtered_urls"
    fi

    # --- Tokens in URLs (from combined URLs) ---
    if [ -s "$combined_urls" ]; then
        local tok_tmp="${raw_dir}/.tokens.tmp"
        grep -iE "$TOKEN_RE" "$combined_urls" > "$tok_tmp" 2>/dev/null || true
        if [ -s "$tok_tmp" ]; then
            local tok_count
            tok_count=$(wc -l < "$tok_tmp")
            {
                box_header "Tokens / Credentials in URLs" "$tok_count"
                sed 's/^/    /' "$tok_tmp"
            } >> "$interesting_file"
            found_any=true
        fi
        rm -f "$tok_tmp"
    fi

    # --- Emails (from combined URLs) ---
    if [ -s "$combined_urls" ]; then
        local email_tmp="${raw_dir}/.emails.tmp"
        grep -ioE "$EMAIL_RE" "$combined_urls" | sort -u > "$email_tmp" 2>/dev/null || true
        if [ -s "$email_tmp" ]; then
            {
                box_header "Emails Discovered" "$(wc -l < "$email_tmp")"
                sed 's/^/    /' "$email_tmp"
            } >> "$interesting_file"
            found_any=true
        fi
        rm -f "$email_tmp"
    fi

    # --- Interesting Subdomains ---
    if [ -f "$sub_file" ] && [ -s "$sub_file" ]; then
        local sub_tmp="${raw_dir}/.interesting_subs.tmp"
        grep -iE '^('\
'api|admin|dev|staging|test|beta|sandbox|internal'\
'|portal|dashboard|console|cpanel|manager'\
'|gateway|proxy|vpn|mail|email|smtp|imap|pop'\
'|jenkins|git|gitlab|jira|confluence|wiki|docs'\
'|kibana|grafana|prometheus|monitor|status|health'\
'|s3|bucket|cdn|static|assets|storage|upload|download'\
'|swagger|graphql|playground|api-docs|api'\
'|auth|login|secure|sso|oauth|saml'\
'|db|database|mysql|redis|mongo|elastic'\
'|ws|websocket|webhook|callback'\
'|ftp|sftp|ssh|vpn'\
'|backup|dr|stage|qa|uat|preprod'\
')\.' "$sub_file" > "$sub_tmp" 2>/dev/null || true

        if [ -s "$sub_tmp" ]; then
            {
                box_header "Interesting Subdomains" "$(wc -l < "$sub_tmp")"
                sed 's/^/    /' "$sub_tmp"
            } >> "$interesting_file"
            found_any=true
        fi
        rm -f "$sub_tmp"
    fi

    # --- Interesting Parameters (from params.txt) ---
    if [ -f "$param_file" ] && [ -s "$param_file" ]; then
        local ptmp="${raw_dir}/.interesting_params.tmp"
        grep -iE "$TOKEN_RE" "$param_file" > "$ptmp" 2>/dev/null || true
        if [ -s "$ptmp" ]; then
            {
                box_header "Interesting Parameters" "$(wc -l < "$ptmp")"
                sed 's/^/    /' "$ptmp"
            } >> "$interesting_file"
            found_any=true
        fi
        rm -f "$ptmp"
    fi

    rm -f "$combined_urls"

    if [ "$found_any" = true ]; then
        log ok "Interesting findings saved → ${interesting_file}"
    else
        echo "--- No interesting findings ---" >> "$interesting_file"
        log warn "No interesting findings discovered"
    fi
}
