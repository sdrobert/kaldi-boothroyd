#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

cleanup=false

echo "$0: $*"

. utils/parse_options.sh

if [ $# -lt 3 ] && [ $# -gt 5 ]; then
  echo "Usage: $0 [opts] <data-dir> <perp-dir> <num-to-split> [<dir> [<tmpdir>]]"
  echo "e.g: $0 data/dev_clean exp/3-gram_perp_dev_clean 2"
  echo ""
  echo "Creates data splits in the perp-dir with the pattern"
  echo "  <dir>/<cur-split>"
  echo "With ascending <cur-split> (1 to <num-to-split) corresponding to "
  echo "ascending per-utterance perplexity"
  echo "<out-dir> defaults to <perp-dir>/split<num-to-split>"
  echo ""
  echo "Options"
  echo "--cleanup (true|false)"
  exit 1
fi

data="$1"
exp="$2"
ns="$3"
dir="${4:-"$exp/split${ns}"}"
tmpdir="${5:-"$dir/tmp"}"

export LC_ALL=C

for x in "$data/wav.scp" "$exp/perp"; do
  if [ ! -f "$x" ]; then
    echo "'$x' is not a file"
    exit 1
  fi
done

nw="$(cat "$data/wav.scp" | wc -l)"
np="$(./utils/filter_scp.pl "$exp/perp" "$data/wav.scp" | wc -l)"
if [ "$nw" -ne "$np" ]; then
  echo "$data/wav.scp and $exp/perp have different utterances (or maybe unordered)!"
  echo "diff is:"
  diff <(cut -d ' ' -f 1 "$data/wav.scp") <(cut -d ' ' -f 1 "$exp/perp")
  exit 1
fi

set -eo pipefail

mkdir -p "$dir" "$tmpdir"

sort -k 2n -k 1 "$exp/perp" > "$tmpdir/perp_sorted"

echo -n "" > "$tmpdir/split_wav.scp"
for (( n=1; n <= $ns; n+=1 )); do
  rm -rf "$tmpdir/$n"
  utils/split_scp.pl -j $ns $((n - 1)) "$tmpdir/perp_sorted" |
    sort > "$tmpdir/uttlist.$n"
  utils/subset_data_dir.sh --utt-list "$tmpdir/uttlist.$n" "$data" "$tmpdir/$n"
  cat "$tmpdir/$n/wav.scp" >> "$tmpdir/split_wav.scp"
done

sort "$tmpdir/split_wav.scp" > "$tmpdir/split_wav_sorted.scp"
if ! diff "$tmpdir/split_wav_sorted.scp" "$data/wav.scp" 2> /dev/null; then
  echo "$0: $tmpdir/split_wav_sorted.scp and $data/wav.scp differ!"
  echo "diff is:"
  diff "$tmpdir/split_wav_sorted.scp" "$data/wav.scp"
  exit 1
fi

for (( n=1; n <= $ns; n+=1 )); do
  mkdir -p "$dir/$n"
  cp "$tmpdir/$n/"* "$dir/$n/"
done

! $cleanup || rm -rf "$tmpdir"
