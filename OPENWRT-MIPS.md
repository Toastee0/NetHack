# NetHack 3.6.7 — OpenWrt big-endian MIPS port (Arduino Yún & friends)

A working cross-compile of NetHack 3.6.7 for **OpenWrt on big-endian MIPS** (`mips_24kc`,
musl libc, soft-float). Built and run on an **Arduino Yún** (Atheros AR9331) running
OpenWrt 24.10, but applies to any OpenWrt ath79/ar71xx MIPS device.

Prebuilt artifacts (the stripped `nethack` binary + `nhdat`) are attached to the GitHub release —
if you just want to play, grab those and skip to **Deploy**.

---

## TL;DR of why this is non-trivial

NetHack stamps every data file (`dungeon`, the special-level `*.lev` files, save/bones files)
with a `struct version_info` and refuses to load anything whose stamp doesn't match the running
binary. **That stamp is architecture-dependent**, and a naïve cross-compile gets it wrong in two
separate ways:

1. **Endianness.** `dgn_comp`/`lev_comp` write the data files as raw binary structs. Tools built
   for the *host* (x86, little-endian) produce little-endian data the big-endian MIPS binary can't
   read → *"Version mismatch"*.

2. **Word size, via `date.h`.** `makedefs` generates `include/date.h` containing
   `VERSION_SANITY1/2/3` — these encode the **sizes of key structs**. A 64-bit host `makedefs`
   bakes in 64-bit sizes (e.g. `VERSION_SANITY2 = 0x148c24958UL`, a **33-bit** value). On the
   32-bit target the data tools *write* that truncated into a 32-bit field (`0x48c24958`) while
   `check_version()` *compares* against the full constant → permanent
   *"Configuration incompatibility for file dungeon"*.

**The fix for both:** generate `date.h` **and** all binary data files with **target-native**
(`makedefs`/`dgn_comp`/`lev_comp`/`dlb`) tools — i.e. run them on the device itself (or under
`qemu-mips`) — and build *both* the game's `version.o` and the data tools against that same
target `date.h`. Get this right and everything lines up.

---

## Prerequisites

- The matching **OpenWrt SDK** for your device, e.g.
  `openwrt-sdk-24.10.7-ath79-generic_gcc-13.3.0_musl.Linux-x86_64`. It provides the
  `mips-openwrt-linux-gcc` toolchain (big-endian `mips_24kc`, musl). `export STAGING_DIR=<sdk>/staging_dir`
  and put `<sdk>/staging_dir/toolchain-*/bin` on `PATH`.
- A normal Linux host toolchain (`gcc`, `make`, `bison`, `flex`, `libncurses-dev`) for the native pass.
- The target device reachable over SSH (to run the data generators natively).

## Build (overview — see `sys/unix/openwrt-mips/` for the scripts)

1. **Cross-build ncurses** (static, non-wide so it links into the binary; NetHack's tty/curses
   ports want non-wide `curses.h`):
   ```
   ./configure --build=x86_64-linux-gnu --host=mips-openwrt-linux --with-build-cc=gcc \
       --disable-widec --without-cxx-binding --without-ada --without-tests \
       --without-progs --without-shared --without-manpages --disable-stripping
   make            # -> lib/libncurses.a, include/curses.h
   ```

2. **Native pass** (`sh sys/unix/setup.sh sys/unix/hints/linux; make all`) — builds the host-side
   `makedefs`/`dgn_comp`/`lev_comp`/`dlb` and the *architecture-independent* generated source
   (`include/onames.h`, `include/pm.h`, `src/monstr.c`, …). Discard the native binary.

3. **Cross-compile the game**: point `src/Makefile` at the cross toolchain and the cross ncurses —
   `CFLAGS += -I<ncurses>/include`, `WINTTYLIB=<ncurses>/lib/libncurses.a`, `WINCURSESLIB=` (blank),
   `LFLAGS=` (drop `-rdynamic`) — then `make -C src CC=mips-openwrt-linux-gcc LINK=... nethack`.
   Use `make -o ../util/<tool> -o ../include/<generated>.h …` so it won't try to *run* the
   (cross) host tools on x86.

4. **Cross-compile the util tools** (`makedefs dgn_comp lev_comp dlb`) the same way. The Makefile's
   recursive `date.h::`/`onames.h` rules fight you (they try to *run* the MIPS `makedefs` on x86) —
   easiest is to link them by hand against the already-cross-built `src/*.o`. See
   `sys/unix/openwrt-mips/build.sh`.

5. **Generate `date.h` + data ON THE TARGET** (this is the crucial step):
   copy the cross-built util tools + `dat/` + `include/` to the device and run
   `sys/unix/openwrt-mips/gen-data.sh`. The device's `makedefs -v` writes a **32-bit** `date.h`
   (e.g. `VERSION_SANITY2 = 0xf48195c4`), and `dgn_comp`/`lev_comp`/`dlb` emit big-endian `dungeon`,
   `*.lev`, and a repacked `nhdat`.

6. **Rebuild the game's `version.o`** against that target `date.h` and relink — now the binary's
   `check_version()` expects the same 32-bit sanity values the data carries. (`version.c` is the
   only game source that uses `VERSION_SANITY`.)

## Deploy

Put the binary + data in a playground and create the writable game-state files:
```
mkdir -p /mnt/data/nethack/save
cp nethack nhdat symbols license sysconf /mnt/data/nethack/
: > record ; : > logfile      # high scores + log
chmod 0777 /mnt/data/nethack /mnt/data/nethack/save
chmod 0644 /mnt/data/nethack/{nhdat,symbols,license,sysconf}
chmod 0666 /mnt/data/nethack/{record,logfile}
```
The binary has its build-time `HACKDIR`/`SYSCF_FILE` path compiled in. Rather than match it, just
symlink it at the real playground:
```
mkdir -p "$(dirname <compiled HACKDIR>)"
ln -s /mnt/data/nethack <compiled HACKDIR>
```
(Find the compiled path by running `./nethack </dev/null` — it prints "Cannot chdir to …".)
You also need `libncursesw.so`/`terminfo` on the device (`opkg install libncurses6 terminfo`) — or
static-link ncurses as above.

## Bonus: play over SSH

A captive game account (everyone SSHes in as `hack` and lands straight in the game) is in
`sys/unix/openwrt-mips/play.sh`. Set the user's login shell to it, and harden `sysconf`
(`SHELLERS=root`) + `SHELL=/bin/false` so the `!` shell-escape can't pop a shell.

## Gotchas cheat-sheet

- **Endianness + word size of the version stamp** — the whole point (see TL;DR). Generate data &
  `date.h` on the target.
- **ncurses must be non-wide** for NetHack's `<curses.h>`; build with `--disable-widec`.
- **Don't run the cross `makedefs` on the host.** The Makefile's `date.h`/`onames.h` rules will try.
- **Compiled `HACKDIR`/`SYSCF_FILE` paths** are absolute and baked in → symlink them.
- **Playground must be writable** by the player (lock + level files are written into `HACKDIR`),
  but keep `sysconf` `0644` or SYSCF security rejects it.
