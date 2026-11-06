#!/usr/bin/env bash
#
# Runs the taint analysis of Psalm over the package in the working directory.
# Only taint findings count. The other issues of Psalm are type checks, which PHPStan covers.
#
# SOURCES lists the directories to analyse, separated by spaces. It defaults to src.
# REPORT names the file for a Markdown report. SARIF names the file for the findings in SARIF.
# COMPOSER_REPOSITORY names a composer repository besides packagist, as a url.
# A package keeps known findings in psalm-taint-baseline.xml. Without that file, every finding counts.
# The exit code is 0 without a finding, 1 with a finding and 2 when the analysis could not run.

set -uo pipefail

: "${REPORT:?REPORT must name the file for the report}"
: "${SARIF:?SARIF must name the file for the SARIF report}"

log=$(mktemp)
issues=$(mktemp)

fail() {
    {
        echo "### Taint analysis could not run"
        echo
        echo '```'
        tail -n 50 "$log"
        echo '```'
    } > "$REPORT"
    cat "$REPORT"
    exit 2
}

[ -z "${COMPOSER_REPOSITORY:-}" ] || composer config repositories.private composer "$COMPOSER_REPOSITORY"

plugins='<pluginClass class="Weirdan\DoctrinePsalmPlugin\Plugin"/>'
packages=('vimeo/psalm:^7.0' 'psalm/plugin-symfony:^5.10' 'weirdan/doctrine-psalm-plugin:^2.11')

# OpenDXP itself is analysed without the plugin. Its stubs would replace the real code.
if [ "$(jq -r .name composer.json)" != open-dxp/opendxp ]; then
    plugins="$plugins<pluginClass class=\"OpenDxp\PsalmPlugin\Plugin\"/>"
    packages+=('open-dxp/psalm-plugin:^1.0')
fi

# Advisories are the job of the audit. The analysis also runs over a dependency that has one.
COMPOSER_NO_SECURITY_BLOCKING=1 composer require --dev --with-all-dependencies --no-interaction --no-progress --no-scripts --no-plugins --ignore-platform-reqs \
    "${packages[@]}" > "$log" 2>&1 || fail

directories=
for source in ${SOURCES:-src}; do
    directories="$directories<directory name=\"$source\"/>"
done

# plugin-symfony fails if its Twig template directory does not exist.
twig_root=templates
[ -d "$twig_root" ] || twig_root=.

cat > psalm-taint.xml <<XML
<?xml version="1.0"?>
<psalm xmlns="https://getpsalm.org/schema/config" findUnusedCode="false" findUnusedBaselineEntry="false">
    <projectFiles>$directories</projectFiles>
    <plugins>
        <pluginClass class="Psalm\SymfonyPsalmPlugin\Plugin"><twigRootPath>$twig_root</twigRootPath></pluginClass>
        $plugins
    </plugins>
</psalm>
XML

baseline=()
[ ! -f psalm-taint-baseline.xml ] || baseline=(--use-baseline=psalm-taint-baseline.xml)

# Psalm exits with 2 for any issue. Only valid JSON shows that the run finished.
rm -f "$SARIF"
php -d memory_limit=-1 vendor/bin/psalm --config=psalm-taint.xml --no-progress --no-cache --output-format=json --report="$SARIF" \
    "${baseline[@]}" > "$issues" 2> "$log"
jq -e 'type == "array"' "$issues" > /dev/null 2>&1 || fail
jq -e '.runs' "$SARIF" > /dev/null 2>&1 || fail

findings='[.[] | select(.type | startswith("Tainted"))]'
count=$(jq "$findings | length" "$issues")

# SARIF refers to a rule by number. The rule list gives the issue type.
# Psalm keeps a finding of the baseline in the SARIF report as a note. Code scanning would list it.
jq '.runs[] |= ([.tool.driver.rules[] | select(.name | startswith("Tainted")) | .id] as $taint
    | .results |= map(select((.ruleId as $id | $taint | index($id)) and .level != "note")))' "$SARIF" > "$SARIF.tmp" && mv "$SARIF.tmp" "$SARIF"

{
    if [ "$count" -eq 0 ]; then
        echo "No taint findings."
    else
        echo "### $count taint findings"
        echo
        echo "| Issue | Location | Message |"
        echo "|---|---|---|"
        jq -r "$findings | .[] | \"| \(.type) | \(.file_name):\(.line_from) | \(.message | gsub(\"\\\\|\"; \"\\\\|\")) |\"" "$issues"
    fi
} > "$REPORT"

[ "$count" -eq 0 ] || exit 1
