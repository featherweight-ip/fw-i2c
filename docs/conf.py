# Sphinx configuration for the fw-i2c documentation.
#
# Build:  dfm run docs              (sphinx-build -W: a warning fails the build)
#    or:  sphinx-build -W -b html docs docs/_build/html

import os

project = "fw-i2c"
copyright = "2026, Featherweight-IP"
author = "Featherweight-IP"
release = "0.1.0"

extensions = [
    "myst_parser",
    "sphinx_copybutton",
    "sphinx_peakrdl",
    "sphinxcontrib.wavedrom",
    "sphinxcontrib.mermaid",
]

source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "fieldlist",
]
myst_heading_anchors = 3

exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]

# -- Registers (sphinx-peakrdl) ---------------------------------------------
_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
peakrdl_input_files = [
    os.path.join(_root, "src", "rdl", "oc_i2c_master.rdl"),
]
peakrdl_top_component = "oc_i2c_master"
peakrdl_html_title = "freecores i2c registers"
peakrdl_default_link_to = "doc"

# -- Timing diagrams (sphinxcontrib-wavedrom) -------------------------------
# Render to SVG at build time with the Python wavedrom package, so the HTML
# needs no JavaScript and the build works offline.
render_using_wavedrompy = True

# -- HTML --------------------------------------------------------------------
html_theme = "furo"
html_title = "fw-i2c — I2C Controller IP"
html_static_path = ["_static"]

# Untagged code fences are plain text (diagrams, transcripts); Verilog and
# C blocks tag themselves.
highlight_language = "text"
pygments_style = "friendly"
pygments_dark_style = "monokai"
