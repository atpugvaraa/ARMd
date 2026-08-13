#!/usr/bin/env bash
#
# Cut a signed, notarised ARMd release and publish it to the Homebrew tap.
#
#   ./Scripts/release.sh 1.0.0
#
# Everything a student needs happens here: the app is signed with a Developer ID
# certificate and notarised by Apple, so it opens on their Mac with no warning
# and no right-click ritual. Nothing in this script asks the *student* to do
# anything — that is the whole point.
#
# One-time setup on this machine (the script checks all of it before building):
#
#   1. A Developer ID Application certificate in the login keychain.
#      Xcode -> Settings -> Accounts -> team -> Manage Certificates -> + .
#   2. Notarisation credentials stored under the profile name "ARMd":
#        xcrun notarytool store-credentials ARMd \
#          --apple-id <email> --team-id 3YK32DPS3W --password <app-specific-password>
#      The app-specific password comes from appleid.apple.com, not your Apple ID
#      password.
#   3. A GitHub remote named origin, and `gh auth login` completed.

set -euo pipefail

readonly NOTARY_PROFILE="ARMd"
readonly TAP_REPO="atpugvaraa/homebrew-atpugvaraa"
readonly APP_REPO="atpugvaraa/ARMd"

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIST="$ROOT/dist"

die() { printf '\n\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- arguments

[ $# -eq 1 ] || die "usage: $(basename "$0") <version>   e.g. $(basename "$0") 1.0.0"
readonly VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "version must be three numbers separated by dots, e.g. 1.0.0 — got '$VERSION'"

cd "$ROOT"

# ---------------------------------------------------------------- preflight
#
# All of it up front. Each of these has failed for someone at some point, and
# every one of them is cheaper to discover now than after a five-minute archive.

step "Preflight"

[ -z "$(git status --porcelain)" ] \
    || die "working tree is dirty. A release must be reproducible from its tag —
       commit or stash first, then re-run."

git rev-parse "v$VERSION" >/dev/null 2>&1 \
    && die "tag v$VERSION already exists. Pick a new version, or delete the tag with:
       git tag -d v$VERSION && git push origin :refs/tags/v$VERSION"

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || die "no Developer ID Application certificate in the keychain.
       Xcode -> Settings -> Accounts -> select your team -> Manage Certificates ->
       + -> Developer ID Application. An Apple Development or Apple Distribution
       certificate will not work: only Developer ID can be notarised."

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notarisation credentials '$NOTARY_PROFILE' are not stored. Run:
       xcrun notarytool store-credentials $NOTARY_PROFILE \\
         --apple-id <your-apple-id> --team-id 3YK32DPS3W --password <app-specific-password>
       Generate the app-specific password at appleid.apple.com -> Sign-In and
       Security -> App-Specific Passwords. Your normal Apple ID password is rejected."

git remote get-url origin >/dev/null 2>&1 \
    || die "no git remote named origin. Create the repository with:
       gh repo create $APP_REPO --public --source . --remote origin"

gh auth status >/dev/null 2>&1 \
    || die "gh is not authenticated. Run: gh auth login"

xcodebuild -project ARMd.xcodeproj -list >/dev/null 2>&1 \
    || die "xcodebuild cannot read ARMd.xcodeproj."

echo "  all checks passed"

# ---------------------------------------------------------------- version

step "Setting version to $VERSION"

# Written straight into the project file rather than with `agvtool`. This target
# uses GENERATE_INFOPLIST_FILE = YES, so there is no Info.plist on disk, and
# agvtool resolves the setting's literal value as a path — it fails with
# `Cannot find "ARMd.xcodeproj/../YES"`. sed has no opinion about Info.plists.
readonly PBXPROJ="$ROOT/ARMd.xcodeproj/project.pbxproj"
readonly BUILD_NUMBER="$(( $(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' "$PBXPROJ" | head -1) + 1 ))"

sed -i '' \
    -e "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $VERSION;/g" \
    -e "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" \
    "$PBXPROJ"

grep -q "MARKETING_VERSION = $VERSION;" "$PBXPROJ" \
    || die "failed to write MARKETING_VERSION into project.pbxproj"

echo "  marketing version $VERSION, build $BUILD_NUMBER"

# ---------------------------------------------------------------- build

rm -rf "$DIST"
mkdir -p "$DIST"

step "Archiving"
xcodebuild archive \
    -project ARMd.xcodeproj \
    -scheme ARMd \
    -configuration Release \
    -archivePath "$DIST/ARMd.xcarchive" \
    -quiet

step "Exporting a Developer ID-signed app"
xcodebuild -exportArchive \
    -archivePath "$DIST/ARMd.xcarchive" \
    -exportOptionsPlist "$ROOT/Scripts/ExportOptions.plist" \
    -exportPath "$DIST/export" \
    -quiet

readonly APP="$DIST/export/ARMd.app"
[ -d "$APP" ] || die "export produced no ARMd.app in $DIST/export"

# ---------------------------------------------------------------- notarise

step "Notarising (this is the slow part — usually 1-5 minutes)"

# ditto, not zip: only ditto preserves the symlinks and extended attributes
# inside a .app bundle. A plain `zip` produces an archive Apple rejects.
ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"

notary_output="$(xcrun notarytool submit "$DIST/notarize.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
echo "$notary_output"

# --wait exits 0 even when Apple rejects the submission, so the status line is
# the only trustworthy signal.
grep -q "status: Accepted" <<<"$notary_output" || {
    submission_id="$(grep -m1 -o '[0-9a-f-]\{36\}' <<<"$notary_output" || true)"
    die "notarisation was not accepted. For the reason, run:
       xcrun notarytool log ${submission_id:-<submission-id>} --keychain-profile $NOTARY_PROFILE"
}

step "Stapling"
xcrun stapler staple "$APP"

# Re-zip AFTER stapling. Stapling writes the notarisation ticket into the bundle,
# so the archive made above is stale. Shipping that one means every user's Mac
# has to ask Apple's servers at launch instead of reading the ticket locally —
# slower, and it fails outright offline.
readonly ZIP="$DIST/ARMd-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Verifying the signed app"
spctl -a -vvv -t install "$APP"
xcrun stapler validate "$APP"

readonly SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "  sha256 $SHA"

# ---------------------------------------------------------------- publish

step "Tagging and pushing"
git add -A
git diff --cached --quiet || git commit -m "chore: release $VERSION"
git tag "v$VERSION"
git push origin HEAD --tags

step "Creating the GitHub release"
gh release create "v$VERSION" "$ZIP" \
    --repo "$APP_REPO" \
    --title "ARMd $VERSION" \
    --generate-notes

step "Updating the Homebrew cask"
rm -rf "$DIST/tap"
gh repo clone "$TAP_REPO" "$DIST/tap" -- --quiet
mkdir -p "$DIST/tap/Casks"

cat > "$DIST/tap/Casks/armd.rb" <<CASK
cask "armd" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$APP_REPO/releases/download/v#{version}/ARMd-#{version}.zip"
  name "ARMd"
  desc "Write and run Keil-style ARM7 assembly on Apple Silicon"
  homepage "https://github.com/$APP_REPO"

  # Bare symbol, not ">= :sequoia": the string-comparison form is deprecated and
  # Homebrew warns on every install. A bare symbol already means "at least".
  depends_on macos: :sequoia

  app "ARMd.app"

  zap trash: "~/Library/Preferences/com.aaravgupta.ARMd.plist"
end
CASK

git -C "$DIST/tap" add Casks/armd.rb
git -C "$DIST/tap" commit -m "armd $VERSION"
git -C "$DIST/tap" push

printf '\n\033[32mReleased ARMd %s\033[0m\n\n' "$VERSION"
echo "Install it with:"
echo "  brew install --cask atpugvaraa/atpugvaraa/armd"
echo
echo "Already installed? Upgrade with:"
echo "  brew upgrade --cask armd"
