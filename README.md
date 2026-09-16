# Static PHP Builds

- [Introduction](#introduction)
- [Installation](#installation)
- [Xdebug](#xdebug)
- [Verifying a Download](#verifying-a-download)
- [How Releases Are Built](#how-releases-are-built)
  - [Building a Release Manually](#building-a-release-manually)
- [Release Layout](#release-layout)

## Introduction

Static PHP Builds provides precompiled PHP for [mise](https://mise.jdx.dev). With Static PHP Builds, installing PHP is a download instead of a compile — each release includes the PHP CLI with the extensions Laravel needs, Composer, and Xdebug, for Linux x86_64, Linux aarch64, and macOS on Apple Silicon.

The extensions compiled into every build are listed in [`config/extensions.txt`](config/extensions.txt). Linux builds run on any distribution with glibc 2.17 or newer.

## Installation

First, you should point mise's `php` tool at this repository:

```sh
mise config set -f ~/.config/mise/config.toml tool_alias.php github:nunomaduro/static-php-builds
```

Once configured, you may install and use PHP like any other mise tool:

```sh
mise use --global php@8.5

php -v
composer --version
```

Projects that pin a PHP version in their `mise.toml` file use these builds as well:

```toml
[tools]
php = "8.4"
```

## Xdebug

Xdebug is loaded in every build, but it is turned off by default, so PHP runs at full speed. To enable it, set the `XDEBUG_MODE` environment variable to the [modes](https://xdebug.org/docs/all_settings#mode) you need, such as `debug` for step debugging or `coverage` for code coverage. `XDEBUG_MODE` always takes precedence over the bundled configuration, so you never need to edit files inside mise's install directory.

To enable Xdebug for a single command, set the variable inline:

```sh
XDEBUG_MODE=coverage php artisan test --coverage
```

To enable Xdebug for a project, add the variable to the project's `mise.toml` file. mise sets it whenever you are inside that directory:

```toml
[env]
XDEBUG_MODE = "debug"
```

To enable Xdebug everywhere, export the variable from your shell's startup file, such as `~/.bashrc`:

```sh
export XDEBUG_MODE=debug
```

You may enable several modes at once by separating them with commas, such as `XDEBUG_MODE=debug,coverage`.

### Step Debugging

With `XDEBUG_MODE=debug` set, start listening for debug connections in your editor (the "PHP Debug" extension in VS Code, or "Start Listening for PHP Debug Connections" in PhpStorm), then trigger a debugging session:

- **Console commands:** set the `XDEBUG_TRIGGER` environment variable, e.g. `XDEBUG_MODE=debug XDEBUG_TRIGGER=1 php artisan my:command`.
- **Browser requests:** use a browser extension such as Xdebug Helper, which sets the `XDEBUG_SESSION` cookie. When using `php artisan serve`, set `XDEBUG_MODE` before starting the server so the requests it serves inherit it.

If you would like every request and command to connect to your editor without a trigger, also set `XDEBUG_CONFIG="start_with_request=yes"`.

The `bin/php` wrapper adds `etc/php/conf.d` to `PHP_INI_SCAN_DIR`, so any scan directory you configure yourself is still read.

## Verifying a Download

Every release file carries a GitHub build attestation, which mise verifies automatically. If you would like to verify a download yourself, you may use the `gh attestation verify` command:

```sh
gh attestation verify php-8.5.10-linux-x86_64.tar.gz --repo nunomaduro/static-php-builds
```

Each release also includes a `SHA256SUMS` file with the digest of every tarball:

```sh
sha256sum --check --ignore-missing SHA256SUMS
```

## How Releases Are Built

A scheduled workflow runs once a day. For each branch in [`config/php-branches.txt`](config/php-branches.txt), it looks up the newest release on php.net and builds it if this repository does not have a release for it yet:

1. The PHP source is downloaded from php.net and verified against the SHA-256 that php.net publishes.
2. PHP is compiled with a pinned, checksum-verified [static-php-cli](https://github.com/crazywhalecc/static-php-cli) on GitHub-hosted runners.
3. Each build is unpacked and smoke tested: the PHP version, the extensions, Xdebug, Composer, SQLite, intl, HTTPS with the system CA certificates, and the glibc baseline.
4. The files receive a build attestation and are published as a GitHub release named after the PHP version.

All pinned versions and checksums live in [`config/build.env`](config/build.env). The checksum of every other source that went into a build is recorded in the release's `share/sources.txt` file.

Security releases of PHP follow the same schedule, so they are built within a day of being published on php.net.

### Building a Release Manually

You may also run the **Release** workflow yourself, passing a PHP branch or version:

```sh
gh workflow run release.yml -f version=8.5
```

By default, the workflow only builds and smoke tests. If you would like to publish the result as a GitHub release, pass the `publish` input as well:

```sh
gh workflow run release.yml -f version=8.5.10 -f publish=true
```

Leaving `version` empty builds every release that is missing from this repository.

## Release Layout

Each tarball unpacks to the following layout:

```
bin/php                          # runs libexec/php with the bundled ini files
bin/composer
libexec/php                      # the PHP binary
libexec/composer.phar
lib/php/extensions/xdebug.so
etc/php/conf.d/xdebug.ini
share/licenses/                  # licenses of PHP and every bundled library
share/build-info.txt
share/sources.txt                # SHA-256 of every source archive and commit of every git source in the build
```
