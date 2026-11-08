# VestaRV: source the site tool environment. Sourced, never run; POSIX sh or bash.
#
# cdspaths.sh holds site-specific licence servers and install paths, so it is
# untracked: copy cdspaths.example.sh to cdspaths.sh at the repo root and edit it.
# The first file that exists wins:
#   $CDSPATHS                     an explicit file
#   <checkout>/cdspaths.sh        this checkout
#   <main checkout>/cdspaths.sh   when this checkout is a git worktree, which never
#                                 carries the untracked file
# <checkout> is $VESTA_ROOT if set, else the directory above this file (bash only;
# a POSIX sh caller must set VESTA_ROOT).
_vcds_root="${VESTA_ROOT:-}"
if [ -z "$_vcds_root" ] && [ -n "${BASH_SOURCE:-}" ]; then
    _vcds_root="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
fi
_vcds_main=""
_vcds_common="$(cd "$_vcds_root" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"
if [ -n "$_vcds_common" ]; then
    _vcds_main="$(cd "$_vcds_root" && cd "$_vcds_common/.." 2>/dev/null && pwd)"
fi
_vcds_file=""
for _vcds_f in "${CDSPATHS:-}" "${_vcds_root:+$_vcds_root/cdspaths.sh}" "${_vcds_main:+$_vcds_main/cdspaths.sh}"; do
    if [ -n "$_vcds_f" ] && [ -f "$_vcds_f" ]; then _vcds_file="$_vcds_f"; break; fi
done
unset _vcds_root _vcds_main _vcds_common _vcds_f
if [ -n "$_vcds_file" ]; then
    . "$_vcds_file"
else
    echo "VestaRV: no cdspaths.sh found; cp cdspaths.example.sh cdspaths.sh and edit it, or set CDSPATHS" >&2
    false
fi
