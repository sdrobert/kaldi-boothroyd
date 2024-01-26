#! /usr/bin/env bash

# Copyright 2024 Sean Robertson
# Apache 2.0

echo "$0 $@"

cmd=run.pl
nj=1
pretrained=pretrained
use_gpu=true

. ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 4 ]; then
  echo "Usage: $0 [options] <lang-or-graph-dir> <data-dir> <mdl> <decode-dir>"
  echo "e.g. $0 data/dev_clean data/lang facebook/wav2vec2-base-960h"
  echo "          exp/facebook/wav2vec2-base-960h/decode_dev_clean"
  echo ""
  echo "Options"
  echo " --pretrained <dir>  Where to save pretrained model checkpoints"
  exit 1
fi

lang_or_graph=$1
data=$2
mdl=$3
dir=$4

symtab=$lang_or_graph/words.txt
oov=$lang_or_graph/oov.txt

for x in "$data/"{wav.scp,text} $symtab $oov; do
  if [ ! -f "$x" ]; then
    echo "$0: '$x' is not a file"
  fi
done

set -e

mkdir -p "$pretrained" "$dir/scoring" "$dir/log"

device=cpu
if $use_gpu; then
  device=cuda
fi

sdata=$data/split$nj
wav=scp:$sdata/JOB/wav.scp
if [ -f "$data/segments" ]; then
    wav="ark:extract-segments $wav $sdata/JOB/segments ark:- |"
fi

split_data.sh $data $nj

rm -f $dir/*.txt
$cmd JOB=1:$nj $dir/log/decode.JOB.log \
  ./local/transformer/decode_transformer.py --device=$device "$wav" "$mdl" \
  "ark,t:$dir/JOB.txt"

cat $dir/*.txt |
  sort -k 1,1 -u |
  sym2int.pl --map-oov "$(cat $oov)" -f 2- $symtab > $dir/scoring/1.1.tra

local/score.sh \
  --stage 1 --word-ins-penalty 1 \
  --min-lmwt 1 --max-lmwt 1 \
  $data $lang_or_graph $dir