#!/bin/sh

fg=/home/bluhm/github/FlameGraph
file="${1:-kstack}"
host="${2:-ot14}"

# btrace -e 'profile:hz:100{@[kstack]=count()}' >~/"$file.dt" &
# sleep 60; kill -INT $!

ssh "$host" cat "$file.dt" | \
    $fg/stackcollapse-bpftrace.pl | \
    $fg/flamegraph.pl > \
    /data/test/files/"$host-$file.svg"

echo http://bluhm.genua.de/files/"$host-$file.svg"
