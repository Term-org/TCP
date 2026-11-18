# TCP (Term Community Packages)

Community packages for TermOne, TermTwo, TermThree and TermFour. Recipes use the termux-packages
format and are built with the same pipeline as the main repository (TP), then published as a
separate signed apt repository.

## Using it

    tn community enable
    tn update
    tn install hello-term

## Setup (maintainers)

1. Run `bash scripts/make-signing-key.sh`, commit `keys/term-community.gpg`, store `private-key.asc`
   in the secret `TERM_COMMUNITY_GPG_PRIVATE_KEY` and delete the file.
2. In **Settings > Pages** set the source to **GitHub Actions**.
3. Protect `main`: require a pull request review and the **Validate recipes** check.

See `CONTRIBUTING.md` to add a package.