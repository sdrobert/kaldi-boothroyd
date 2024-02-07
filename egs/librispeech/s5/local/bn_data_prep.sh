#! /usr/bin/env bash

# Copyright 2024 Sean Robertson
# Apache 2.0

confdir="conf"
parts="hp lp zp"

. ./utils/parse_options.sh
. ./path.sh

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 [options] <dst-dir>"
  echo "e.g.: $0 data/local/bn"
  echo "Options:"
  echo " --confdir <dir>"
fi

dst="$1"

for part in $parts; do
  x="$confdir/bn_$part.txt"
  if [ ! -f "$x" ]; then
    echo "$0: '$x' is not a file!"
    exit 1
  fi
done

set -eo pipefail

mkdir -p "$dst"

for part in $parts; do
  # remove comments, empty lines, and then capitalize
  cut -d '#' -f 1 "$confdir/bn_$part.txt" |
    sed '/^ *$/d' |
    tr '[:lower:]' '[:upper:]' > $dst/$part.txt
done
