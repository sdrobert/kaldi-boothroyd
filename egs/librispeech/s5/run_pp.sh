#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

latlm=tgsmall # which lm to use to generate lattices
lm=tgmed      # which lm to use for computing perplexities/rescoring
mdl=tri4b     # which model to decode with
subparts=2    # number of partitions to split with perplexity

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

for x in \
    data/local/lm/lm_$lm.arpa.gz \
    data/lang_test_$latlm/G.fst \
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
  utils/mkgraph.sh data/lang_test_$lm $mdldir $graphdir

for part in dev_clean dev_other test_clean test_other; do
  partdir="data/$part"
  latdecodedir="$mdldir/decode_${latlm}_$part"
  decodedir="$mdldir/decode_${lm}_$part"
  perpdir="exp/${lm}_perp_${part}"

  # decode the entire partition in the usual way using the lattice lm
  if [ ! -f "$latdecodedir/.complete" ]; then
    steps/decode_fmllr.sh --nj 20 --cmd "$decode_cmd" \
      $graphdir $partdir $latdecodedir
    touch "$latdecodedir/.complete"
  fi

  # now rescore with the intended lm
  if [ ! -f "$decodedir/.complete" ]; then
    if [ -f "data/lang_test_$lm/G.fst" ]; then
        steps/lmrescore.sh --cmd "$decode_cmd" \
          data/lang_test_{$latlm,$lm} $partdir $latdecodedir $decodedir
    elif [ -f "data/lang_test_$lm/G.carpa" ]; then
      steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
        data/lang_test_{$latlm,$lm} $partdir $latdecodedir $decodedir
    else
      echo "neither G.fst nor G.carpa exists in data/lang_test_$lm"
      exit 1
    fi
    touch "$decodedir/.complete"
  fi

  # compute perplexity of utterance transcriptions 
  [ -f "$perpdir/perp" ] || \
    ./local/compute_perps.sh data/local/lm/lm_$lm.arpa.gz $partdir $perpdir
  
  # partition data directory by perplexity
  if [ ! -f "$perpdir/.split.$subparts" ]; then
    ./local/split_data_dir_by_perp.sh $partdir $perpdir $subparts
    touch "$perpdir/.split.$subparts"
  fi

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
      [ $ep = 0 ] || evaldir="${evaldir}_perp${ep}_${subparts}"
      ./utils/tuned_wer.sh "$tunedir" "$evaldir"
    done
  done
done
