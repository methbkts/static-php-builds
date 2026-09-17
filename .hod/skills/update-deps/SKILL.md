---
name: update-deps
description: "Raise every dependency of this project: the pinned tools in `config/build.env` and `.github/workflows/ci.yml`, the build sources in `config/sources.lock`, the PHP branches with their release manager keys, and the Dependabot pull requests. Use when the user asks to update, upgrade or bump the dependencies, the pins, the lock or the PHP branches of this project."
disable-model-invocation: true
---

# Update Deps

Raise every dependency of this project to its newest version. Start no workflow, no build and no release. Write no commit. Leave each change in the working tree.

## 1. Read the project

Read `.hod/PROJECT.md`. It names each file that holds a pin and the command that updates it.

Run `git status --short`. Stop when a file carries a change, and ask the user to commit that change first.

Run `gh repo view --json nameWithOwner --jq .nameWithOwner` and use the answer as `<repo>` in each command below.

## 2. Report the Dependabot pull requests

Run `gh pr list --repo <repo> --author app/dependabot --json number,title,url`. Dependabot raises the GitHub Actions in `.github/workflows/*.yml` and `zizmor` in `.github/zizmor-requirements.txt`. Merge no pull request. Report each one with its number and its title in section 6, and ask the user to merge them.

## 3. Raise the pinned tools

Run `scripts/update-pins.sh`. It raises static-php-cli, Composer, Xdebug, actionlint and the eight mirrored libraries in `SPC_SOURCE_MIRRORS`, and it writes each new version and SHA-256 into `config/build.env`, `.github/workflows/ci.yml` and `config/sources.lock`. It compares the checksum of each download with a second origin and stops when the two differ. Report that stop to the user and continue with the next section.

Run `git diff --stat` and keep the list of the changed files for section 6.

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

4. Tell the user that `config/extensions-excluded.txt` must name each extension that does not build on the new branch yet.

Remove no branch. The user decides when a branch that php.net stopped supporting leaves the file.

## 5. What needs no update

The PHP patch version resolves from php.net on each run, by design. The runner images and the apt packages that `spc doctor` installs come from GitHub, and no file of this project pins them. Say nothing about them in the report.

## 6. Report

Give four lists: each Dependabot pull request that waits for a merge, each pinned tool that you raised with the version before and the version after, each line of `config/sources.lock` that changed with the version before and the version after, and each PHP branch that you added with its fingerprints. When a list above names one change, tell the user that the Release workflow checks the other lines of `config/sources.lock`, and start no run. Write no commit.
