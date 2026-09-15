# kcc — A Formal C17 Compiler in ARM64 Assembly

**kcc** is a formal C17 compiler written entirely in ARM64 assembly, and set
down as a single **literate program** using [weft](https://github.com/temo-pacheco/weft),
a metalanguage built to be authored and read by human and AI collaborators
alike. Every instruction is explained in prose before it is written in code.

It checks C against the Standard, optimises it, allocates registers, and emits
native machine code; it compiles itself to a byte-identical binary; and it
**cross-compiles to x86-64** (Linux and macOS). It builds and runs Lua, SQLite,
and DOOM — and boots a Linux kernel.

The whole book **is** the compiler (≈1000 pages): download the latest
**[kcc.pdf from Releases](https://gitlab.polinesso.org/literate-programming/kcc/-/releases)**,
or build it yourself (see below). Learn more about Literate Driven Development
at <https://literatedriven.com>.

## The `.weft` files are the only source of truth

Everything the machine builds — the assembly modules, the verification scripts,
and the `Makefile` itself — is **generated** by tangling the literate sources.
You never edit generated files; you edit the book.

```
kcc.weft          master document (LaTeX preamble + @i includes)
literate/         all the chapters (prose + code fragments)
assets/           cover art (SVG → the PDF covers)
README.md         this file
LICENSE           MIT
```

The typeset book, `kcc.pdf`, is **not** committed — it is an ~8 MB binary that
changes on every edit. Download it from Releases, or build it with `make pdf`.

## Build

There is a one-time bootstrap: because the `Makefile` is itself tangled from the
book, you generate it first, then use it.

```sh
# 1. Tangle sources, scripts, and the Makefile into gen/ (and ./Makefile).
weft -p gen/ --mkdirs kcc.weft

# 2. Build the compiler (gen/kcc).
make

# 3. Compile something with it.
./gen/kcc gen/hello.c -o gen/hello && ./gen/hello
```

`-p gen/` prepends `gen/` to every tangle output; `--mkdirs` creates the
directories. The generated tree lives entirely under `gen/` (plus the root
`Makefile`); `make clean` removes it and the command above regenerates it.

### Common targets

| Target | What it does |
|--------|--------------|
| `make` / `make build` | assemble + link `gen/kcc` |
| `make difftest` | compile a corpus with kcc **and** clang, compare |
| `make diagtest` / `make warntest` | invalid programs are rejected; `-Wall` warns |
| `make test-codegen` / `make e2e` / `make interop` | run generated programs |
| `make selfhost-*` | recompile a module in C with kcc, relink, verify |
| `make meta-c` | full self-host fixpoint on Linux (needs Docker + qemu) |
| `make ci` | the complete verification suite |
| `make pdf` | weave the book and typeset `kcc.pdf` |

The verification scripts locate their own base directory, so they work under any
`-p` prefix.

## The book

`make pdf` weaves the `.weft` sources to `kcc.tex` and typesets `kcc.pdf` with
LuaLaTeX. The covers are regenerated from `assets/*.svg` when `rsvg-convert` is
available. The resulting `kcc.pdf` is git-ignored; the released book is
published manually as a **Release** asset on GitLab, so the repository stays
free of the large, frequently-changing binary.

## Prerequisites

- **weft** ≥2.0.0  (the literate tool).
- A C toolchain's `as` and `ld` (Xcode command-line tools on macOS).
- For the book: a TeX distribution with LuaLaTeX and `latexmk` — a full
  [TeX Live](https://tug.org/texlive/), or the lightweight
  [TinyTeX](https://yihui.org/tinytex/) (a minimal TeX Live) — and, optionally,
  `rsvg-convert` for the covers.
- For `make meta-c` and the kernel-boot reproduction: Docker and qemu-user.

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Cuauhtémoc Pacheco, co-authored
with an AI collaborator (Claude).
