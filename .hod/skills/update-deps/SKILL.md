---
name: update-deps
description: "Raise every dependency of this project: the pinned tools in `config/build.env` and `.github/workflows/ci.yml`, the build sources in `config/sources.lock`, the PHP branches with their release manager keys, and the Dependabot pull requests. Use when the user asks to update, upgrade or bump the dependencies, the pins, the lock or the PHP branches of this project."
disable-model-invocation: true
---

# Update Deps

Raise every dependency of this project to its newest version, then prove the result with one run of the Release workflow. Write no commit. Leave each change in the working tree.

## 1. Read the project

Read `.hod/PROJECT.md`. It names each file that holds a pin and the command that updates it.

Run `git status --short`. Stop when a file carries a change, and ask the user to commit that change first.

Run `gh repo view --json nameWithOwner --jq .nameWithOwner` and use the answer as `<repo>` in each command below.

## 2. Report the Dependabot pull requests

Run `gh pr list --repo <repo> --author app/dependabot --json number,title,url`. Dependabot raises the GitHub Actions in `.github/workflows/*.yml` and `zizmor` in `.github/zizmor-requirements.txt`. Merge no pull request. Report each one with its number and its title in section 7, and ask the user to merge them.

## 3. Raise the pinned tools

Run `scripts/update-pins.sh`. It raises static-php-cli, Composer, Xdebug, actionlint and the eight mirrored libraries in `SPC_SOURCE_MIRRORS`, and it writes each new version and SHA-256 into `config/build.env`, `.github/workflows/ci.yml` and `config/sources.lock`. It compares the checksum of each download with a second origin and stops when the two differ. Report that stop to the user and continue with the next section.

Run `git diff --stat` and keep the list of the changed files for section 7.

## 4. Add a new PHP branch

Run `curl -fsSL 'https://www.php.net/releases/active.php' | jq -r '.[] | keys[]'`. It lists each PHP branch that php.net supports. Compare the list with the uncommented lines of `config/php-branches.txt`.

For each branch that php.net lists and the file lacks, do four steps.

1. Add the branch on its own line in `config/php-branches.txt`, in version order.
2. Run `curl -fsSL https://www.php.net/gpg-keys.php` and read the fingerprints under the heading of that branch. Add one line per fingerprint to `config/php-release-keys.txt` in the form `<branch> <fingerprint>` with no spaces inside the fingerprint, and keep the file sorted.
3. Run these commands to add the public keys to `config/php-release-keys.asc`, with the fingerprints of step 2 in place of `<fingerprints>`:

```sh
home=$(mktemp -d) && chmod 0700 "$home"
curl -fsSL -o "$home/php-keyring.gpg" https://www.php.net/distributions/php-keyring.gpg
gpg --homedir "$home" --batch --quiet --import "$home/php-keyring.gpg" config/php-release-keys.asc
gpg --homedir "$home" --batch --armor --export --export-options export-minimal $(awk '{print $2}' config/php-release-keys.txt | sort -u) > config/php-release-keys.asc
rm -rf "$home"
```

4. Check that `config/extensions-excluded.txt` names each extension that does not build on the new branch yet. The build of section 5 shows a missing one.

Remove no branch. The user decides when a branch that php.net stopped supporting leaves the file.

## 5. Refresh the source lock and prove the build

The Release workflow downloads every build source, compares each one with `config/sources.lock`, and stops before the compile when one differs. The cached sources hide an upstream change, thus delete the caches first.

Run these commands:

```sh
gh cache delete --all --repo <repo>
gh workflow run release.yml --repo <repo> -f version=all
sleep 30
gh run watch --repo <repo> --exit-status "$(gh run list --repo <repo> --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

When the run passes, the lock is current and every branch builds with the new dependencies. Continue with section 7.

When a job fails at the step `Build` with the message `these sources are not in config/sources.lock`, download the drift:

```sh
gh run download <run-id> --repo <repo> --pattern 'build-logs-*' --dir "$(mktemp -d)"
```

Read `sources.drift` from one `linux-x86_64` artifact and from one `linux-aarch64` artifact. The two lists agree, except the lines for `zig` and `pkg-config`, which differ per platform. Each line has the form `sha256:<hash>  <file>` or `git:<commit>  <name>`. For each line, find the line in `config/sources.lock` with the same source name, and show the user the old line and the new line. Name the upstream version change that the file name shows, such as `openssl-3.6.4.tar.gz` to `openssl-3.7.0.tar.gz`. For a `git:` line, give the compare URL of the repository between the two commits when the repository is on GitHub, such as `https://github.com/libjxl/libjxl/compare/<old>...<new>`.

Ask the user to accept the new lines. Wait for the answer. After the user accepts, replace each old line with its new line, keep the file sorted by the source name with `sort -k2,2 -o config/sources.lock config/sources.lock`, and run the commands at the top of this section again. Repeat until the run passes.

When a job fails at a different step, the new dependency broke the build. Read the last lines of the job log with `gh run view <run-id> --repo <repo> --log-failed | tail -n 150`. Report the failing source and the error to the user, and ask the user to keep or to return the change. Return a change with `git checkout -- <file>`.

## 6. What needs no update

The PHP patch version resolves from php.net on each run, by design. The runner images and the apt packages that `spc doctor` installs come from GitHub, and no file of this project pins them. Say nothing about them in the report, except when a build fails because of them.

## 7. Report

Give four lists: each Dependabot pull request that waits for a merge, each pinned tool that you raised with the version before and the version after, each line of `config/sources.lock` that changed with the version before and the version after, and each PHP branch that you added with its fingerprints. Give the URL of the Release workflow run that passed, in one sentence of its own, whenever a list above names one change. Write no commit.
