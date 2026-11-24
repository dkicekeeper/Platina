#!/bin/sh
# Sets up a Mac for Platina, once: XcodeGen, the git hooks that regenerate the Xcode project
# after every pull, merge, rebase and branch switch (.githooks, scripts/xcodegen-if-needed.sh),
# and the project itself.
#   scripts/setup.sh
set -e
cd "$(git rev-parse --show-toplevel)"

if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        brew install xcodegen
    else
        echo "XcodeGen is needed: install Homebrew (https://brew.sh), then run this again."
        exit 1
    fi
fi

git config core.hooksPath .githooks
(cd ios && xcodegen generate)

echo "Done: open ios/Platina.xcodeproj. From now on the project regenerates itself after git pull."
echo "If Xcode still shows an old DesignKit: File > Packages > Reset Package Caches."
