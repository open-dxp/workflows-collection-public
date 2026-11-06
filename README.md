# OpenDXP workflows

Reusable GitHub workflows and actions for OpenDXP packages. A package keeps its tests, its rule
files and its triggers, and calls a workflow from here to run them.

Everything here is called with `uses:`. Nothing runs on this repository itself.

## What is here

| Workflow                                 |                                                                                 |
|------------------------------------------|---------------------------------------------------------------------------------|
| `reusable-ci.yaml`                       | runs the tests, the analysis and the security checks of a pull request          |
| `reusable-pest-tests.yaml`               | runs a package's Pest suite in an OpenDXP application built for it              |
| `reusable-static-analysis.yaml`          | runs phpstan over a package, against the same application                       |
| `reusable-php-cs-fixer.yaml`             | runs php-cs-fixer and commits the fixes                                         |
| `reusable-changelog.yaml`                | checks the `CHANGELOG.md` of a pull request: an entry and its form              |
| `reusable-composer-vulnerabilities.yaml` | checks the installed packages against the advisory database                     |
| `reusable-taint-analysis.yaml`           | follows input from a request into SQL, HTML, files and other sinks, with Psalm  |
| `reusable-secret-scan.yaml`              | searches the commits for secrets, with gitleaks                                 |
| `reusable-sbom.yaml`                     | attaches a CycloneDX SBOM to a release                                          |
| `reusable-cla-check.yaml`                | checks that a contributor has signed the CLA                                    |
| `stale.yml`                              | marks issues nobody has answered for 20 days                                    |

| Action                      |                                                      |
|-----------------------------|------------------------------------------------------|
| `build-opendxp-application` | builds an OpenDXP application with the package in it |
| `test-matrix`               | builds a job matrix from a matrix configuration      |

| Configuration                             |                                                           |
|-------------------------------------------|-----------------------------------------------------------|
| `tests-configuration/`                    | the matrix for test runs                                  |
| `phpstan-configuration/`                  | the matrix for analysis runs                              |
| `php-cs-fixer-configuration/`             | the shared php-cs-fixer rule sets                         |
| `config/vulnerabilities-ignore-list.json` | accepted advisories, looked up by the `ignore-list` input |
| `security/`                               | the scripts of the security checks                        |

| Changelog lint            |                                                           |
|---------------------------|-----------------------------------------------------------|
| `changelog-lint/lint.mjs` | reads a `CHANGELOG.md` and reports what breaks its format |

## How a test run is put together

A package cannot be tested on its own. OpenDXP needs an application around it, with a kernel, a
configuration, a database and installed bundles. `open-dxp/test-foundation` ships that application.
The Pest and the analysis workflow both build it through `build-opendxp-application`:

1. check the package out
2. build an application beside it, with the package linked into `vendor`
3. install OpenDXP into it
4. run Pest, or phpstan

Nothing of this lives in your repository.
You do not keep a `bin/console`, a `config/` or a `public/index.php` for the sake of CI.

## CI of a package

`.github/workflows/ci.yaml` in your package:

```yaml
name: CI

on:
    workflow_dispatch:
    schedule:
        -   cron: '0 5 * * *'
    push:
        branches:
            - "[0-9]+.[0-9]+"
            - "[0-9]+.x"
    pull_request:
        types: [ opened, synchronize, reopened ]

jobs:
    ci:
        uses: open-dxp/workflows-collection-public/.github/workflows/reusable-ci.yaml@main
        with:
            composer_repository: 'https://my-registry.com'
        secrets: inherit
```

`reusable-ci.yaml` calls the workflows below. Which ones run depends on the event:

| Event                        | Pest tests | Static analysis | Security checks |
|------------------------------|------------|-----------------|-----------------|
| pull request                 | yes        | yes             | yes             |
| push to a version branch     | no         | no              | yes             |
| schedule                     | no         | Mondays only    | yes             |
| run by hand                  | yes        | yes             | yes             |

A pull request has run the tests on the code before its merge, so a push does not run them again. A
pull request that changes only `.md` files or files in `doc/` or `docs/` skips the tests and the
analysis. A new run cancels the run of the same pull request or branch that is still going.

The last job, `ci / ci-passed`, fails when one of the others fails. The CI ruleset of the organisation
requires this check in every repository whose property `ci-gate` is `true`.

Options of `reusable-ci.yaml`. Each one is handed to the workflow of the same name.

|                                   |                                                    |
|-----------------------------------|----------------------------------------------------|
| `composer_repository`             | a composer repository besides packagist, as a url  |
| `enable_browser`                  | see `reusable-pest-tests.yaml`                     |
| `enable_redis_service`            | see `reusable-pest-tests.yaml`                     |
| `enable_opensearch_service`       | see `reusable-pest-tests.yaml`                     |
| `install_ghostscript_and_pdfinfo` | see `reusable-pest-tests.yaml`                     |
| `install_ffmpeg`                  | see `reusable-pest-tests.yaml`                     |
| `taint_sources`                   | `sources` of `reusable-taint-analysis.yaml`        |

## Running the tests

`reusable-ci.yaml` runs the tests. A package can also call them in a workflow of its own:

```yaml
name: Pest tests

on:
    workflow_dispatch:
    push:
        branches:
            - "[0-9]+.[0-9]+"
            - "[0-9]+.x"

jobs:
    setup-matrix:
        runs-on: ubuntu-latest
        outputs:
            matrix: ${{ steps.matrix.outputs.matrix }}
        steps:
            -   uses: actions/checkout@v7

            -   id: matrix
                uses: open-dxp/workflows-collection-public/.github/actions/test-matrix@main
                with:
                    configuration: tests-configuration

    pest-tests:
        needs: setup-matrix
        strategy:
            matrix: ${{ fromJson(needs.setup-matrix.outputs.matrix) }}
        uses: open-dxp/workflows-collection-public/.github/workflows/reusable-pest-tests.yaml@main
        with:
            php_version: ${{ matrix.matrix.php-version }}
            database: ${{ matrix.matrix.database }}
            server_version: ${{ matrix.matrix.server_version }}
            dependencies: ${{ matrix.matrix.dependencies }}
            experimental: ${{ matrix.matrix.experimental }}
            opendxp_version: ${{ matrix.matrix.opendxp_version }}
        secrets:
            COMPOSER_AUTH: ${{ secrets.COMPOSER_AUTH }}
```

### What the package has to have

A `phpunit.xml.dist`, a `tests/Application/TestKernel.php` and `open-dxp/test-foundation` under
`require-dev`. How to write any of it is in [open-dxp/test-foundation](https://github.com/open-dxp/test-foundation).

## Static analysis

The same shape, with the phpstan matrix:

```yaml
    setup-matrix:
        steps:
            -   id: matrix
                uses: open-dxp/workflows-collection-public/.github/actions/test-matrix@main
                with:
                    configuration: phpstan-configuration

    static-analysis:
        needs: setup-matrix
        strategy:
            matrix: ${{ fromJson(needs.setup-matrix.outputs.matrix) }}
        uses: open-dxp/workflows-collection-public/.github/workflows/reusable-static-analysis.yaml@main
        with:
            php_version: ${{ matrix.matrix.php-version }}
            experimental: ${{ matrix.matrix.experimental }}
```

The analysis builds and installs the same application as the tests. It then runs
`opendxp-test analyse` in it. [Commands](https://github.com/open-dxp/test-foundation#commands) in the
test foundation lists what it checks.

## The matrix

`test-matrix` reads the php versions your `composer.json` supports and picks the matching entry
from a configuration in this repository:

```
tests-configuration/matrix-config.json     for test runs
phpstan-configuration/matrix-config.json   for the analysis
```

It fails when nothing matches. An empty matrix runs no tests and still reports success, which
looks like a suite that passed.

## Options

`reusable-pest-tests.yaml` and `reusable-static-analysis.yaml`:

|                                |                                                                                                           |
|--------------------------------|-----------------------------------------------------------------------------------------------------------|
| `php_version`                  | required                                                                                                  |
| `dependencies`                 | `locked`, `highest` or `lowest`, handed to composer                                                       |
| `database`                     | `mysql:8.4` by default, an image name                                                                     |
| `server_version`               | the server version doctrine is configured with, matches the image, required by `reusable-pest-tests.yaml` |
| `experimental`                 | a failure does not fail the run                                                                           |
| `opendxp_version`              | a version of `open-dxp/opendxp` to force                                                                  |
| `composer_repository`          | a composer repository besides packagist, as a url                                                         |
| `execute_post_checkout_action` | run `.github/actions/post-checkout-action` of your package                                                |

`reusable-pest-tests.yaml` also:

|                                   |                                                      |
|-----------------------------------|------------------------------------------------------|
| `enable_browser`                  | run the tests in the `browser` group, off by default |
| `pest_options`                    | passed to Pest unchanged                             |
| `enable_redis_service`            | a redis container beside the application             |
| `enable_opensearch_service`       | an opensearch container beside the application       |
| `install_ghostscript_and_pdfinfo` | for suites that read pdfs                            |
| `install_ffmpeg`                  | for suites that convert videos                       |

The defaults for `redis_dsn`, `opendxp_open_search_host` and `opendxp_opensearch_version` match
what the containers are started with. Change them only if your tests expect other values.

`reusable-static-analysis.yaml` also:

|                     |                                                     |
|---------------------|-----------------------------------------------------|
| `generate_baseline` | on a failure, attach a baseline of everything found |

Running a browser downloads chromium and costs seconds per test, so `enable_browser` is off by
default. With it, the tests marked `->group('browser')` run as well.

## Code style

`reusable-php-cs-fixer.yaml` runs php-cs-fixer and commits what it changed. A package either brings
its own configuration, or uses one from `php-cs-fixer-configuration/`:

```yaml
with:
    head_ref: ${{ github.head_ref }}
    repository: ${{ github.event.pull_request.head.repo.full_name }}
    use_global_config: true
    cs_fixer_mode: bundle
```

`cs_fixer_mode` picks the rule set: `core`, `bundle`.
The global configurations read the files to fix from `.php-cs-fixer-finder.dist.php` in your
package, so that file stays with the package. Without `use_global_config` the workflow uses
`config_file`.

## Security checks

Four workflows check a package for known vulnerabilities, unsafe input and leaked secrets. Their logic
lives in the scripts in `security/`. A workflow only runs a script and shows its report in the summary
of the job.

`reusable-ci.yaml` runs them. A package can also call them in a workflow of its own:

```yaml
name: Security

on:
    workflow_dispatch:
    push:
        branches:
            - "[0-9]+.[0-9]+"
            - "[0-9]+.x"

jobs:
    composer-vulnerabilities:
        uses: open-dxp/workflows-collection-public/.github/workflows/reusable-composer-vulnerabilities.yaml@main
        secrets:
            COMPOSER_AUTH: ${{ secrets.COMPOSER_AUTH }}

    taint-analysis:
        uses: open-dxp/workflows-collection-public/.github/workflows/reusable-taint-analysis.yaml@main
        permissions:
            contents: read
            security-events: write
        secrets:
            COMPOSER_AUTH: ${{ secrets.COMPOSER_AUTH }}

    secret-scan:
        uses: open-dxp/workflows-collection-public/.github/workflows/reusable-secret-scan.yaml@main
```

A run started by hand searches the whole history for secrets. A pull request or a push searches only
its own commits.

`reusable-composer-vulnerabilities.yaml` audits a project as its `composer.lock` installs it, and a
package with the highest versions its constraints allow. An advisory or an audit that cannot run fails
the job. A pull request is only audited when it changes `composer.json`. A scheduled run and a run
started by hand also post the report to Microsoft Teams, when `TEAMS_COMPOSER_VULNERABILITY_URI` is set.

`reusable-taint-analysis.yaml` runs Psalm 7 with `psalm/plugin-symfony`,
`weirdan/doctrine-psalm-plugin` and [open-dxp/psalm-plugin](https://github.com/open-dxp/psalm-plugin),
which adds the sinks of OpenDXP. OpenDXP itself is analysed without the last one. Only taint
findings count. The other issues of Psalm are type checks, which phpstan covers. The package needs no
Psalm configuration and no Psalm in its `composer.json`. `sources` names the directories to analyse,
`src` by default. A package with known false positives keeps them in a Psalm baseline named
`psalm-taint-baseline.xml` in its root. Only findings outside the baseline count then.

In a private repository a finding fails the job. The summary of the job lists the findings, and the
run keeps them in SARIF. Anyone can read the runs of a public repository, so its findings go only to
code scanning, where people with write access see them. They do not fail the job.

`reusable-sbom.yaml` takes the tag of a release, creates an SBOM of the package with
`cyclonedx/cyclonedx-php-composer` and attaches it to the release:

```yaml
on:
    release:
        types: [ published ]
    workflow_dispatch:
        inputs:
            tag:
                required: true
                type: string

jobs:
    sbom:
        uses: open-dxp/workflows-collection-public/.github/workflows/reusable-sbom.yaml@main
        permissions:
            contents: write
        with:
            tag: ${{ github.event.release.tag_name || inputs.tag }}
        secrets:
            COMPOSER_AUTH: ${{ secrets.COMPOSER_AUTH }}
```

The package has no lock file. The SBOM lists what a fresh install of the release resolves to.

A package that needs a composer repository besides packagist passes it to all three as
`composer_repository`, the same way as to the tests. Credentials for it go in `COMPOSER_AUTH`.

## Packages from a private registry

Packagist is the only repository the application knows. 
Name another one when your package or its dependencies come from somewhere else:

```yaml
with:
    composer_repository: 'https://my-registry.com'
```

Credentials for it go in `COMPOSER_AUTH`, as a secret.

## Packages the tests need but the package must not require

What a package lists under `extra.opendxp-test.optional` is installed like any other dependency.
What that key is for is in [open-dxp/test-foundation](https://github.com/open-dxp/test-foundation).

## Deprecated

Do not use these for a new package.

|                                               | Use instead                     |
|-----------------------------------------------|---------------------------------|
| `reusable-codeception-tests-centralized.yaml` | `reusable-pest-tests.yaml`      |
| `reusable-static-analysis-centralized.yaml`   | `reusable-static-analysis.yaml` |
| `reusable-security-analysis.yaml`             | `reusable-taint-analysis.yaml`  |
| `reusable-composer-checks.yaml`               | `reusable-composer-vulnerabilities.yaml` |
| `codeception-tests-configuration/`            | `tests-configuration/`          |
