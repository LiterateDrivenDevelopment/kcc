# Reproducing the kcc-built Linux boot on a native x86-64 host

**Files here:** `tiny_boot.sh` (full build+boot), `native_boot.sh` (KVM boot of
an existing bzImage), this README. The scripts run *inside* the kcc-kbuild /
kcc-qemu container and expect a working directory mounted at `/w` that holds the
kcc-tangled C sources (`make tangle` output + `os_linux.s`, `memglue.c`) and the
built `bzImage.tiny`. In this repo that scratch dir is `tmp/metac` (gitignored,
regenerable); copy these scripts there (or bind-mount `kernel-boot` as `/w`
alongside the sources) before running. `bzImage.tiny` is a build artifact and is
NOT committed — regenerate it with `tiny_boot.sh`.


This session got kcc to compile ~84% of a tinyconfig Linux 6.6 kernel, link a
valid bzImage, and boot it in QEMU past the real-mode setup with **no triple
fault** (the early-GDT #GP was root-caused and fixed). Full boot-to-console
could not be verified on the ARM Mac because QEMU there runs the x86 guest under
**TCG inside an emulated amd64 container** — triple emulation: glacial and
non-deterministic (a 114 MB kcc vmlinux decompresses very slowly; serial output
was flaky).

On a **native x86-64 Linux host with KVM**, the same flow runs in seconds and is
deterministic. This is how to finish the verification.

## Prerequisites (native x86-64 Linux)
- KVM available: `ls /dev/kvm` and the user in the `kvm` group.
- `qemu-system-x86` installed.
- The kcc-kbuild Docker image (linux-6.6 defconfig-prepared), OR a local
  linux-6.6 tree + the kcc sources. The image used here:
  `kcc-kbuild:linux66-defconfig` (amd64). Rebuild if lost — see MEMORY.md
  "Build Pipeline".

## One-shot: build + boot
`tmp/metac/tiny_boot.sh` already does the whole build (build kcc_linux from the
tangled C, reconfigure tinyconfig, gcc baseline, kcc-compile the obj-y, heal,
link, bzImage, boot). On a native host, run it with the sources mounted at
`/w`:

```bash
docker run --rm --platform=linux/amd64 \
  -v /path/to/tmp/metac:/w \
  --device=/dev/kvm \
  kcc-qemu:boot bash /w/tiny_boot.sh
```

The only change for native speed is the QEMU line inside the boot step: add
`-enable-kvm`. Use `native_boot.sh` (below) for a KVM boot of an already-built
`/w/bzImage.tiny`.

## Just boot an existing bzImage (fast, native)
`tmp/metac/bzImage.tiny` (Linux 6.6, ~4.2 MB) is the kcc-built image from this
session. On a native x86-64 host:

```bash
qemu-system-x86_64 -enable-kvm -M pc -m 512 \
  -kernel bzImage.tiny -nographic \
  -append "console=ttyS0,115200 earlyprintk=ttyS0,115200,keep panic=-1" \
  -no-reboot
```

Expected once early boot is correct: `early console in setup code` →
`Decompressing Linux... done. Booting the kernel.` → `Linux version 6.6.0 ...`
→ subsystem init → a panic like *"No working init found"* / *"Unable to mount
root fs"* (there is no rootfs — the panic PROVES a full boot through
`start_kernel` and the initcalls). To reach a shell, add a tiny initramfs
(`-initrd` with a static `/init`).

## If it still faults/hangs early — how to pin the next bug
The method that worked this session (a real bisect toolkit):

1. **Get the crash RIP.** Add `-d cpu_reset,int` to QEMU; the first
   `v=0d`/`v=0e ... IP=...` line before `Triple fault` is the faulting address.
2. **Map RIP → function.** The decompressed kernel's `_text` sits at physical
   `0x1000000` (virt `0xffffffff81000000`). So crash `0x0100XXXX` → symbol at
   `0xffffffff8100XXXX`. Find it:
   ```bash
   nm vmlinux | sort > /tmp/nm.txt      # vmlinux, not bzImage
   awk 'strtonum("0x"$1) <= strtonum("0xffffffff8100XXXX"){l=$0} END{print l}' /tmp/nm.txt
   ```
3. **Confirm the file is kcc's.** If the symbol is in a `.c` kcc compiled,
   `objdump -d` its `.o` around the crash offset and compare with gcc's `-S`.
4. **Bisect by reverting.** `tiny_boot.sh` honours `FORCE_GCC="a/b/c ..."`
   (env): those source paths are kept gcc instead of kcc. Add the suspect file,
   rebuild, reboot; if the crash moves, that file's kcc codegen is the bug.

## What is already fixed (committed this session)
The early crash was kcc emitting file-scope statics as zero-`.bss` + a
`kcc.module_init` runtime store that a kernel never runs, so tables built from
constant initializers (the GDT, initcall/exitcall/fixup/setup) were zero at
boot. Now kcc emits them as static data like gcc:
- `de3d53d` refset scans file-scope asm for `.initcall`/`.pci_fixup` symbols.
- `834b460` skip runtime-init of statics in discarded `.exit*` sections.
- `d57ec49` symbol-address inits (`=fn`/`=&sym`) → `.quad sym+off`.
- `3cd599b` const structs with bit-fields → bit-packed static data.
- `4c09b00` non-const globals + `.member`/`[i]` designators → static data.
- `2b03233` `sizeof`/`alignof` accepted as constant initializers.

Verified: `startup_gdt` / `startup_gdt_descr` byte-identical to gcc; the
`mov %ds` triple-fault is gone. Every fix keeps the meta-c self-hosting fixpoint
byte-identical (0/29).

## Known scale note
kcc's `-O0`-class x86 text is ~15–39× gcc's, so the tinyconfig vmlinux is
~114 MB (vs a few MB). That is fine to link/boot on any real machine but is the
reason TCG decompression was glacial. Shrinking it (a real x86 register
allocator; the ARM64 backend already has one) is the separate density track.
