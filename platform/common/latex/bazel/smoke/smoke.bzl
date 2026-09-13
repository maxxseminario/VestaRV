"""VestaRV: declare the hermetic LaTeX smoke document, behind one explicit switch.

bazel_latex 1.2.2 calls native.sh_binary, which Bazel 9 removed, and the failure is at load
time, so any wildcard enumerating this package would fail outright. The .bazelrc
--incompatible_autoload_externally line puts sh_binary and py_binary back, and
ENABLE_HERMETIC_LATEX_SMOKE must be flipped with it. Probing hasattr(native, ...) reads False.
"""

load("@bazel_latex//:latex.bzl", "latex_document")

# Set to True together with the .bazelrc line quoted above, never separately.
ENABLE_HERMETIC_LATEX_SMOKE = True

def latex_document_where_supported(name, main, **kwargs):
    """Call bazel_latex's latex_document, or declare nothing where it cannot run."""
    if not ENABLE_HERMETIC_LATEX_SMOKE:
        return
    latex_document(name = name, main = main, **kwargs)
