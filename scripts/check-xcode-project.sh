#!/bin/sh
# The "Check the project is current" build phase of both targets (ios/project.yml). The Xcode
# project is generated from ios/project.yml and is not in git, so one generated before a pull can
# pin an older DesignKit or miss files that came since (CompleteStepIntent in ios/Shared: "Cannot
# find 'CompleteStepIntent' in scope", 2026-11-24). This stops the build with what to run instead.
# The git hooks keep the project current (scripts/setup.sh, once).

cd "$SRCROOT" 2>/dev/null || exit 0
project="$PROJECT_FILE_PATH/project.pbxproj"
[ -f "$project" ] || exit 0
fix="Run: cd ios && xcodegen generate (or scripts/setup.sh once, and git regenerates it after every pull)."

pin=$(sed -n 's/^ *exactVersion: *"\([^"]*\)".*/\1/p' project.yml | head -n 1)
if [ -n "$pin" ] && ! grep -Eq "version = \"?$pin\"?;" "$project"; then
    echo "error: ios/project.yml pins DesignKit $pin, but this Xcode project was generated before that. $fix"
    exit 1
fi

# Swift files the project does not list (a script sandbox that hides the folders finds none).
missing=$(find Platina Shared PlatinaWidgets -name '*.swift' 2>/dev/null | while read -r file; do
    grep -qF "$(basename "$file")" "$project" || echo "$file"
done | head -n 3 | tr '\n' ' ' | sed 's/ $//')
if [ -n "$missing" ]; then
    echo "error: this Xcode project was generated before these files came: ${missing}. $fix"
    exit 1
fi
exit 0
