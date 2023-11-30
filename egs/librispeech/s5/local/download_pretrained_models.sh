#! /usr/bin/env bash

# Copyright 2023 Sean Robertson
# Apache 2.0

# Copies from local/download_and_untar.sh and local/download_lm.sh
# Copyright 2014 Daniel Povey, Vassil Panayotov

remove_archive=false
if [ "$1" == --remove-archive ]; then
  remove_archive=true
  shift
fi

declare -A FILE2SIZE=(
  ["0013_librispeech_v1_lm"]="197387188"
  ["0013_librispeech_v1_chain"]="214046656"
  ["0013_librispeech_v1_extractor"]="19121926"
)

if [ $# -ne 3 ]; then
  echo "Usage: $0 [--remove-archive] <store-base> <url-base> <model-name>"
  echo "e.g.: $0 /ais/hal9000/sdrobert/librispeech_models https://kaldi-asr.org/models/13/ 0013_librispeech_v1_lm"
  echo "With --remove-archive it will remove the archive after successfully un-tarring it."
  echo "Valid model-names: ${!FILE2SIZE[*]}"
  exit 1
fi

store="$1"
url="$2"
model="$3"
tarfile="$store/$model.tar.gz"
full_url="$url/$model.tar.gz"

efsize="${FILE2SIZE[$model]}"
if [ -z "$efsize" ]; then
  echo "$0: Invalid model $model: should be one of ${!FILE2SIZE[*]}"
  exit 1
fi

set -eo pipefail

if [ -f "$store/.$model.complete" ]; then
  echo "$0: model $model was already successfully extracted into $store, nothing to do."
  exit 0;
fi

if [ -f "$tarfile" ]; then
  fsize="$(set -o pipefail; du -b "$tarfile" 2>/dev/null | awk '{print $1}' || stat '-f %z' "$tarfile")"
  if [ "$fsize" != "$efsize" ]; then
    echo "$0: $tarfile exists but is the wrong size. Removing"
    rm "$tarfile"
  fi
fi

if [ ! -f "$tarfile" ]; then
  mkdir -p "$store"
  wget --no-check-certificate -O "$tarfile" "$full_url"
  fsize="$(set -o pipefail; du -b "$tarfile" 2>/dev/null | awk '{print $1}' || stat '-f %z' "$tarfile")"
  if [ "$fsize" != "$efsize" ]; then
    echo "$0: downloaded $tarfile, but it was the wrong size! Exiting"
    exit 1
  fi
fi

tar -xvzf "$tarfile" -C "$store"

touch "$store/.$model.complete"

if $remove_archive; then
  echo "$0: removing $tarfile file since --remove-archive option was supplied."
  rm "$tarfile"
fi
