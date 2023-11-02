#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

if [ $# -ne 1 ] && [ $# -ne 2 ]; then
  echo "Usage: $0 <tune-dir> [<eval-dir>]"
  echo "e.g. $0 exp/tri6b/decode_tgsmall_{dev,test}_clean"
  echo ""
  echo "Prints the WER in <eval-dir> of the model/hyperparameters which lead "
  echo "to the lowest WER in <tune-dir>. WERs are expected to be stored in "
  echo "the files matching the pattern"
  echo "  <dir>/wer*"
  echo "e.g."
  echo "  exp/tri6b/decode_tgsmall_dev_clean/wer_14_0.5"
  echo "where such files are one-to-one between <tune-dir> and <eval-dir>."
  echo "If <eval-dir> is unspecified, it is set to <tune-dir>"
  exit 1
fi

tdir="$1"
edir="${2:-"$1"}"

for x in "$tdir" "$edir"; do
  if ! ls "$x/wer"* 2>&1 > /dev/null; then
    echo "No files matching $x/wer* exist"
    exit 1
  fi
done

set -eo pipefail

best_tdir_wer="$(grep WER "$tdir/wer"* | utils/best_wer.sh)"
best_param="${best_tdir_wer##*/}"
if [ ! -f "$edir/$best_param" ]; then
  echo "Best param in $tdir was $best_param, but not in $edir"
  exit 1
fi
echo "$(grep WER "$edir/$best_param") (tuned on $tdir)"
