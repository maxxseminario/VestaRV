#!/bin/sh
# VestaRV: fetch bazelisk into tools/bin/bazel for this checkout.
# Bazelisk is a static go binary; it reads .bazelversion at the repo root and
# downloads/runs that exact bazel release, so this is the only bootstrap step.
# If the GitHub download fails, an installed bazelisk (e.g. the one on GitHub's
# ubuntu runner images) is used instead.
set -eu
dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$dir/bin"
url=${BAZELISK_URL:-https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64}
if curl -fsSL --retry 5 --retry-delay 15 -o "$dir/bin/bazel.tmp" "$url"; then
    mv "$dir/bin/bazel.tmp" "$dir/bin/bazel"
elif have="$(command -v bazelisk)"; then
    echo "get_bazel.sh: download failed; using installed $have" >&2
    rm -f "$dir/bin/bazel.tmp"
    ln -sf "$have" "$dir/bin/bazel"
else
    rm -f "$dir/bin/bazel.tmp"
    echo "get_bazel.sh: download failed and no bazelisk on PATH" >&2
    exit 1
fi
[ -L "$dir/bin/bazel" ] || chmod +x "$dir/bin/bazel"
"$dir/bin/bazel" version
