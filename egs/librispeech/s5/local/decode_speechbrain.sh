#! /usr/bin/env bash

# Copyright 2024 Sean Robertson
# Apache 2.0

echo "$0 $@"

pretrained=pretrained

. ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 4 ]; then
  echo "Usage: $0 [options] <data-dir> <lang-or-graph-dir> <mdl> <decode-dir>"
  echo "e.g. $0 data/dev_clean data/lang speechbrain/asr-crdnn-rnnlm-librispeech"
  echo "          exp/speechbrain/asr-crdnn-rnnlm-librispeech/decode_dev_clean"
  echo ""
  echo "Options"
  echo " --pretrained <dir>  Where to save pretrained model checkpoints"
  exit 1
fi

data=$1
lang_or_graph=$2
mdl=$3
dir=$4

symtab=$lang_or_graph/words.txt

for x in "$data/"{wav.scp,text} $symtab; do
  if [ ! -f "$x" ]; then
    echo "$0: '$x' is not a file"
  fi
done

set -e

mkdir -p "$pretrained" "$dir/scoring"

wav=scp:$data/wav.scp
if [ -f "$data/segments" ]; then
    wav="ark:extract-segments $wav $data/segments ark:- |"
fi

./local/decode_speechbrain.py \
  --sb-name $3 --model-dir $pretrained "$wav" "$dir/scoring/0.0/.tra"
