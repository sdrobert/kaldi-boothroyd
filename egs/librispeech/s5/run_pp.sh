#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

exp=exp        # experiment directory
data=data      # data directory
mfcc=mfcc      # mfcc (and other feat archive) directory
perplm=rnnlm_lstm_1a # which lm to use to compute perplexities
latlm=tgsmall  # which lm to use to generate lattices
reslm=tgsmall  # which lm to use for lattice rescoring
mdl=tri6b      # which model to decode with
part=dev_clean # partition to perform 
snr_low=3    # lower bound (inclusive) of signal-to-noise ratio (SNR)
snr_high=3     # upper bound (inclusive) of signal-to-noise ratio (SNR)
subparts=2     # number of partitions to split with perplexity
pretrained_store=/ais/hal9000/sdrobert/librispeech_models  # where pretrained models are downloaded to
pretrained_url=https://kaldi-asr.org/models/13  # where to download pretrained models from

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

declare -A MNAME2PNAME=(
  ["rnnlm_lstm_1a"]="0013_librispeech_v1_lm"
  ["chain_cleaned/tdnn_1d_sp"]="0013_librispeech_v1_chain"
)

set -e

for mname in "$mdl" "$reslm" "$perplm"; do
  pname="${MNAME2PNAME[$mname]}"
  if [ ! -z "$pname" ] && [ ! -f "$exp/$mname/.downloaded" ]; then
    echo "$0: $mname corresponds to pretrained model $pname. Downloading and extracting"
    mkdir -p "$pretrained_store" "$exp/$mname"
    ./local/download_pretrained_models.sh \
      "$pretrained_store" "$pretrained_url" "$pname"
    cp -r "$pretrained_store/exp/$mname/"* "$exp/$mname"
    touch "$exp/$mname/.downloaded"
  fi
done


perplm_is_rnn() [[ "$perplm" =~ rnnlm ]]
reslm_is_rnn() [[ "$reslm" =~ rnnlm ]]
latlm_is_reslm() [[ "$reslm" = "$latlm" ]]
mdl_is_tdnn() [[ "$mdl" =~ tdnn ]]
mdldir="$exp/$mdl"
graphdir="$mdldir/graph_$latlm"

if mdl_is_tdnn; then
  echo "$0: tdnn decoding not yet implemented!"
  exit 1
fi

needed_files=(
  $exp/$mdl/final.mdl $data/lang_test_$latlm/G.fst
  $data/$part/{text,wav.scp,feats.scp,cmvn.scp}
)
if ! latlm_is_reslm; then
  if reslm_is_rnn; then
    needed_files+=( "$exp/$reslm/final.raw" )
  else
    if [ ! -f "$exp/$reslm/G.fst" ]; then 
      needed_files+=( "$exp/$reslm/G.carpa" )
    fi
  fi
fi
if perplm_is_rnn; then
  needed_files+=( "$exp/$perplm/final.raw" )
else
  needed_files+=( "$data/local/lm_$perplm.arpa.gz" )
fi
for x in "${needed_files[@]}"; do
  if [ ! -f "$x" ]; then
    echo "$0: '$x' is not a file!"
    exit 1
  fi
done

if [ ! -f "$graphdir/HCLG.fst" ]; then
  if mdl_is_tdnn; then
    utils/mkgraph.sh --self-loop-scale 1.0 \
      "$data/lang_test_$latlm" "$mdldir" "$graphdir"
  else
    utils/mkgraph.sh "$data/lang_test_$latlm" "$mdldir" "$graphdir"
  fi
fi

npart="${part}_norm"
parts=( $npart )

# Normalize data volume to same reference average RMS
if [ ! -f "$data/$npart/.complete" ]; then
  ./local/normalize_data_volume.sh "$data/$part" "$data/$npart"
  ./steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 \
      $data/$npart $exp/make_mfcc/$npart $mfcc
  steps/compute_cmvn_stats.sh $data/$npart $exp/make_mfcc/$npart $mfcc
  touch "$data/$npart/.complete"
fi

# compute perplexity of utterance transcriptions.
# we do this only once per part and copy across SNRs b/c the perplexity
# doesn't change
if [ ! -f "$exp/${perplm}_perp_${part}/perp" ]; then
  if perplm_is_rnn; then
    ./local/compute_perps_rnnlm.sh \
      "$exp/$perplm" "$data/$part" "$exp/${perplm}_perp_${part}/perp"
  else
    ./local/compute_perps.sh \
      "$data/local/lm/lm_$lm.arpa.gz" "$data/$part" \
      "$exp/${perplm}_perp_${part}/perp"
  fi
fi

for snr in $(seq $snr_low $snr_high); do
  spart="${part}_snr$snr"
  if [ ! -f "$data/$spart/.complete" ]; then
    # add noise at specific SNR, then compute feats + cmvn
    ./local/add_noise.sh $data/$npart $snr $data/$spart $mfcc
    ./steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 \
      $data/$spart $exp/make_mfcc/$spart $mfcc
    steps/compute_cmvn_stats.sh $data/$spart $exp/make_mfcc/$spart $mfcc
    mkdir -p "$exp/${perplm}_perp_${spart}"
    cp -f "$exp/${perplm}_perp_${part}/perp" "$exp/${perplm}_perp_${spart}/perp"
    touch "$data/$spart/.complete"
  fi
  parts+=( $spart )
done

for spart in "${parts[@]}"; do
  partdir="$data/$spart"
  latdecodedir="$mdldir/decode_${latlm}_$spart"
  if latlm_is_reslm; then
    decodedir="$latdecodedir"
  else
    decodedir="$mdldir/decode_${latlm}_rescore_${reslm}_$spart"
  fi
  perpdir="$exp/${perplm}_perp_${part}"

  # decode the entire partition in the usual way using the lattice lm
  if [ ! -f "$latdecodedir/.complete" ]; then
    steps/decode_fmllr.sh --nj 20 --cmd "$decode_cmd" \
      "$graphdir" "$partdir" "$latdecodedir"
    touch "$latdecodedir/.complete"
  fi

  # now rescore with the intended lm
  if [ ! -f "$decodedir/.complete" ]; then
    if reslm_is_rnn; then
      steps/rnnlmrescore.sh --N 100 0.5 \
        $data/lang_test_$latlm "$exp/$reslm" "$partdir" $latdecodedir $decodedir
    else
      if [ -f "$data/lang_test_$reslm/G.fst" ]; then
          steps/lmrescore.sh --cmd "$decode_cmd" \
            $data/lang_test_{$latlm,$reslm} $partdir $latdecodedir $decodedir
      else
        steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
          $data/lang_test_{$latlm,$reslm} $partdir $latdecodedir $decodedir
      fi
    fi
    touch "$decodedir/.complete"
  fi

  if [ ! -f "$decodedir/wer_best" ]; then
    grep WER "$decodedir/"wer* |
      utils/best_wer.sh > "$decodedir/wer_best"
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

    if [ ! -f "$decodesubdir/wer_best" ]; then
       grep WER "$decodesubdir/"wer* |
        utils/best_wer.sh > "$decodesubdir/wer_best"
    fi
  done
done

find "$exp/" -name 'wer_best' -exec cat {} \;