#! /usr/bin/env bash

set -e

# compute perplexity of utterance transcriptions 
for part in dev_clean dev_other test_clean test_other; do
  perp_dir="exp/perp_$part"
  for lm in 3-gram 4-gram fglarge tglarge; do
    perp_lm_dir="$perp_dir/$lm"
    if [ ! -f "$perp_lm_dir/.complete" ]; then
      ./local/compute_perps.sh data/local/lm/$lm.arpa.gz data/$part "$perp_lm_dir"
      touch "$perp_lm_dir/.complete"
    fi
  done
done