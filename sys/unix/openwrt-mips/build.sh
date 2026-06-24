#!/bin/bash
# Cross-compile NetHack 3.6.7 for OpenWrt big-endian MIPS (mips_24kc, musl).
# Reference script documenting the real sequence — read OPENWRT-MIPS.md first.
# Not fully turnkey: the on-target data-generation step (5) must run on the device.
#
# Required env:
#   SDK   = path to the OpenWrt SDK (provides mips-openwrt-linux-gcc)
#   TARGET_HOST = user@device for the on-target data gen (optional convenience)
set -euo pipefail
: "${SDK:?set SDK to the OpenWrt SDK path}"
TC="$SDK/staging_dir/toolchain-mips_24kc_gcc-13.3.0_musl"
export STAGING_DIR="$SDK/staging_dir"
export PATH="$TC/bin:$PATH"
CC=mips-openwrt-linux-gcc
NH="$(cd "$(dirname "$0")/../../.." && pwd)"   # repo root
NCDIR="$NH/lib/ncurses-mips"                    # where we put the cross ncurses
# Game's full define set — the util tools MUST match this exactly (feeds version stamp)
DEFS='-DNOTPARMDECL -DDLB -DCOMPRESS="/bin/gzip" -DCOMPRESS_EXTENSION=".gz" -DSYSCF
      -DSYSCF_FILE="/usr/games/lib/nethackdir/sysconf" -DSECURE -DTIMED_DELAY
      -DHACKDIR="/usr/games/lib/nethackdir" -DDUMPLOG -DCONFIG_ERROR_SECURE=FALSE -DCURSES_GRAPHICS'

echo "### 1. cross-build ncurses (static, non-wide) ###"
# fetch ncurses.tar.gz into $NCDIR yourself, then:
( cd "$NCDIR" && CC=$CC AR=mips-openwrt-linux-ar RANLIB=mips-openwrt-linux-ranlib \
  ./configure --build=x86_64-linux-gnu --host=mips-openwrt-linux --with-build-cc=gcc \
    --disable-widec --without-cxx-binding --without-ada --without-tests \
    --without-progs --without-shared --without-manpages --disable-stripping --without-debug && make )

echo "### 2. native pass: host tools + arch-independent generated source ###"
( cd "$NH/sys/unix" && sh setup.sh hints/linux ) ; ( cd "$NH" && make all )   # discard native binary

echo "### 3. cross-compile the game ###"
sed -i "s#^CFLAGS=-g -O -I../include#CFLAGS=-g -O -I../include -I$NCDIR/include#" "$NH/src/Makefile"
sed -i "s#^WINTTYLIB=.*#WINTTYLIB=$NCDIR/lib/libncurses.a#" "$NH/src/Makefile"
sed -i "s#^WINCURSESLIB *=.*#WINCURSESLIB =#" "$NH/src/Makefile"
sed -i "s#^LFLAGS=-rdynamic#LFLAGS=#" "$NH/src/Makefile"
rm -f "$NH"/src/*.o
make -C "$NH/src" CC=$CC LINK=$CC \
  -o ../util/makedefs -o ../util/lev_comp -o ../util/dgn_comp -o ../util/dlb -o ../util/recover nethack
mips-openwrt-linux-strip "$NH/src/nethack"

echo "### 4. cross-compile util tools (linked by hand to dodge the makedefs-on-host recursion) ###"
( cd "$NH/util"
  for s in makedefs dgn_yacc dgn_lex dgn_main lev_yacc lev_lex lev_main dlb_main panic; do
    $CC -g -O -I../include $DEFS -c $s.c -o $s.o; done
  $CC -o makedefs makedefs.o ../src/monst.o ../src/objects.o
  $CC -o dgn_comp dgn_yacc.o dgn_lex.o dgn_main.o panic.o ../src/alloc.o
  $CC -o lev_comp lev_yacc.o lev_lex.o lev_main.o panic.o ../src/alloc.o ../src/drawing.o ../src/decl.o ../src/monst.o ../src/objects.o
  $CC -o dlb dlb_main.o ../src/dlb.o panic.o ../src/alloc.o )

cat <<EOF

### 5. RUN ON THE TARGET ###
  Copy util/{makedefs,dgn_comp,lev_comp,dlb}, dat/, and include/ to the device, then run
  sys/unix/openwrt-mips/gen-data.sh from the dat/ dir. It regenerates include/date.h with
  32-bit sanity values and emits big-endian dungeon/*.lev/nhdat. Copy date.h back here.

### 6. rebuild version.o against the target date.h and relink ###
  cp <date.h from target> $NH/include/date.h
  rm -f $NH/src/version.o
  make -C $NH/src CC=$CC LINK=$CC -o ../include/date.h -o ../util/makedefs ... nethack
  # also rebuild the util tools (step 4) with the new date.h, then re-run step 5.

Then deploy per OPENWRT-MIPS.md (Deploy).
EOF
