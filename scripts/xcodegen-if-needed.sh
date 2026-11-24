#!/bin/sh
# Regenerates ios/Platina.xcodeproj after a pull, a merge, a rebase or a branch switch that
# changed what the project is made of: ios/project.yml (the DesignKit pin, targets, settings), or
# a file added, removed or renamed under ios/ (XcodeGen lists every file; the local package
# ios/Packages needs nothing). The project is not in git, so without this Xcode kept an old
# DesignKit after a pull until someone ran `xcodegen generate` by hand.
#
# Called by the hooks in .githooks, which scripts/setup.sh turns on. Never fails a git command.
#   scripts/xcodegen-if-needed.sh <old commit> [<new commit>]

old="$1"
new="${2:-HEAD}"

[ "$(uname)" = "Darwin" ] || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
[ -f ios/project.yml ] || exit 0

zero=0000000000000000000000000000000000000000
if [ ! -d ios/Platina.xcodeproj ] || [ -z "$old" ] || [ "$old" = "$zero" ] \
    || ! git cat-file -e "$old^{commit}" 2>/dev/null; then
    needed=yes
elif [ -n "$(git diff --name-only "$old" "$new" -- ios/project.yml)" ]; then
    needed=yes
elif [ -n "$(git diff --name-only --diff-filter=ADR "$old" "$new" -- ios ':(exclude)ios/Packages')" ]; then
    needed=yes
else
    needed=no
fi
[ "$needed" = yes ] || exit 0

# Git apps (Xcode, GitHub Desktop) run hooks without the shell's PATH.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Platina: the Xcode project is out of date, and xcodegen is not installed."
    echo "Platina: brew install xcodegen, then: cd ios && xcodegen generate"
    exit 0
fi
echo "Platina: regenerating ios/Platina.xcodeproj (project.yml or the file list changed)"
if ! (cd ios && xcodegen generate --quiet); then
    echo "Platina: xcodegen failed; run it by hand: cd ios && xcodegen generate"
fi
exit 0
