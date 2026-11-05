#!/usr/bin/env bash
#
# Searches the commits of the repository in the working directory for secrets, with gitleaks.
# RANGE limits the search to the commits git log selects with it, such as base..head. Without it, gitleaks
# searches the whole history.
# REPORT names the file for a Markdown report.
# The exit code is 0 without a finding, 1 with a finding and 2 when the search could not run.

set -uo pipefail

: "${REPORT:?REPORT must name the file for the report}"

log=$(mktemp)

report() {
    {
        echo "### $1"
        echo
        [ -z "${2:-}" ] || { echo "$2"; echo; }
        echo '```'
        cat "$log"
        echo '```'
    } > "$REPORT"
}

# For a range git cannot resolve, gitleaks reports no finding instead of an error.
if [ -n "${RANGE:-}" ]; then
    read -ra range <<< "$RANGE"
    git rev-list "${range[@]}" > /dev/null 2> "$log" || { report "Secret scan could not run"; cat "$REPORT"; exit 2; }
fi

gitleaks=$(cd "$(dirname "$0")/gitleaks" && pwd)
image=$(sed -n 's/^FROM //p' "$gitleaks/Dockerfile")

# gitleaks exits with 1 on an error. Exit code 3 marks findings.
docker run --rm -v "$PWD:/repo" -v "$gitleaks/gitleaks.toml:/gitleaks.toml:ro" "$image" \
    git /repo --config /gitleaks.toml --log-opts="${RANGE:-}" \
    --redact --verbose --no-banner --no-color --exit-code 3 > "$log" 2>&1

case $? in
    0) echo "No secrets found." > "$REPORT" ;;
    3) report "Secrets found" "Revoke each secret with its provider. Removing it from the code is not enough."; exit 1 ;;
    *) report "Secret scan could not run"; cat "$REPORT"; exit 2 ;;
esac
