#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

lm=tgsmall  # which lm to use for computing perplexities
mdl=tri4b   # which model to decode with
subparts=2  # number of partitions to split with perplexity

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

for x in \
    data/local/lm/lm_$lm.arpa.gz \
    data/lang_test_$lm/G.fst \
    exp/$mdl/final.mdl; do
  if [ ! -f "$x" ]; then
    echo "'$x' is not a file!"
    exit 1
  fi
done

set -e

mdldir="exp/$mdl"
graphdir="$mdldir/graph_$lm"
[ -f "$graphdir/HCLG.fst" ] || \
  utils/mkgraph.sh data/lang_test_$lm exp/$mdl

for part in dev_clean dev_other test_clean test_other; do
  partdir="data/$part"
  decodedir="$mdldir/decode_${lm}_$part"
  perpdir="exp/${lm}_perp_${part}"

  # decode the entire partition in the usual way
  if [ ! -f "$decodedir/.complete" ]; then
    steps/decode_fmllr.sh --nj 20 --cmd "$decode_cmd" \
      $graphdir $partdir $decodedir
    touch "$decodedir/.complete"
  fi

  # compute perplexity of utterance transcriptions 
  [ -f "$perpdir/perp" ] || \
    ./local/compute_perps.sh data/local/lm/lm_$lm.arpa.gz $partdir $perpdir
  
  # partition data directory by perplexity
  ./local/split_data_dir_by_perp.sh data/$part $perpdir $subparts

  # score only the utterances in each partition
  for (( p=1; p <= subparts; p+=1 )); do
    decodesubdir="${decodedir}_perp${p}_$subparts"
    if [ ! -f "$decodesubdir/.complete" ]; then
      ./local/score.sh --cmd "$decode_cmd" \
        $perpdir/split$subparts/$p $graphdir $decodedir $decodesubdir
      touch "$decodesubdir/.complete"
    fi
  done
done

# WERs
for (( tp=0; tp <= subparts; tp+=1 )); do  # tuning sub-part
  tunedir="$mdldir/decode_${lm}_dev_clean"
  [ $tp = 0 ] || tunedir="${tunedir}_perp${tp}_${subparts}"
  for (( ep=0; ep <= subparts; ep+=1 )); do  # eval sub-part
    for part in dev_clean dev_other test_clean test_other; do
      evaldir="$mdldir/decode_${lm}_$part"
      [ $ep = 0 ] || tunedir="${tunedir}_perp${ep}_${subparts}"
      steps/tuned_wer.sh "$tunedir" "$evaldir"
    done
  done
done
