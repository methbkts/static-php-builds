# Static PHP Builds

Precompiled PHP for [mise](https://mise.jdx.dev), so installing PHP is a download instead of a compile.

Every release includes:

- PHP CLI with the extensions Laravel needs (see [`config/extensions.txt`](config/extensions.txt))
- Composer
- Xdebug

Platforms: Linux x86_64, Linux aarch64 (both glibc 2.17 or newer), and macOS on Apple Silicon.

## Usage

Point mise's `php` at this repository, then use PHP as usual:

```sh
mise config set -f ~/.config/mise/config.toml tool_alias.php github:nunomaduro/static-php-builds

mise use --global php@8.5
php -v
composer --version
```

Projects that pin a version in `mise.toml` (for example `php = "8.4"`) use these builds too.

Xdebug is loaded but only starts debugging on a trigger. Set `XDEBUG_MODE=off` to skip it entirely.

## Verifying a download

Every release file has a GitHub build attestation, which mise checks automatically. To check one yourself:

```sh
gh attestation verify php-8.5.10-linux-x86_64.tar.gz --repo nunomaduro/static-php-builds
```

## How releases are built

A scheduled workflow runs daily. For each branch in [`config/php-branches.txt`](config/php-branches.txt) it looks up the newest release on php.net, and builds it if it has not been released here yet:

1. The PHP source is downloaded from php.net and checked against php.net's published SHA-256.
2. PHP is built with a pinned, checksum-verified [static-php-cli](https://github.com/crazywhalecc/static-php-cli) on GitHub-hosted runners.
3. Each build is unpacked and smoke tested: version, extensions, Xdebug, Composer, SQLite, intl, HTTPS and the glibc baseline.
4. The files get a build attestation and are published as an immutable GitHub release named after the PHP version.

All pinned versions and checksums live in [`config/build.env`](config/build.env).

To build a version manually, run the **Release** workflow with a version. Leave **publish** off to only build and test.

## Release layout

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
