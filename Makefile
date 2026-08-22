# kcc — A Formal C17 Compiler in ARM64 Assembly
# Build pipeline: .weft → weft tangle → .s → as → .o → ld → kcc
#
# Migrated from justfile. Written for the system make (GNU Make 3.81), which
# lacks .ONESHELL/.SHELLFLAGS, so each multi-command recipe is a single logical
# line (joined with \) that begins with `set -e` for fail-fast behaviour.
# Command echo is silenced (.SILENT) to match the original `set quiet`.

SHELL := /bin/bash
.SILENT:

# All assembly source basenames (order doesn't matter for linking)
sources := main syscalls arena strings io hashtab vec strtab source lexer lexer_tables diag preprocessor parser expressions statements declarations types symtab conversions sema ir opt emit_arm64 emit_x86 linker codegen emit_macho dwarf driver

# Library sources (everything except main — shared with the test binary)
lib_sources := syscalls arena strings io hashtab vec strtab source lexer lexer_tables diag preprocessor parser expressions statements declarations types symtab conversions sema ir opt emit_arm64 emit_x86 linker codegen emit_macho dwarf driver

# Test source basenames (in tmp/tests/)
test_sources := test_runner test_lexer

# SDK root for the linker
SDKROOT := $(shell xcrun --show-sdk-path)
LDFLAGS := -lSystem -syslibroot $(SDKROOT) -e _main -arch arm64

.DEFAULT_GOAL := build

.PHONY: all default tangle assemble build test selfhost selfhost-lexer \
        difftest interop e2e diagtest warntest test-codegen doc weave \
        clean run map

# Default: build everything
all default: build

# Tangle: extract .s files from .weft literate sources
tangle:
	mkdir -p tmp/src tmp/tests tmp/docs tmp/selfhost tmp/include
	weft kcc.weft

# Assemble: compile each .s to .o
assemble: tangle
	set -e; for f in $(sources); do as -o tmp/src/$${f}.o tmp/src/$${f}.s; done

# Link: produce the kcc binary
build: assemble
	set -e; OBJ=""; for f in $(sources); do OBJ="$$OBJ tmp/src/$${f}.o"; done; \
	ld -o tmp/kcc $$OBJ $(LDFLAGS)

# Test: build and run the unit-test suite
test: tangle
	set -e; \
	for f in $(lib_sources); do as -o tmp/src/$${f}.o tmp/src/$${f}.s; done; \
	for f in $(test_sources); do as -o tmp/tests/$${f}.o tmp/tests/$${f}.s; done; \
	OBJ=""; \
	for f in $(lib_sources); do OBJ="$$OBJ tmp/src/$${f}.o"; done; \
	for f in $(test_sources); do OBJ="$$OBJ tmp/tests/$${f}.o"; done; \
	ld -o tmp/test_kcc $$OBJ $(LDFLAGS); \
	echo ""; \
	./tmp/test_kcc

# Self-hosting (Stage 8b): compile kcc's arena in C with kcc, relink, run suite
selfhost: build
	chmod +x tmp/selfhost/selfhost.sh
	tmp/selfhost/selfhost.sh

# Self-hosting (Stage 8b): compile a C tokenizer with kcc, self-test, diff clang
selfhost-lexer: build
	chmod +x tmp/selfhost/lexer_verify.sh
	tmp/selfhost/lexer_verify.sh

# Self-hosting (Stage 8c): compile kcc's vector in C with kcc, relink, run suite
selfhost-vec: build
	chmod +x tmp/selfhost/vec_verify.sh
	tmp/selfhost/vec_verify.sh

# Self-hosting (Stage 8d): compile kcc's string primitives in C, relink, run suite
selfhost-strings: build
	chmod +x tmp/selfhost/strings_verify.sh
	tmp/selfhost/strings_verify.sh

# Self-hosting (Stage 8e): compile kcc's hash table in C, relink, run suite
selfhost-hashtab: build
	chmod +x tmp/selfhost/hashtab_verify.sh
	tmp/selfhost/hashtab_verify.sh

# Self-hosting (Stage 8f): compile kcc's string interner in C, relink, run suite
selfhost-strtab: build
	chmod +x tmp/selfhost/strtab_verify.sh
	tmp/selfhost/strtab_verify.sh

# Self-hosting (Stage 8g): compile kcc's buffered output in C, relink, run suite
selfhost-io: build
	chmod +x tmp/selfhost/io_verify.sh
	tmp/selfhost/io_verify.sh

# Self-hosting (Stage 8h): compile kcc's source manager in C, relink, run suite
selfhost-source: build
	chmod +x tmp/selfhost/source_verify.sh
	tmp/selfhost/source_verify.sh

# Self-hosting (Stage 8i): compile kcc's diagnostic engine in C, relink, run suites
selfhost-diag: build
	chmod +x tmp/selfhost/diag_verify.sh
	tmp/selfhost/diag_verify.sh

# Self-hosting (Stage 8j): compile kcc's symbol table in C, relink, run suite
selfhost-symtab: build
	chmod +x tmp/selfhost/symtab_verify.sh
	tmp/selfhost/symtab_verify.sh

# Self-hosting (Stage 8k): compile kcc's conversions in C, relink, run suite
selfhost-conversions: build
	chmod +x tmp/selfhost/conversions_verify.sh
	tmp/selfhost/conversions_verify.sh

# Differential tests: compile each program with kcc AND clang, compare
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

# Diagnostics: invalid programs must be rejected with clear errors (no hang)
diagtest: build
	chmod +x tmp/tests/diagtest.sh
	tmp/tests/diagtest.sh

# Warnings: -Wall must warn while the default build stays silent
warntest: build
	chmod +x tmp/tests/warntest.sh
	tmp/tests/warntest.sh

# Code generation tests: compile with kcc, link, run, check exit codes
test-codegen: build
	chmod +x tmp/tests/test_codegen.sh
	tmp/tests/test_codegen.sh

# Weave: generate LaTeX source
doc:
	weft -w tex -d -r kcc.weft

# Weave + compile to PDF (lualatex for native Unicode)
weave: doc
	latexmk -lualatex -interaction=nonstopmode -f kcc.tex

# Clean generated files
clean:
	rm -rf tmp/

# Run the compiler:  make run ARGS="file.c -o out"
run: build
	./tmp/kcc $(ARGS)

# Structure map (JSON)
map:
	weft -m kcc.weft
