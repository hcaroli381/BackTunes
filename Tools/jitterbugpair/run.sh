#!/usr/bin/env bash
# Runs jitterbugpair with the bundled libplist.so.3 (Fedora ships a newer,
# incompatible one). Plug the iPhone in, unlock it, accept the Trust dialog,
# then run:  ./Tools/jitterbugpair/run.sh
set -e
cd "$(dirname "$0")"
exec env LD_LIBRARY_PATH="$PWD/lib" ./jitterbugpair "$@"
