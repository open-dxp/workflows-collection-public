# OpenDXP workflows

Reusable GitHub workflows and actions for OpenDXP packages. A package keeps its tests, its rule
files and its triggers, and calls a workflow from here to run them.

Everything here is called with `uses:`. Nothing runs on this repository itself.

## What is here

| Workflow                                  |                                                                |
|-------------------------------------------|----------------------------------------------------------------|
| `reusable-pest-tests.yaml`                | a package's Pest suite, in an OpenDXP application built for it |
| `reusable-static-analysis.yaml`           | phpstan over a package, against the same application           |
| `reusable-php-cs-fixer.yaml`              | php-cs-fixer, with the fixes committed back                    |
| `reusable-composer-checks.yaml`           | `composer audit` and `composer outdated`                       |
| `reusable-composer-vulnerabilities.yaml`  | the installed packages against the advisory database           |
| `reusable-cla-check.yaml`                 | a contributor has signed the CLA                               |
| `stale.yml`                               | marks issues nobody has answered for 20 days                   |

| Action                      |                                               |
|-----------------------------|-----------------------------------------------|
| `build-opendxp-application` | an OpenDXP application with the package in it |
| `test-matrix`               | a job matrix out of a matrix configuration    |

| Configuration                             |                                                           |
|-------------------------------------------|-----------------------------------------------------------|
| `codeception-tests-configuration/`        | the matrix for test runs                                  |
| `phpstan-configuration/`                  | the matrix for analysis runs                              |
| `php-cs-fixer-configuration/`             | the shared php-cs-fixer rule sets                         |
| `config/vulnerabilities-ignore-list.json` | accepted advisories, looked up by the `ignore-list` input |

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

## Running the tests

`.github/workflows/pest.yaml` in your package:

```yaml
name: Pest tests

on:
    workflow_dispatch:
    push:
        branches:
            - "[0-9]+.[0-9]+"
            - "[0-9]+.x"
    pull_request:
        types: [ opened, synchronize, reopened ]

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
                    configuration: codeception-tests-configuration

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

A `phpunit.xml.dist`, a `tests/TestKernel.php` and `open-dxp/test-foundation` under `require-dev`.
How to write any of it is in [open-dxp/test-foundation](https://github.com/open-dxp/test-foundation).

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

phpstan reads the compiled container to know the services, so this builds and installs the same
application the tests use. It takes longer than a plain phpstan run and it sees what the services
actually are. Your `phpstan.neon` has to point at the container the test kernel writes, which
[open-dxp/test-foundation](https://github.com/open-dxp/test-foundation) documents.

## The matrix

`test-matrix` reads the php versions your `composer.json` supports and picks the matching entry
from a configuration in this repository:

```
codeception-tests-configuration/matrix-config.json     for test runs
phpstan-configuration/matrix-config.json               for the analysis
```

It fails when nothing matches. An empty matrix runs nothing and reports success,
which reads like a suite that passed.

## Options

`reusable-pest-tests.yaml` and `reusable-static-analysis.yaml`:

|                                |                                                            |
|--------------------------------|------------------------------------------------------------|
| `php_version`                  | required                                                   |
| `dependencies`                 | `locked`, `highest` or `lowest`, handed to composer        |
| `database`                     | `mysql:8.4` by default, an image name                      |
| `server_version`               | what doctrine is told the server is, paired with the image |
| `experimental`                 | a failure does not fail the run                            |
| `opendxp_version`              | a version of `open-dxp/opendxp` to force                   |
| `composer_repository`          | a composer repository besides packagist, as a url          |
| `execute_post_checkout_action` | run `.github/actions/post-checkout-action` of your package |

`reusable-pest-tests.yaml` also:

|                                   |                                                      |
|-----------------------------------|------------------------------------------------------|
| `enable_browser`                  | run the tests in the `browser` group, off by default |
| `pest_options`                    | passed to Pest as it stands                          |
| `enable_redis_service`            | a redis container beside the application             |
| `enable_opensearch_service`       | an opensearch container beside the application       |
| `install_ghostscript_and_pdfinfo` | for suites that read pdfs                            |

The ports and versions of those two containers have defaults that match what the tests read:
`redis_dsn`, `opendxp_open_search_host` and `opendxp_opensearch_version`.
Change them only when something in the suite expects something else.

`reusable-static-analysis.yaml` also:

|                     |                                                     |
|---------------------|-----------------------------------------------------|
| `generate_baseline` | on a failure, attach a baseline of everything found |

A browser costs a chromium download and seconds per test, so `enable_browser` is off unless you
ask for it. It then runs the tests marked `->group('browser')` as well.

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
A global configuration takes the files to fix from a `.php-cs-fixer-finder.dist.php` in the package, 
so that part stays with the package. Without `use_global_config` the workflow uses `config_file` as it is.

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
