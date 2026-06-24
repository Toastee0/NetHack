#!/bin/sh
# Generate NetHack data files ON THE TARGET (big-endian MIPS), so the binary
# data + the regenerated include/date.h carry target-native version stamps.
# Run from the dat/ directory, with the cross-built util tools in ../util/ and
# the headers in ../include/.  Produces a native `dungeon`, `*.lev`, and `nhdat`.
cd "$(dirname "$0")"
U=../util
export LC_ALL=C
set -e

$U/makedefs -d            # data
$U/makedefs -r            # rumors
$U/makedefs -q            # quest.dat
$U/makedefs -h            # oracles
$U/makedefs -s            # engrave/epitaph/bogusmon
$U/makedefs -v            # options + (re)writes ../include/date.h with TARGET sanity values
$U/makedefs -e            # dungeon.pdf
$U/dgn_comp dungeon.pdf   # -> dungeon

for f in bigroom castle endgame gehennom knox medusa mines oracle sokoban tower yendor \
         Arch Barb Caveman Healer Knight Monk Priest Ranger Rogue Samurai Tourist Valkyrie Wizard; do
  $U/lev_comp $f.des
done

rm -f nhdat
$U/dlb cf nhdat help hh cmdhelp keyhelp history opthelp wizhelp dungeon tribute \
  asmodeus.lev baalz.lev bigrm-*.lev castle.lev fakewiz?.lev juiblex.lev knox.lev medusa-?.lev \
  minend-?.lev minefill.lev minetn-?.lev oracle.lev orcus.lev sanctum.lev soko?-?.lev tower?.lev \
  valley.lev wizard?.lev astral.lev air.lev earth.lev fire.lev water.lev \
  ???-goal.lev ???-fil?.lev ???-loca.lev ???-strt.lev \
  bogusmon data engrave epitaph oracles options quest.dat rumors

echo "GEN_DONE"; ls -la nhdat dungeon
