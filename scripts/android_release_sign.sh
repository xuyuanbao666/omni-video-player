#!/usr/bin/env bash
# Sign only the release APK outputs. Never persist key material in the workspace/artifacts.
set -euo pipefail
umask 077
: "${OMNI_ANDROID_KEYSTORE_B64:?Configure the persistent release keystore secret}"
: "${OMNI_ANDROID_KEYSTORE_PASSWORD:?Configure the persistent release password secret}"
: "${OMNI_ANDROID_CERT_SHA256:?Configure the expected release certificate fingerprint}"
expected="$(printf '%s' "$OMNI_ANDROID_CERT_SHA256" | tr '[:upper:]' '[:lower:]' | tr -d ':[:space:]')"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]]
tools="$ANDROID_HOME/build-tools/36.0.0"
if [[ ! -x "$tools/apksigner" ]]; then sdkmanager 'build-tools;36.0.0'; fi
keydir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/omni-sign.XXXXXX")"
trap 'rm -rf -- "$keydir"' EXIT
printf '%s' "$OMNI_ANDROID_KEYSTORE_B64" | base64 --decode > "$keydir/release.p12"
unset OMNI_ANDROID_KEYSTORE_B64
sign() {
    local input="$1" output="$2" cert
    # flutter produces aligned APKs; apksigner replaces their temporary test signature.
    "$tools/zipalign" -c -v 4 "$input" >/dev/null
    "$tools/apksigner" sign --ks "$keydir/release.p12" --ks-type PKCS12 --ks-key-alias omni-release \
      --ks-pass env:OMNI_ANDROID_KEYSTORE_PASSWORD --key-pass env:OMNI_ANDROID_KEYSTORE_PASSWORD \
      --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
      --out "$output" "$input"
    cert="$("$tools/apksigner" verify --verbose --print-certs "$output" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
    test "$cert" = "$expected"
    "$tools/zipalign" -c -v 4 "$output" >/dev/null
}
# Pin all four release APK certificates and never upload the temporary test APKs.
for apk in dist/*-test.apk; do
    test -f "$apk"
    sign "$apk" "${apk%-test.apk}-release.apk"
    rm -- "$apk"
done
test "$(find dist -maxdepth 1 -name '*-release.apk' | wc -l)" -eq 4
# Download actual prior stable release. First transition is explicitly a
# re-signed historical APK used ONLY as an upgrade-test fixture, never distributed.
mkdir -p upgrade-fixture
tag="$(gh api "repos/$GITHUB_REPOSITORY/releases/latest" --jq .tag_name)"
if [[ "$tag" == v0.4.1 ]]; then
    gh release download "$tag" --repo "$GITHUB_REPOSITORY" --dir "$keydir" --pattern 'OmniPlayer-Android-universal-test.apk'
    sign "$keydir/OmniPlayer-Android-universal-test.apk" upgrade-fixture/previous.apk
    echo "First release-key migration: upgrade fixture is re-signed v0.4.1, not the original public APK."
else
    gh release download "$tag" --repo "$GITHUB_REPOSITORY" --dir upgrade-fixture --pattern 'OmniPlayer-Android-universal-release.apk'
    mv upgrade-fixture/OmniPlayer-Android-universal-release.apk upgrade-fixture/previous.apk
    previous="$("$tools/apksigner" verify --verbose --print-certs upgrade-fixture/previous.apk | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
    test "$previous" = "$expected" || { echo 'Previous public release certificate differs; refusing key rotation.' >&2; exit 1; }
fi
printf '%s\n' "$expected" > dist/ANDROID-CERT-SHA256.txt
