#! /usr/bin/env bash

# Copyright 2023 Sean Robertson

echo "$0: $*"

. ./path.sh
. utils/parse_options.sh

if [ $# -ne 2 ]; then
  echo "Usage: $0 <lang-or-graph-dir> <scoring-dir>"
  echo "e.g. $0 exp/tri6b/{graph_tgsmall,decode_tgsmall_dev_clean_norm/scoring}"
  exit 1
fi

gdir="$1"
sdir="$2"

echo "$gdir" "$sdir"

symtab="$gdir/words.txt"
ref="$sdir/test_filt.txt"
tra_files=( "$sdir/"*.tra )

for x in "$symtab" "$ref"; do
  if [ ! -f "$x" ]; then
     echo "$0: $x is not a file!"
     exit 1
  fi
done

if [ "${#tra_files[@]}" = 0 ]; then
  echo "$0: no .tra files in $gdir!"
  exit 1
fi

set -eo pipefail

for tra_file in "${tra_files[@]}"; do
  wer_file="${tra_file%.tra}.uttwer"
  utils/int2sym.pl -f 2- "$symtab" "$tra_file" |
    sed 's:\<UNK\>::g' |
    align-text "ark:$ref" "ark:-" "ark,t:-" |
    ./utils/scoring/wer_per_utt_details.pl \
      --nooutput-ref --nooutput-hyp --nooutput-ops |
    awk '
{
  wer=sprintf("%.02f", 100 * ($4 + $5 + $6) / ($3 + $4 + $6));
  print $1,wer
}' > "$wer_file" &
done
wait
