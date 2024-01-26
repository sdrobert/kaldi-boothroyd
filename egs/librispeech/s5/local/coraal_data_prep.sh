#! /usr/bin/env bash

# Copyright 2024 Sean Robertson
# FIXME(sdrobert): age groups are not standardized. Maybe should re-code them

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

for x in coraal_recos; do
    if [ ! -f "$confdir/$x" ]; then
        echo "$0: '$confdir/$x' is not a file!"
        exit 1
    fi
done

if ! which sox > /dev/null; then
    echo "sox is not available!"
    exit 1
fi

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

mkdir -p $dst/links

# remove comments and empty lines
cut -d '#' -f 1 "$confdir/coraal_recos" |
    sed '/^ *$/d' | sort > $dst/recos

# compile a list of files in the source directory ending with {wav,txt}
for x in wav txt; do
    find "$src" -name "*.$x" -and -not -name '._*' |
        sed -rn 's:.*/([^/.]+)\.'$x':\1 \0:p' |
        sort > $dst/${x}list
done

# make sure all wav files have transcriptions
check_for_unpaired_utts $dst/{wav,txt}list

# make sure all recordings have wav files
check_for_unpaired_utts $dst/{recos,wavlist}

# report any wav files missing from recording list. This could be because of
# updates to CORAAL that we haven't integrated yet.
check_for_unpaired_utts $dst/{wavlist,recos} false

# construct soft links to wav files in order to avoid spaces in wav.scp
cut -d ' ' -f 2- $dst/wavlist |
    xargs -P4 -I % bash -c '
bn=$(basename "$1")
src="$(cd "$(dirname "$1")"; pwd -P)/$bn"
ln -sf "$src" $2/$bn' -- % $dst/links

# sanitize all transcripts and write to stm file
filter_scp.pl $dst/{wav,txt}list |
    cut -d ' ' -f 2 |
    xargs -P 8 -I % local/coraal_txt_to_ctm.py % |
    sort +0 -1 +1 -2 +3nb -4 > $dst/stm

# spk2gender file
paste -d ' ' \
        <(cut -d ' ' -f 3 $dst/stm) <(cut -d '_' -f 9 $dst/stm) |
    sort -u > $dst/spk2gender

# build segment and transcripts files from stm
#
# utterance IDs take the form
#
#   <spkr>_<reco>_<start_cs>_<end_cs>
#   e.g. ATL_se0_ag1_f_01_ATL_se0_ag1_f_01_1_000044_000241
#
# where "cs" is centiseconds.
#
# The speaker/recording looks a bit redundant, except that speakers other than
# the primary speaker can be speaking in the same file.
awk '{
    start_cs=$4 * 100; end_cs=$5 * 100;
    printf "%s_%s_%06.0f_%06.0f %s %04.02f %04.02f", $3, $1, start_cs, end_cs, $1, $4, $5;
    for (i=6; i <= NF; ++i) printf " %s", $i;
    printf "\n";
}' $dst/stm |
    tee >(cut -d ' ' -f 1-4 | sort > $dst/segments) |
    cut -d ' ' -f 1,5- | sort > $dst/text

# get list of recordings (with at least one utterance)
cut -d ' ' -f 2 $dst/segments | sort -u > $dst/recos

# construct wav.scp (remix down to 16kHz, single channel)
cut -d ' ' -f 1 $dst/wavlist |
    awk -v d=$dst/links '{
print $1, "sox "d"/"$1".wav -t wav -b 16 - rate 16k remix 1 |"
}' |
    filter_scp.pl $dst/recos > $dst/wav.scp

# utt2spk file
paste -d ' ' \
      <(cut -d ' ' -f 1 $dst/segments) <(cut -d '_' -f 1-5 $dst/segments) \
      > $dst/utt2spk

# utterances by region
for x in $(cut -d _ -f 1 $dst/utt2spk | sort -u); do
    cut -d ' ' -f 1 $dst/utt2spk | grep '^'"$x"'_' > $dst/utts_from_$x
done