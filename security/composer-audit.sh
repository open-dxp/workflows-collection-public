#!/usr/bin/env bash
#
# Checks the dependencies of the package or project in the working directory against the advisory database.
# It writes a Markdown report to the file that REPORT names.
# The exit code is 0 without an advisory, 1 with an advisory and 2 when the check could not run.
#
# IGNORE_LIST names a list in config/vulnerabilities-ignore-list.json. Its advisories are accepted.
# COMPOSER_REPOSITORY names a composer repository besides packagist, as a url.

set -uo pipefail

: "${REPORT:?REPORT must name the file for the report}"

log=$(mktemp)
audit=$(mktemp)

fail() {
    {
        echo "### Composer audit could not run"
        echo
        echo '```'
        cat "$log"
        echo '```'
    } > "$REPORT"
    cat "$REPORT"
    exit 2
}

if [ -n "${IGNORE_LIST:-}" ]; then
    ignored=$(jq -c --arg key "$IGNORE_LIST" '.[$key] // []' "$(dirname "$0")/../config/vulnerabilities-ignore-list.json" 2> "$log") || fail
    if [ "$ignored" != "[]" ]; then
        # composer.json lists ignored advisories either plainly or with a reason for each.
        jq --argjson ignored "$ignored" '.config.audit.ignore |= if type == "object"
            then . + ($ignored | map({(.): "vulnerabilities-ignore-list.json"}) | add) else . + $ignored end' \
            composer.json > composer.json.tmp 2> "$log" || fail
        mv composer.json.tmp composer.json
    fi
fi

[ -z "${COMPOSER_REPOSITORY:-}" ] || composer config repositories.private composer "$COMPOSER_REPOSITORY"

# A project is audited as its lock file installs it. A package without one as a fresh install resolves it.
# Without COMPOSER_NO_SECURITY_BLOCKING, Composer skips versions with a known advisory and the audit never sees them.
[ -f composer.lock ] && install=install || install=update
COMPOSER_NO_SECURITY_BLOCKING=1 composer "$install" --no-interaction --no-progress --no-scripts --ignore-platform-reqs > "$log" 2>&1 || fail

# Composer exits with 1 for an advisory and for an error. Only a valid JSON report means the audit ran.
composer audit --format=json --abandoned=report > "$audit" 2> "$log"
jq -e 'has("advisories")' "$audit" > /dev/null 2>&1 || fail

count=$(jq '[.advisories[]?[]?] | length' "$audit")
abandoned=$(jq -r '(.abandoned // {}) | to_entries[] | "- \(.key), use \(.value // "nothing")"' "$audit")

{
    if [ "$count" -eq 0 ]; then
        echo "No security vulnerability advisories found."
    else
        echo "### $count security vulnerability advisories"
        echo
        echo "| Package | Affected | Severity | Advisory |"
        echo "|---|---|---|---|"
        jq -r 'def cell: gsub("\\|"; "\\|"); [.advisories[]?[]?] | .[] | "| \(.packageName) | \(.affectedVersions | cell) | \(.severity // "unknown") | [\(.cve // .advisoryId)](\(.link)) \(.title | cell) |"' "$audit"
    fi
    if [ -n "$abandoned" ]; then
        echo
        echo "### Abandoned packages"
        echo
        echo "$abandoned"
    fi
} > "$REPORT"

[ "$count" -eq 0 ] || exit 1
