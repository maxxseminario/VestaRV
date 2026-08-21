"""Declare the hermetic LaTeX smoke document, behind one explicit switch.

bazel_latex 1.2.2 calls native.sh_binary inside its latex_document macro, and
Bazel 9 removed that native rule.  The failure is at LOAD time, which a manual
tag cannot contain: any wildcard pattern that has to enumerate this package
fails outright, taking every unrelated target under //platform/... with it.

Putting this line in .bazelrc puts sh_binary back, and py_binary with it, which
bazel_latex's generated latexrun BUILD file needs for the same reason:

    common --incompatible_autoload_externally=+sh_binary,+sh_test,+py_binary,+py_library,+py_test

The two changes are one change and have to land together, so this file carries
the switch.  Flip ENABLE to True in the same commit that adds that line.  Until
then the package declares nothing and still loads, and a wildcard sweep sees an
empty package rather than a broken one.

Probing for the flag instead of naming it was tried and does not work:
hasattr(native, "sh_binary") reads False even with the flag in effect, so the
guard would suppress the target on exactly the configuration that supports it.

The smoke document was BUILT GREEN on this host with the flag set, before the
switch was added, so what is gated here is known to work and not a guess.

Delete this file and call latex_document directly once bazel_latex loads
sh_binary from @rules_shell.
"""

load("@bazel_latex//:latex.bzl", "latex_document")

# Set to True together with the .bazelrc line quoted above, never separately.
ENABLE_HERMETIC_LATEX_SMOKE = True

def latex_document_where_supported(name, main, **kwargs):
    """Call bazel_latex's latex_document, or declare nothing where it cannot run."""
    if not ENABLE_HERMETIC_LATEX_SMOKE:
        return
    latex_document(name = name, main = main, **kwargs)
