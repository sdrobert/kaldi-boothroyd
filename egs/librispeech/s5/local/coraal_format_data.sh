#! /usr/bin/env bash

# Copyright 2024 Sean Robertson
# Apache 2.0

. path.sh
delete_full=true

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <src-dir> <dst-dir>"
  echo "e.g.: $0 data/local/coraal data"
fi

src="$1"
dst="$2"

for x in wav.scp text utt2spk segments spk2gender; do
    if [ ! -f "$src/$x" ]; then
        echo "$src/$x doesn't exist! Exiting"
        exit 1
    fi
done

set -eo pipefail

mkdir -p "$dst/coraal"


# construct entire corpus partition
for x in wav.scp text utt2spk segments spk2gender; do
    cp -f "$src/$x" "$dst/coraal/$x"
done
utt2spk_to_spk2utt.pl "$dst/coraal/utt2spk" > "$dst/coraal/spk2utt"
validate_data_dir.sh --no-feats "$dst/coraal"

# regional partitions
for x in "$src/utts_from_"*; do
    rdst="$dst/$(echo "$x" | cut -d '_' -f 3)"
    subset_data_dir.sh --utt-list "$x" "$dst/coraal" "$rdst"
    validate_data_dir.sh --no-feats "$rdst"
done

if $delete_full; then
    rm -rf "$dst/coraal"
fi
