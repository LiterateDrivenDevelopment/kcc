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
        selfhost-types selfhost-opt selfhost-lexer-tables selfhost-linker \
        selfhost-statements selfhost-emit-macho selfhost-expressions selfhost-parser selfhost-driver \
        selfhost-declarations selfhost-dwarf selfhost-emit-arm64 selfhost-sema \
        selfhost-emit-x86 selfhost-preprocessor selfhost-codegen meta-a \
        difftest interop e2e diagtest warntest test-codegen doc weave clean \
        run map

# Default: build everything
all default: build

# Tangle: extract .s files from .weft literate sources
tangle:
	mkdir -p tmp/src tmp/tests tmp/docs tmp/selfhost tmp/include tmp/runtime
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

# Self-hosting (Stage 8l): compile kcc's type system in C, relink, run suite
selfhost-types: build
	chmod +x tmp/selfhost/types_verify.sh
	tmp/selfhost/types_verify.sh

# Self-hosting (Stage 8m): compile kcc's optimizer in C, relink, run suite
selfhost-opt: build
	chmod +x tmp/selfhost/opt_verify.sh
	tmp/selfhost/opt_verify.sh

# Self-hosting (Stage 8n): compile kcc's lexer tables in C, relink, run suites
selfhost-lexer-tables: build
	chmod +x tmp/selfhost/lexer_tables_verify.sh
	tmp/selfhost/lexer_tables_verify.sh

# Self-hosting (Stage 8o): compile kcc's linker info in C, relink, run suite
selfhost-linker: build
	chmod +x tmp/selfhost/linker_verify.sh
	tmp/selfhost/linker_verify.sh

# Self-hosting (Stage 8p): compile kcc's statement parser in C, relink, run suite
selfhost-statements: build
	chmod +x tmp/selfhost/statements_verify.sh
	tmp/selfhost/statements_verify.sh

# Self-hosting (Stage 8q): compile kcc's Mach-O writer in C, relink, run suite
selfhost-emit-macho: build
	chmod +x tmp/selfhost/emit_macho_verify.sh
	tmp/selfhost/emit_macho_verify.sh

# Self-hosting (Stage 8r): compile kcc's expression parser in C, relink, run suite
selfhost-expressions: build
	chmod +x tmp/selfhost/expressions_verify.sh
	tmp/selfhost/expressions_verify.sh

# Self-hosting (Stage 8s): compile kcc's parser spine in C, relink, run suite
selfhost-parser: build
	chmod +x tmp/selfhost/parser_verify.sh
	tmp/selfhost/parser_verify.sh

# Self-hosting (Stage 8t): compile kcc's driver in C, relink, run codegen+e2e
selfhost-driver: build
	chmod +x tmp/selfhost/driver_verify.sh
	tmp/selfhost/driver_verify.sh

# Self-hosting (Stage 8u): compile kcc's declaration parser in C, relink, run codegen
selfhost-declarations: build
	chmod +x tmp/selfhost/declarations_verify.sh
	tmp/selfhost/declarations_verify.sh

# Self-hosting (Stage 8v): compile kcc's DWARF emitter in C, relink,
# run codegen + a -g byte-compare against the asm build
selfhost-dwarf: build
	chmod +x tmp/selfhost/dwarf_verify.sh
	tmp/selfhost/dwarf_verify.sh

# Self-hosting (Stage 8w): compile kcc's ARM64 encoder + .s renderer in C,
# relink, verify both halves (difftest + --emit-asm functional check)
selfhost-emit-arm64: build
	chmod +x tmp/selfhost/emit_arm64_verify.sh
	tmp/selfhost/emit_arm64_verify.sh

# Self-hosting (Stage 8x): compile kcc's semantic analyzer in C, relink,
# verify with difftest + diagtest + warntest + codegen
selfhost-sema: build
	chmod +x tmp/selfhost/sema_verify.sh
	tmp/selfhost/sema_verify.sh

# Self-hosting (Stage 8y): compile kcc's x86-64 back end in C, relink,
# verify functionally (arm64 codegen + x86 programs run under Rosetta)
selfhost-emit-x86: build
	chmod +x tmp/selfhost/emit_x86_verify.sh
	tmp/selfhost/emit_x86_verify.sh

# Self-hosting (Stage 8z): compile kcc's preprocessor in C, relink,
# verify with difftest + diagtest + codegen
selfhost-preprocessor: build
	chmod +x tmp/selfhost/preprocessor_verify.sh
	tmp/selfhost/preprocessor_verify.sh

# Self-hosting: compile kcc's ARM64 code generator in C, relink, verify
selfhost-codegen: build
	chmod +x tmp/selfhost/codegen_verify.sh
	tmp/selfhost/codegen_verify.sh

# Milestone A: cross-compile a multi-TU C program to Linux/x86-64 with kcc,
# link against the Linux runtime (no libc), run it natively (Chapter: Runtime).
meta-a: build
	chmod +x tmp/runtime/meta_a_verify.sh
	tmp/runtime/meta_a_verify.sh

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
