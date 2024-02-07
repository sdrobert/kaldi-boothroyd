#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

exp=exp        # experiment directory
data=data      # data directory
perplm=rnnlm_lstm_1a # which lm to use to compute perplexities
part=dev_clean # partition to perform 
pretrained_store=/ais/hal9000/sdrobert/librispeech_models  # where pretrained models are downloaded to
pretrained_url=https://kaldi-asr.org/models/13  # where to download pretrained models from

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

declare -A MNAME2PNAME=(
  ["rnnlm_lstm_1a"]="0013_librispeech_v1_lm"
  ["chain_cleaned/tdnn_1d_sp"]="0013_librispeech_v1_chain"
  ["nnet3_cleaned/extractor"]="0013_librispeech_v1_extractor"
)

set -eo pipefail

for mname in "$perplm"; do
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

needed_files=( $data/$part/text )
if [[ "$perplm" =~ rnnlm ]]; then
  needed_files+=( "$exp/$perplm/final.raw" )
else
  needed_files+=( "$data/local/lm/lm_$perplm.arpa.gz" )
fi
for x in "${needed_files[@]}"; do
  if [ ! -f "$x" ]; then
    echo "$0: '$x' is not a file!"
    exit 1
  fi
done

# compute perplexity of utterance transcriptions.
# we do this only once per part and copy across SNRs b/c the perplexity
# doesn't change
if [ ! -f "$exp/${perplm}_perp_${part}/perp" ]; then
  if [[ "$perplm" =~ rnnlm ]]; then
    ./local/compute_perps_rnnlm.sh \
      "$exp/$perplm" "$data/$part" "$exp/${perplm}_perp_${part}"
  else
    ./local/compute_perps.sh \
      "$data/local/lm/lm_$perplm.arpa.gz" "$data/$part" \
      "$exp/${perplm}_perp_${part}"
  fi
fi
