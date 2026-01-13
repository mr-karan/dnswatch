#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

shopt -s nullglob

BPF_DEVICES=(/dev/bpf*)
if [ "${#BPF_DEVICES[@]}" -eq 0 ]; then
    exit 0
fi

if dseditgroup -o read access_bpf >/dev/null 2>&1; then
    chgrp access_bpf "${BPF_DEVICES[@]}"
    chmod g+rw "${BPF_DEVICES[@]}"
else
    chmod o+rw "${BPF_DEVICES[@]}"
fi
