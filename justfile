# kcc — A Formal C17 Compiler in ARM64 Assembly
# Build pipeline: .weft → weft tangle → .s → as → .o → ld → kcc

set quiet

# All assembly source basenames (order doesn't matter for linking)
sources := "main syscalls arena strings io hashtab vec strtab source lexer lexer_tables"

# Default: build everything
default: build

# Tangle: extract .s files from .weft literate sources
tangle:
    mkdir -p tmp/src tmp/tests tmp/docs
    weft kcc.weft

# Assemble: compile each .s to .o
assemble: tangle
    #!/usr/bin/env bash
    set -euo pipefail
    for f in {{sources}}; do
        as -o tmp/src/${f}.o tmp/src/${f}.s
    done

# Link: produce the kcc binary
build: assemble
    #!/usr/bin/env bash
    set -euo pipefail
    OBJ=""
    for f in {{sources}}; do
        OBJ="$OBJ tmp/src/${f}.o"
    done
    ld -o tmp/kcc $OBJ \
        -lSystem -syslibroot $(xcrun --show-sdk-path) \
        -e _main -arch arm64

# Weave: generate LaTeX source
doc:
    weft -w tex kcc.weft

# Weave + compile to PDF (lualatex for native Unicode)
weave: doc
    latexmk -lualatex -interaction=nonstopmode -halt-on-error kcc.tex

# Clean generated files
clean:
    rm -rf tmp/

# Run the compiler
run *ARGS: build
    ./tmp/kcc {{ARGS}}

# Structure map (JSON)
map:
    weft -m kcc.weft
