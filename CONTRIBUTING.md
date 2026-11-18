# Contributing a package

A package is a directory `packages/<name>/` with a `build.sh` written in the
[termux-packages](https://github.com/termux/termux-packages/wiki/Creating-new-package) format.
Patches and `*.subpackage.sh` files live in the same directory.

## Rules

- The name uses lowercase letters, digits, `+`, `-` and `.`, and must not exist in termux-packages.
- `build.sh` defines `TERMUX_PKG_HOMEPAGE`, `TERMUX_PKG_DESCRIPTION`, `TERMUX_PKG_LICENSE`,
  `TERMUX_PKG_MAINTAINER` (your GitHub user, starting with `@`) and `TERMUX_PKG_VERSION`.
- Sources come from `https://` (or `git+https://`) and have a `TERMUX_PKG_SHA256`.
  Packages without sources set `TERMUX_PKG_SKIP_SRC_EXTRACT=true`.
- The license must allow redistribution.
- No prebuilt binaries and no file larger than 1 MB.
- Never write `/data/data/com.termux`; use `$TERMUX_PREFIX`.

## Workflow

1. Open a pull request. The **Validate packages** check runs static checks only; it never executes
   your recipe.
2. A maintainer reviews the recipe. Everything in it runs during the build, and package scripts run
   on users' devices, so the review is the real security boundary.
3. After the merge the package is built for TermOne to TermFour and published.

## Testing locally

On a Linux machine with Docker:

    bash scripts/validate-packages.sh <name>
    bash scripts/build-package.sh app.term.one aarch64 <name>

Builds on a phone are not supported.