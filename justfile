# kcc — A Formal C17 Compiler in ARM64 Assembly
# Build pipeline: .weft → weft tangle → .s → as → .o → ld → kcc

set quiet

# All assembly source basenames (order doesn't matter for linking)
sources := "main syscalls arena strings io hashtab vec strtab source lexer lexer_tables diag preprocessor parser expressions statements declarations types symtab conversions sema ir opt emit_arm64 linker codegen emit_macho driver"

# Library sources (everything except main — shared with test binary)
lib_sources := "syscalls arena strings io hashtab vec strtab source lexer lexer_tables diag preprocessor parser expressions statements declarations types symtab conversions sema ir opt emit_arm64 linker codegen emit_macho driver"

# Test source basenames (in tmp/tests/)
test_sources := "test_runner test_lexer"

# Default: build everything
default: build

# Tangle: extract .s files from .weft literate sources
tangle:
    mkdir -p tmp/src tmp/tests tmp/docs tmp/selfhost
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

# Test: build and run the test suite
test: tangle
    #!/usr/bin/env bash
    set -euo pipefail
    # Assemble library sources
    for f in {{lib_sources}}; do
        as -o tmp/src/${f}.o tmp/src/${f}.s
    done
    # Assemble test sources
    for f in {{test_sources}}; do
        as -o tmp/tests/${f}.o tmp/tests/${f}.s
    done
    # Link test binary
    OBJ=""
    for f in {{lib_sources}}; do
        OBJ="$OBJ tmp/src/${f}.o"
    done
    for f in {{test_sources}}; do
        OBJ="$OBJ tmp/tests/${f}.o"
    done
    ld -o tmp/test_kcc $OBJ \
        -lSystem -syslibroot $(xcrun --show-sdk-path) \
        -e _main -arch arm64
    echo ""
    ./tmp/test_kcc

# Self-hosting (Stage 8b): compile kcc's arena in C with kcc, relink, run the suite
selfhost: build
    chmod +x tmp/selfhost/selfhost.sh
    tmp/selfhost/selfhost.sh

# Self-hosting (Stage 8b): compile a C tokenizer with kcc, self-test, diff clang
selfhost-lexer: build
    chmod +x tmp/selfhost/lexer_verify.sh
    tmp/selfhost/lexer_verify.sh

# Differential tests: compile each program with kcc AND clang, compare exit codes
difftest: build
    chmod +x tmp/tests/difftest.sh
    tmp/tests/difftest.sh

# ABI interop: compile one TU with kcc and the other with clang, link, run
interop: build
    chmod +x tmp/tests/interop.sh
    tmp/tests/interop.sh

# End-to-end: kcc compiles AND links to an executable, then runs it
e2e: build
    chmod +x tmp/tests/e2e.sh
    tmp/tests/e2e.sh

# Code generation tests: compile C programs with kcc, link, run, check exit codes
test-codegen: build
    chmod +x tmp/tests/test_codegen.sh
    tmp/tests/test_codegen.sh

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
