#!/bin/sh
# VestaRV: provide bazelisk as tools/bin/bazel for this checkout.
# Bazelisk is a static go binary; it reads .bazelversion at the repo root and
# downloads/runs that exact bazel release, so this is the only bootstrap step.
# An installed bazelisk (e.g. the one on GitHub's ubuntu runner images) is
# used as-is; otherwise the latest release is downloaded from GitHub.
# Set BAZELISK_URL to force a download from a specific URL.
set -eu
dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$dir/bin"
have="$(command -v bazelisk 2>/dev/null || true)"
if [ -n "$have" ] && [ -z "${BAZELISK_URL:-}" ]; then
    echo "get_bazel.sh: using installed $have" >&2
    ln -sf "$have" "$dir/bin/bazel"
else
    url=${BAZELISK_URL:-https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64}
    if curl -fsSL --retry 5 --retry-delay 15 -o "$dir/bin/bazel.tmp" "$url"; then
        rm -f "$dir/bin/bazel"
        mv "$dir/bin/bazel.tmp" "$dir/bin/bazel"
        chmod +x "$dir/bin/bazel"
    else
        rm -f "$dir/bin/bazel.tmp"
        echo "get_bazel.sh: download of $url failed" >&2
        exit 1
    fi
fi
"$dir/bin/bazel" version
