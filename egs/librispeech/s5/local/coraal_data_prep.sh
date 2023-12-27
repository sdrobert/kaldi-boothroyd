#! /usr/bin/env bash

# Copyright 2024 Sean Robertson

confdir="conf"

. ./utils/parse_options.sh
. ./path.sh

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 [options] <src-dir> <dst-dir>"
  echo "e.g.: $0 /ais/hal9000/sdrobert/coraal data/local/coraal"
  echo "Options:"
  echo " --confdir <dir>"
fi

src="$1"
dst="$2"

if [[ " " =~ "$dst" ]]; then
    echo "$0: $dst contains spaces"
    exit 1
fi

for x in coraal_spk2reco; do
    if [ ! -f "$confdir/$x" ]; then
        echo "$0: '$confdir/$x' is not a file!"
        exit 1
    fi
done

check_for_unpaired_utts() {
    a="$1"
    b="$2"
    fail="${3:-true}"
    alen=$(cat "$a" | wc -l)
    blen=$(filter_scp.pl $a $b | wc -l)
    if [ $alen != $blen ]; then
        echo "File $a has unmatched utterances in $b"
        echo "diff $a $b:"
        diff <(cut -d ' ' -f 1 $a) <(cut -d ' ' -f 1 $b) || true
        if $fail; then
            return 1
        fi
    fi
    return 0
}

set -eo pipefail

mkdir -p $dst

# remove comments and empty lines
cut -d '#' -f 1 "$confdir/coraal_spk2reco" |
    sed '/^ *$/d' | sort > $dst/spk2reco

# reverse spk2reco map
cat $dst/spk2reco | spk2utt_to_utt2spk.pl > $dst/reco2spk

# compile a list of files in the source directory ending with {wav,txt}
for x in wav txt; do
    find "$src" -name "*.$x" -and -not -name '._*' |
        sed -rn 's:.*/([^/.]+)\.'$x':\1 \0:p' |
        sort > $dst/${x}list
done

# make sure all wav files have transcriptions
check_for_unpaired_utts $dst/{wav,txt}list

# make sure all recordings have wav files
check_for_unpaired_utts $dst/{reco2spk,wavlist}