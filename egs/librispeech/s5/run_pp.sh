#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

pretrained_dir=/ais/hal9000/sdrobert/kaldi_libri_models/
latlm=tgsmall # which lm to use to generate lattices
lm=tgsmall    # which lm to use for computing perplexities/rescoring
mdl=tri6b     # which model to decode with
suffix=       # clean, other or empty for clean + other
snr_low=-12   # lower bound (inclusive) of signal-to-noise ratio (SNR)
snr_high=3    # upper bound (inclusive) of signal-to-noise ratio (SNR)
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

if [ ! -z "$suffix" ] && \
   [ "$suffix" != "_clean" ] && \
   [ "$suffix" != "_other" ]; then
  echo "--suffix must be empty or one of _clean, _other"
  exit 1
fi

set -e

mdldir="exp/$mdl"
graphdir="$mdldir/graph_$latlm"
[ -f "$graphdir/HCLG.fst" ] || \
  utils/mkgraph.sh data/lang_test_$latlm $mdldir $graphdir

parts=( dev$suffix test$suffix )
for part in "${parts[@]}"; do
  npart="${part}_norm"

  # combine clean + other (if applicable)
  if [ -z "$suffix" ] && [ ! -f "data/$part/.complete" ]; then
    ./utils/combine_data.sh "data/$part"{,_clean,_other}
    touch data/$part/.complete
  fi

  # Normalize data volume to same reference average RMS
  if [ ! -f "data/$npart/.complete" ]; then
    ./local/normalize_data_volume.sh "data/$part" "data/$npart"
    touch "data/$npart/.complete"
  fi

  # compute perplexity of utterance transcriptions.
  # we do this only once per part and copy across SNRs b/c the perplexity
  # doesn't change
  [ -f "exp/${lm}_perp_${part}/perp" ] || \
    ./local/compute_perps.sh data/local/lm/lm_$lm.arpa.gz data/$part "exp/${lm}_perp_${part}/perp"

  for snr in $(seq $snr_low $snr_high); do
    spart="${part}_snr$snr"
    if [ ! -f "data/$spart/.complete" ]; then
      # add noise at specific SNR, then compute feats + cmvn
      ./local/add_noise.sh data/$npart $snr data/$spart mfcc
      ./steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 data/$spart exp/make_mfcc/$spart mfcc
      steps/compute_cmvn_stats.sh data/$spart exp/make_mfcc/$spart mfcc
      mkdir -p "exp/${lm}_perp_${spart}"
      cp -f "exp/${lm}_perp_${part}/perp" "exp/${lm}_perp_${spart}/perp"
      touch "data/$spart/.complete"
    fi
    parts+=( $spart )
  done
done

for part in "${parts[@]}"; do
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
  tunedir="$mdldir/decode_${lm}_dev"
  [ $tp = 0 ] || tunedir="${tunedir}_perp${tp}_${subparts}"
  for (( ep=0; ep <= subparts; ep+=1 )); do  # eval sub-part
    for part in "${parts[@]}"; do
      evaldir="$mdldir/decode_${lm}_$part"
      [ $ep = 0 ] || evaldir="${evaldir}_perp${ep}_${subparts}"
      ./utils/tuned_wer.sh "$tunedir" "$evaldir"
    done
  done
done
