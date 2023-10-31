#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

# compute per-sentence perplexity of ARPA models

cmd=run.pl
nj=8
cleanup=true

echo "$0: $*"

. ./path.sh
. utils/parse_options.sh

if [ $# -lt 3 ] || [ $# -gt 5 ]; then
  echo "Usage: $0 [opts] <ngram-lm> <data-dir> <exp-dir> [<log-dir> [<tmpdir>]]"
  echo "e.g.: $0 data/local/lm/3-gram.arpa.gz data/dev_clean exp/3-gram_perp"
  echo ""
  echo "Options"
  echo "--cmd <cmd>"
  echo "--nj N"
  echo "--cleanup (true|false)"
  exit 1
fi

lm="$1"
data="$2"
exp="$3"
logdir="${4:-"$exp/log"}"
tmpdir="${5:-"$exp/tmp"}"

for x in "$lm" "$data/text"; do
  if [ ! -f "$x" ]; then
    echo "'$x' is not a file"
    exit 1
  fi
done

set -e

# utils/split_data.sh "$data" "$nj"

mkdir -p "$exp" "$tmpdir" "$logdir"

$cmd JOB=1:$nj $logdir/compute_perps.JOB.log \
  python -c '
import sys
import kenlm
lm_pth, txt_pth = sys.argv[1:3]
total_logprob = 0
total_toks = 0
line_no = -1
print(f"loading lm {lm_pth}...", file=sys.stderr)
model = kenlm.Model(lm_pth)
print("loaded", file=sys.stderr)
with open(txt_pth) as txt:
  for line_no, line in enumerate(txt):
    try:
      utt_id, sent = line.split(maxsplit=1)
    except:
      print(f"parsing line {line_no + 1} failed", file=sys.stderr)
      sys.exit(1)
    cur_toks = len(sent.split()) + 1  # +1 for eos
    total_toks += cur_toks
    cur_logprob = model.score(sent)
    total_logprob += cur_logprob
    cur_pp = 10 ** (-cur_logprob / cur_toks)
    print(f"{utt_id} {cur_pp:.3f}")
print(f"processed {line_no + 1} utterances and {total_toks} tokens", file=sys.stderr)
total_pp = 10 ** (-total_logprob / total_toks)
print(f"total perplexity: {total_pp}", file=sys.stderr)
' "$lm" "$data/split$nj/JOB/text" \> "$tmpdir/perp.JOB"

for (( n=1; n <= $nj; n+= 1 )); do
  cat "$tmpdir/perp.$n"
done > "$tmpdir/perp"

cut -d ' ' -f 1 "$data/text" > "$tmpdir/uttlist_text"
cut -d ' ' -f 1 "$tmpdir/perp" > "$tmpdir/uttlist_perp"

if ! diff "$tmpdir/uttlist_"{text,perp} 2> /dev/null; then
  echo "Utterance list of perp file doesn't match transcript!"
  echo "diff is:"
  diff "$tmpdir/uttlist_"{text,perp}
  exit 1
fi

cp "$tmpdir/perp" "$exp/"

$cleanup && rm -rf "$tmpdir"
