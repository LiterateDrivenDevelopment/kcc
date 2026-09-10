# Fix plan: kcc emits `init_task` as `.comm` → kernel can't boot

## Root cause (confirmed on staging x86_64 + KVM)
A kcc-built Linux 6.6 tinyconfig bzImage decompresses and jumps to `startup_64`,
then triple-faults at `_text+0xe5` with `RSP=0xfffffffffffffff0` (garbage). The
bad `initial_stack` traces to `init_task`: gcc emits it in `.data` (5952 B +
relocations); **kcc emits it as a `.comm` COMMON symbol** (zero, no initializer).
Forcing only `init/init_task.c` to gcc removes the crash and the kernel runs past
`startup_64` (confirmed: deep faults are the early `#PF` page-table builder, no
triple-fault). So this is a specific, fixable codegen bug — NOT density/size
(a 11.7 MB mini-kcc kernel fails identically to the 108 MB one; the 10 MB gcc
baseline boots).

## Why it falls to `.comm`
`kcc_x86_emit_data` (48x:1550) routes a global to static data only if it passes
`kcc_global_const_rodata`, `kcc_global_const_ptrarr`, or `kcc_global_sym_data`;
otherwise `x86_emit_zerofill` → `.comm`, with the initializer meant to run at
runtime via `kcc.module_init` (which a kernel never calls). The gate
`kcc_rodata_struct_ok` (49-ir.weft:717) only accepts a struct whose every field
is a scalar literal or `.member = literal`. `init_task` has nested aggregates,
pointer/symbol leaves, arrays, strings, compound literals → rejected → `.comm`.

## Constructs the emitter must handle (from preprocessed init_task, Linux 6.6)
- All-designated `.m = v` at every level; deeply nested designated structs.
- Symbol addresses in ANY scalar field (not just pointers):
  `.active_mm = &init_mm`, `.real_parent = &init_task` (self),
  `.cpus_ptr = &init_task.cpus_mask` (**`&obj.member` = sym+offset**),
  `.se.group_node = { &(init_task.se.group_node), ... }` (nested `&self.a.b`),
  `.stack = init_stack` (array name), `.fn = do_no_restart_syscall` (fn name),
  `.real_cred = (typeof(*(&init_cred)) *)(&init_cred)` (cast around `&`),
  `.thread = { .sp = (unsigned long)&__end_init_task - sizeof(...) }`
  (**`&sym - const` stored in an unsigned long scalar**).
- Compound literals as field values: `(cpumask_t){ { [K-1] = ... } }`,
  `(spinlock_t){...}`, `(raw_spinlock_t){...}`.
- `[index] = value` array designators; `char comm[] = "swapper"` (paint bytes);
  empty `{ }` and `{{0}}` (zero-fill).

## Two-part fix
### Part 1 — extend `kcc_ir_const_symaddr` (49-ir.weft:855)
Add cases so it returns `sym`,`off` for:
- `&obj.member` / `obj.member` (member access): `symaddr(obj) + field->f3`.
- `&obj->member`: `symaddr(obj) + field->f3` (obj already an address).
- `&obj[i]` / `obj[i]`: `symaddr(obj) + i*elem_size` (i an ICE).
Needs member-offset lookup (field `f3`) and element size from the resolved type.
RISK: `kcc_global_sym_data` uses this predicate — extending it can reclassify
existing globals from `.comm`+module_init to static data. That is *more* correct
but changes emitted bytes; must re-verify meta-c fixpoint + difftest.

### Part 2 — recursive static-initializer emitter (48x) + gate (49)
Design: **byte-image + relocation list**, sized via `kcc_arena_alloc(total)`
(no fixed 1024 buffer — init_task is 5952 B):
- `x86_paint_init(buf,total,ty,init,base,relocs,&nrel,rmax)`:
  - struct/union (TY_STRUCT): resolve each field's value (designator `.m` lookup
    or positional cursor); paint at `base+field->f3`; bit-pack bit-field runs
    into their container; recurse for aggregate fields; a union takes only its
    designated/first member (others stay zero).
  - array (TY_ARRAY): iterate elems (positional or `[i]` designator); recurse at
    `base + idx*elem_size`; `char[]` from a string → copy bytes.
  - scalar/pointer: check `kcc_ir_const_symaddr` FIRST (record reloc, leave 8
    bytes zero); string literal + pointer → string reloc; else write LE bits via
    `kcc_rodata_leaf_bits` at the field width. Unwrap compound-literal and
    brace-elided `{expr}` to the inner init.
- Emit: walk `0..total`; between relocations emit `.byte` runs; at each reloc
  emit `.quad sym+off` (or `.quad .Lx86str<id>`); pick section like
  `x86_emit_sym_data` (attr section / `.data` if writable / `.rodata`).
- Gate `kcc_global_static_ok(decl)`: recursively verify every leaf is an ICE,
  float lit, string, or `kcc_ir_const_symaddr`-recognisable; every aggregate is
  an init-list/compound-literal; reject anything else so it stays `.comm`
  (status quo, no regression). Wire in `kcc_x86_emit_data` and
  `x86_emit_one_static` BEFORE `x86_emit_zerofill`.

## Validation (mandatory, in order)
1. `make tangle` + rebuild ARM `tmp/kcc`; `make difftest` (363/0),
   `make test-codegen` (232/0), `make diagtest`.
2. `make meta-c` — 3-way byte-identical fixpoint (0/29) MUST hold.
3. Rebuild kernel (shrink_boot.sh, no FORCE of init_task), boot on staging KVM
   with `-d int,cpu_reset`; confirm the `_text+0xe5` RSP crash is gone.
4. Expect further such globals downstream (init_mm, init_fs, init_signals, …);
   iterate: each is the same class, now handled by the general emitter.

## Repro scaffolding (tmp/metac, gitignored)
`gcc_baseline.sh` (all-gcc tinyconfig → bzImage.gcc, boots), `shrink_boot.sh`
(FORCE_GCC subset), `inspect_inittask.sh` (kcc vs gcc `.o` symbol/section diff),
`vga_stage.py` (QMP VGA screendump), `initramfs.cpio.gz` (static /init banner).
Test host: any x86-64 Linux box with QEMU 8.x + KVM (work under `~/kcc-boot/`).
