#!/bin/sh
# Fetch bazelisk into tools/bin/bazel for this checkout.
# Bazelisk is a static go binary; it reads .bazelversion at the repo root and
# downloads/runs that exact bazel release, so this is the only bootstrap step.
set -eu
dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$dir/bin"
curl -fsSL -o "$dir/bin/bazel" \
    https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64
chmod +x "$dir/bin/bazel"
"$dir/bin/bazel" version
