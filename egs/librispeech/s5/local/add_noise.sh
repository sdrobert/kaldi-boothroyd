#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

echo "$0 $*"

pref="0.00002"
l0="70"
cleanup=true
cmd=run.pl
noise_type=whitenoise

. ./path.sh
. utils/parse_options.sh

if [ $# -ne 3 ] && [ $# -ne 4 ]; then
  echo "Usage: $0 [opts] <src-data> <snr> <dest-data> [<noise-dir>]"
  echo "e.g. $0 data/dev_clean_norm 0 data/dev_clean_snr_0 mfcc"
  echo ""
  echo "Options:"
  echo "--pref FLOAT       The reference amplitude. Default 0.00002"
  echo "--l0 FLOAT         The reference level (dB). Defaults to 70"
  echo "--noise-type TYPE  The type of noise generated with the sox synth"
  echo "                   command. Defaults to whitenoise"
  exit 1
fi

src="$1"
snr="$2"
dst="$3"
ndir="${4:-"$3/noise"}"
tmpdir="$dst/tmp"
tsrc="$tmpdir/tsrc"

for x in "$src/wav.scp"; do
  if [ ! -f "$x" ]; then
    echo "$0: file '$x' does not exist!"
    exit 1
  fi
done

set -eo pipefail

mkdir -p "$tsrc" "$dst" "$ndir"

# general strategy: construct noise with the longest 

./utils/data/get_reco2dur.sh "$src"
max_dur=$(cut -d ' ' -f 2 "$src/reco2dur" | awk -v m=0 '{if ($1 > m) m = $1} END {print m}')

nfile="$ndir/$noise_type.$max_dur.wav"
# -R flag should keep this file the same, no matter how many times it's
# called
sox -R -b 16 -r 16k -n $nfile synth $max_dur $noise_type vol 0.99
coeff=$(sox "$nfile" -n stat 2>&1 | awk -v l0=$l0 -v pref=$pref  -v snr=$snr '/RMS +amplitude/ {print pref * exp(log(10) * (l0 - snr) / 40) / $3}')

./utils/copy_data_dir.sh "$src" "$tsrc"
rm -f "$tsrc/"{feats.scp,cmvn.scp}


awk -v coeff=$coeff -v nfile=$nfile \
    '{print "sox -m - -v",coeff,nfile,"-t wav - trim 0",$2,"|"}' \
    "$src/reco2dur" |
  paste -d ' ' $src/wav.scp - > "$tsrc/wav.scp"

./utils/validate_data_dir.sh --no-feats "$tsrc"

cp "$tsrc"/* "$dst"

! $cleanup || rm -rf "$tmpdir"
