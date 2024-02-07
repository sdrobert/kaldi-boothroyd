#! /usr/bin/env bash

# Copyright 2024 Sean Robertson
# Apache 2.0

. path.sh

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <src-dir> <dst-dir>"
  echo "e.g.: $0 data/local/bn data"
fi

src="$1"
dst="$2"

parts=( "$src/"*.txt )
if [ "${#parts[@]}" = 0 ]; then
  echo "$0: No transcripts in '$src'!"
  exit 1
fi

set -eo pipefail

for part in "${parts[@]}"; do
  name="$(basename "$part" | cut -d '.' -f 1)"
  rdst="$dst/$name"
  mkdir -p "$rdst"
  awk \
      -v p=$name -v n=1 \
      '{utt=sprintf("%s-utt-%03d", p, n++); print utt, $0}' "$part" |
    tee "$rdst/text" |
    awk '{print $1,$1}' |
    tee "$rdst/spk2utt" > "$rdst/utt2spk"
  validate_data_dir.sh --no-feats --no-wav "$rdst"
done
