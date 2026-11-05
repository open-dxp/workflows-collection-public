#!/usr/bin/env bash
#
# Creates a CycloneDX SBOM of the package in the working directory, without its development dependencies.
# VERSION is the released version of the package, without a leading v. SBOM names the file for the SBOM.

set -euo pipefail

: "${VERSION:?VERSION must name the released version}"
: "${SBOM:?SBOM must name the file for the SBOM}"

export COMPOSER_ROOT_VERSION="$VERSION"

# The package has no lock file. The SBOM lists what a fresh install of the release resolves to.
composer update --no-dev --no-scripts --no-plugins --no-interaction --no-progress --ignore-platform-reqs

composer global config --no-interaction allow-plugins.cyclonedx/cyclonedx-php-composer true
composer global require --no-interaction --no-progress cyclonedx/cyclonedx-php-composer:^6.2
composer CycloneDX:make-sbom --output-format=JSON --spec-version=1.6 --omit=dev --validate \
    --mc-version="$VERSION" --output-file="$SBOM"
