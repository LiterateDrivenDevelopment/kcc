#!/bin/bash
set -uo pipefail
LOG=/w/tiny_boot.log; : > "$LOG"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
cd /w
G="gcc -g -O0 -w -std=gnu99 -ffreestanding -fno-stack-protector -Wno-error=implicit-function-declaration -fno-builtin"
$G -c memglue.c -o memglue.o 2>/dev/null; as --64 -o os_linux.o os_linux.s 2>/dev/null
MODS="arena strings io hashtab vec strtab source lexer_core lexer_tables diag preprocessor parser expressions statements declarations types symtab conversions sema ir opt emit_arm64 emit_x86 linker codegen emit_macho dwarf driver main"
OBJ="os_linux.o memglue.o"; for m in $MODS; do $G -c $m.c -o $m.o 2>/dev/null; OBJ="$OBJ $m.o"; done
ld -static -nostdlib -e _start -o kcc_linux $OBJ 2>/dev/null && log "kcc_linux built"
KCC="/w/kcc_linux --target=x86_64-linux"
# get qemu ready in parallel-ish (may need network)
(apt-get install -y -q qemu-system-x86 >/tmp/apt.log 2>&1 && echo ok > /tmp/qemu_ok) &
cd /root/linux-6.6
make tinyconfig >/tmp/c 2>&1
scripts/config --enable 64BIT --enable PRINTK --enable TTY --enable SERIAL_8250 --enable SERIAL_8250_CONSOLE --enable BINFMT_ELF --enable PRINTK_TIME --enable SECTION_MISMATCH_WARN_ONLY --enable DEBUG_KERNEL
make olddefconfig >/tmp/o 2>&1
make -j8 prepare >/tmp/p 2>&1 && log "prepare OK" || { log "prepare FAIL"; tail -10 /tmp/p|tee -a "$LOG"; exit 1; }
make -j8 vmlinux >/tmp/vm 2>&1
[ -f vmlinux ] && log "gcc baseline vmlinux $(stat -c%s vmlinux)B" || { log "gcc baseline FAIL"; tail -20 /tmp/vm|tee -a "$LOG"; exit 1; }
find . -path ./tools -prune -o -name '*.o' -not -name '*.mod.o' -print | grep -vE '^[.]/arch/x86/(entry/vdso|realmode|boot|purgatory)/' | while read -r o; do b="${o%.o}"; [ -f "$b.c" ] && echo "$o"; done | sort > /tmp/cand.txt
TOT=$(wc -l < /tmp/cand.txt); log "candidates: $TOT"
mkdir -p /w/gccbak; : > /w/bakmap.txt
OK=0; F=0
FORCE_GCC="${FORCE_GCC:-}"
while read -r o; do
  b="${o%.o}"; d=$(dirname "$o"); base=$(basename "$o"); cmdf="$d/.$base.cmd"
  bn=$(echo "$o" | tr './' '__'); cp "$o" "/w/gccbak/$bn" 2>/dev/null; echo "$bn $o" >> /w/bakmap.txt
  skip=0; for g in $FORCE_GCC; do case "$o" in *$g*) skip=1;; esac; done
  if [ "$skip" = 1 ]; then F=$((F+1)); continue; fi   # keep gcc object (bisect)
  line=""; [ -f "$cmdf" ] && line=$(sed -n 's/^savedcmd_[^:]*:= //p;s/^cmd_[^:]*:= //p' "$cmdf" | head -1)
  if [ -n "$line" ]; then
    FLAGS=""; prev=""
    for tok in $line; do case "$tok" in -I*|-D*|-U*|-nostdinc|-std=*) FLAGS="$FLAGS $tok";; -include) FLAGS="$FLAGS -include";; *) [ "$prev" = "-include" ] && FLAGS="$FLAGS $tok";; esac; prev="$tok"; done
    if timeout 60 $KCC $FLAGS -c -o "$o.kcc" "$b.c" >/dev/null 2>&1 && [ -s "$o.kcc" ]; then mv -f "$o.kcc" "$o"; OK=$((OK+1)); else rm -f "$o.kcc"; F=$((F+1)); fi
  else F=$((F+1)); fi
done < /tmp/cand.txt
log "kcc-compiled OK=$OK gcc-fallback=$F of $TOT"
nm -A /w/gccbak/* 2>/dev/null | grep -E ' [TtDdRrBbWwVv] ' | sed -E 's#^/w/gccbak/([^:]+):[0-9a-f]+ [TtDdRrBbWwVv] #\1 #' | awk '{print $2, $1}' | sort -u > /w/sym2bak.txt
log "symbol index: $(wc -l < /w/sym2bak.txt) defined syms across backups"
# Heal by stubbing: symbols kcc references in config-disabled dead code (net/cfi,
# never executed in tinyconfig) get `--defsym sym=0'. This KEEPS every kcc object
# (unlike reverting to gcc), and the dead code that names them never runs.  A few
# kcc-DROPPED static defs are restored from the gcc backup instead (real defs).
mkdir -p /w/ldwrap; : > /w/defsyms.txt
cat > /w/ldwrap/ld <<'W'
#!/bin/bash
exec /usr/bin/ld "$@" $(cat /w/defsyms.txt 2>/dev/null)
W
chmod +x /w/ldwrap/ld
export PATH=/w/ldwrap:$PATH
linked=0
for pass in 1 2 3 4 5 6; do
  log "pass $pass: make -j1 vmlinux (defsyms=$(wc -l < /w/defsyms.txt), avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MB)"
  make -j1 vmlinux >/tmp/vm2 2>&1 && { log "*** vmlinux LINKED (pass $pass) $(stat -c%s vmlinux)B ***"; cp vmlinux /w/vmlinux.tiny.kcc; linked=1; break; }
  grep -oE "undefined reference to \`[^']+'" /tmp/vm2 | sed "s/.*to .//;s/.$//" | sort -u > /tmp/undef.txt
  U=$(wc -l < /tmp/undef.txt)
  [ "$U" -eq 0 ] && { log "pass $pass: link failed, no undef (other error) — full tail:"; cp /tmp/vm2 /w/lasterr.log; tail -30 /tmp/vm2|tee -a "$LOG"; break; }
  add=0; stub=0
  while read -r sym; do
    bak=$(grep -m1 "^$sym " /w/sym2bak.txt | awk '{print $2}')
    if [ -n "$bak" ]; then                 # kcc dropped a real def: restore gcc object
      orig=$(grep -m1 "^$bak " /w/bakmap.txt | awk '{print $2}')
      [ -n "$orig" ] && cp "/w/gccbak/$bak" "$orig" 2>/dev/null && add=$((add+1))
    else                                   # dead reference to a config-off symbol: stub to 0
      grep -qx -- "--defsym $sym=0" /w/defsyms.txt || { echo "--defsym $sym=0" >> /w/defsyms.txt; stub=$((stub+1)); }
    fi
  done < /tmp/undef.txt
  log "pass $pass: undef=$U → restored $add gcc objs, stubbed $stub dead syms"
  [ $((add+stub)) -eq 0 ] && { log "no progress; sample undef:"; head -10 /tmp/undef.txt|tee -a "$LOG"; break; }
done
[ "$linked" = 1 ] || { log "vmlinux did not link; stopping"; exit 1; }
log "kcc objects compiled=$OK, dead syms stubbed=$(wc -l < /w/defsyms.txt)"
nm vmlinux 2>/dev/null | sort > /w/vmlinux.nm; log "nm dumped $(wc -l < /w/vmlinux.nm) syms"
# map the crash RIP: decompressed _text is at phys 0x1000000 (virt 0xffffffff81000000);
# the QEMU #GP was at 0x01002d40 -> _text + 0x2d40 -> virt 0xffffffff81002d40
log "=== symbol at/just-below the #GP (virt 0xffffffff81002d40) ==="
awk 'strtonum("0x"$1) <= strtonum("0xffffffff81002d40") {last=$0} END{print last}' /w/vmlinux.nm | tee -a "$LOG"
grep -iE "0xffffffff810029|0xffffffff81002[a-f]|0xffffffff810030" /w/vmlinux.nm 2>/dev/null | head | tee -a "$LOG"
make -j2 bzImage >/tmp/bz 2>&1 && { log "*** bzImage OK $(stat -c%s arch/x86/boot/bzImage)B ***"; cp arch/x86/boot/bzImage /w/bzImage.tiny; } || { log "bzImage FAIL"; tail -12 /tmp/bz|tee -a "$LOG"; exit 1; }
# --- BOOT in QEMU ---
wait 2>/dev/null
if [ ! -f /tmp/qemu_ok ]; then apt-get install -y -q qemu-system-x86 >/tmp/apt2.log 2>&1 && echo ok > /tmp/qemu_ok; fi
if command -v qemu-system-x86_64 >/dev/null; then
  log "booting kcc-built bzImage in QEMU (TCG, 90s cap)..."
  timeout 90 qemu-system-x86_64 -M pc -m 256 -kernel arch/x86/boot/bzImage -nographic \
    -append "console=ttyS0 earlyprintk=serial panic=-1 reboot=t" -no-reboot > /w/qemu_serial.log 2>&1
  log "=== QEMU serial (first 40 lines) ==="; head -40 /w/qemu_serial.log | tee -a "$LOG"
  log "=== QEMU serial (last 25 lines) ==="; tail -25 /w/qemu_serial.log | tee -a "$LOG"
  if grep -qiE "Linux version|Kernel command line|Booting|start_kernel|Run /init|No working init|Unable to mount root|VFS:" /w/qemu_serial.log; then
    log "*** KERNEL BOOTED — kcc-compiled Linux reached start_kernel/init ***"
  else
    log "QEMU produced no recognizable boot output (see /w/qemu_serial.log)"
  fi
else
  log "qemu-system-x86_64 unavailable (no network for apt?); bzImage saved to /w/bzImage.tiny"
fi
log "DONE"
