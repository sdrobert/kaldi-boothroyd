#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

# borrows from local/rnnlm/compute_perplexity.sh

# compute per-sentence perplexity of RNNLM

cmd=run.pl
nj=1
cleanup=true
use_gpu=optional

echo "$0: $*"

. ./path.sh
. utils/parse_options.sh

if [ $# -lt 3 ] || [ $# -gt 5 ]; then
  echo "Usage: $0 [opts] <rnn-dir> <data-dir> <exp-dir> [<log-dir> [<tmpdir>]]"
  echo "e.g.: $0 exp/rnnlm_lstm_1a data/dev_clean exp/rnnlm_lstm_1a_perp_dev_clean"
  echo ""
  echo "Options"
  echo "--cmd <cmd>"
  echo "--nj N"
  echo "--cleanup (true|false)"
  echo "--use_gpu (yes|no|optional|wait)"
  exit 1
fi

lmdir="$1"
data="$2"
exp="$3"
logdir="${4:-"$exp/log"}"
tmpdir="${5:-"$exp/tmp"}"

set -eo pipefail


for x in \
    "$lmdir/"{final.raw,config/words.txt,special_symbol_opts.txt} \
    "$data/text"; do
  if [ ! -f "$x" ]; then
    echo "'$x' is not a file"
    exit 1
  fi
done

./utils/validate_data_dir.sh --no-feats --no-wav "$data"
utils/split_data.sh --per-utt "$data" "$nj"

mkdir -p "$exp" "$tmpdir" "$logdir"

word_embedding="$lmdir/word_embedding.final.mat"
if [ ! -f "$word_embedding" ]; then
  if [ ! -f "$lmdir/feat_embedding.final.mat" ] || \
      [ ! -f "$lmdir/word_feats.txt" ]; then
    echo "$0: neither word_embedding.final.mat nor both"
    echo "{feat_embedding.final.mat,word_feats.txt} exist in $lmdir; exiting"
    exit 1
  fi
  echo "$0: $word_embedding doesn't exist; generating"
  rnnlm-get-word-embedding \
    "$lmdir/"{word_feats.txt,feat_embedding.final.mat} \
    "$tmpdir/word_embedding.final.mat"
  mv "$tmpdir/word_embedding.final.mat" "$word_embedding"
fi

opts="--normalize-probs=true --use-gpu=${use_gpu}"
opts="$opts $(cat "$lmdir/special_symbol_opts.txt")"

map_oov=
if [ -f "$lmdir/config/oov.txt" ]; then
  map_oov="--map-oov $(cat "$lmdir/config/oov.txt")"
fi

utils/split_data.sh "$data" "$nj"

for (( n=1; n <= $nj; n+= 1 )); do
  utils/sym2int.pl $map_oov -f 2- \
    "$lmdir/config/words.txt" "$data/split$nj/$n/text">  "$tmpdir/textint.$n"
done

$cmd JOB=1:$nj $logdir/compute_perps_rnnlm.JOB.log \
  rnnlm-sentence-probs $opts "$lmdir/final.raw" "$word_embedding" \
    "$tmpdir/textint.JOB"  \> "$tmpdir/logprobs.JOB"

for (( n=1; n <= $nj; n+= 1 )); do
  awk '{a=0; for(i=2;i<=NF;i++) a+=$i; print $1, exp(-a / (NF - 1))}' \
    "$tmpdir/logprobs.$n"
done > "$tmpdir/perp"


if [ -f "$data/segments" ]; then
  w="$data/segments"
else
  w="$data/text"
fi
nw="$(cat "$w" | wc -l)"
np="$(./utils/filter_scp.pl "$tmpdir/perp" "$w" | wc -l)"
if [ "$nw" -ne "$np" ]; then
  echo "$w and $tmpdir/perp have different utterances (or maybe unordered)!"
  echo "diff is:"
  diff <(cut -d ' ' -f 1 "$w") <(cut -d ' ' -f 1 "$tmpdir/perp")
  exit 1
fi

cp "$tmpdir/perp" "$exp/"

! $cleanup || rm -rf "$tmpdir"
