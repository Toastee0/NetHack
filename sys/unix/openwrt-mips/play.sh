#!/bin/sh
# Captive launcher for a public/lab "ssh to play NetHack" account.
# Make this the login shell of a dedicated unprivileged user (e.g. `hack`);
# on login it drops straight into the game and exits when the game does.
#
# Hardening (do this too):
#   - sysconf: set `SHELLERS=root` so players can't use NetHack's `!` shell-escape
#   - SHELL=/bin/false below is belt-and-suspenders for the same
export HOME=/mnt/data/nethack
export NETHACKDIR=/mnt/data/nethack
export SHELL=/bin/false
[ -z "$TERM" ] && export TERM=xterm
cd /mnt/data/nethack
exec ./nethack
