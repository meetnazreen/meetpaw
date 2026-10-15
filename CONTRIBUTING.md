# Contributing to MeetPaw

Thanks for your interest in MeetPaw. Contributions of all kinds are welcome:
bug reports, feature ideas, docs, and code.

## Ground rules

- Be respectful. This project follows a [Code of Conduct](CODE_OF_CONDUCT.md).
- Keep changes focused. One topic per pull request.
- MeetPaw is deliberately **dependency-free** (native SwiftUI + AppKit). Please
  don't add third-party packages without discussing it in an issue first.

## Getting set up

```sh
git clone https://github.com/meetnazreen/meetpaw.git
cd meetpaw
swift build                    # debug build
swift run MeetPaw --selftest   # runs the self-checks
./build.sh                     # produce the signed MeetPaw.app
open MeetPaw.app
```

You'll need your own OAuth credentials to exercise sign-in. See the
[README](README.md#setup) for how to set up Google, Zoom, and Microsoft.

## Making a change

1. **Open an issue first** for anything non-trivial, so we can agree on the
   approach before you spend time on it.
2. Create a branch: `git checkout -b my-change`.
3. Match the surrounding code style (naming, spacing, comment density). MeetPaw
   favors small, readable code over cleverness.
4. Keep non-trivial logic covered by the `--selftest` checks where it makes
   sense.
5. Make sure `swift build` and `swift run MeetPaw --selftest` both pass.
6. Write a clear commit message describing *why*, not just *what*.

## Pull requests

- Describe the change and link the related issue.
- Include before/after screenshots or a short clip for UI changes.
- Keep the diff as small as the change allows.

## Reporting bugs & requesting features

Use the issue templates. For bugs, include your macOS version, the provider
involved, and steps to reproduce. For security issues, **do not** open a public
issue — see [SECURITY.md](SECURITY.md).
