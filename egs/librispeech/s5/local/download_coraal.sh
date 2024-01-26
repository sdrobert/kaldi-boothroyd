#! /usr/bin/env bash

# Copyright 2024 Sean Robertson
# Apache 2.0

# Copies from local/download_and_untar.sh
# Copyright 2014 Daniel Povey, Vassil Panayotov

remove_archive=false
blacklist="LES_metadata_2018.10.06.txt VLD_metadata_2018.10.06.txt"
single=false

. ./cmd.sh
. ./path.sh
. parse_options.sh


if [ $# -ne 2 ]; then
  echo "Usage: $0 [options] <store-base> <manifest-file-or-url>"
  echo "e.g.: $0 /ais/hal9000/sdrobert/coraal http://lingtools.uoregon.edu/coraal/coraal_download_list.txt"
  echo "      $0 --single true /ais/hal9000/sdrobert/coraal https://github.com/stanford-policylab/asr-disparities/raw/master/input/CORAAL_transcripts.csv"
  echo ""
  echo "Options:"
  echo " --remove-archive {true|false}                   Delete archives after they're downloaded (deft: $remove_archive)"
  echo " --blacklist '<basename 1> [<basename 2> ...]'   Files not to download (deft: $blacklist)"
  echo " --single {true|false}                           2nd arg is manifest (false) or file to download (true) (deft: $single)"
  exit 1
fi

store="$1"
manifest="$2"

declare -A FILE2SIZE=(
  ["ATL_audio_part01_2020.05.tar.gz"]="471181856"
  ["ATL_audio_part02_2020.05.tar.gz"]="394142433"
  ["ATL_audio_part03_2020.05.tar.gz"]="386630794"
  ["ATL_audio_part04_2020.05.tar.gz"]="462114530"
  ["ATL_elanfiles_2020.05.tar.gz"]="990223"
  ["ATL_metadata_2020.05.txt"]="6603"
  ["ATL_se0_ag1_f_01_1.wav"]="164316636"
  ["ATL_se0_ag1_f_02_1.wav"]="168041472"
  ["ATL_textfiles_2020.05.tar.gz"]="512506"
  ["ATL_textgrids_2020.05.tar.gz"]="847530"
  ["CORAAL_transcripts.csv"]="6089928"
  ["CORAALUserGuide_current.pdf"]="1102468"
  ["DCA_audio_part01_2018.10.06.tar.gz"]="721501810"
  ["DCA_audio_part02_2018.10.06.tar.gz"]="625840650"
  ["DCA_audio_part03_2018.10.06.tar.gz"]="768177376"
  ["DCA_audio_part04_2018.10.06.tar.gz"]="631928677"
  ["DCA_audio_part05_2018.10.06.tar.gz"]="699329572"
  ["DCA_audio_part06_2018.10.06.tar.gz"]="962982155"
  ["DCA_audio_part07_2018.10.06.tar.gz"]="625858241"
  ["DCA_audio_part08_2018.10.06.tar.gz"]="764114779"
  ["DCA_audio_part09_2018.10.06.tar.gz"]="838786355"
  ["DCA_audio_part10_2018.10.06.tar.gz"]="869237834"
  ["DCA_elanfiles_2018.10.06.tar.gz"]="3759043"
  ["DCA_metadata_2018.10.06.txt"]="44081"
  ["DCA_textfiles_2018.10.06.tar.gz"]="1971578"
  ["DCA_textgrids_2018.10.06.tar.gz"]="3128471"
  ["DCB_audio_part01_2018.10.06.tar.gz"]="807328059"
  ["DCB_audio_part02_2018.10.06.tar.gz"]="646803359"
  ["DCB_audio_part03_2018.10.06.tar.gz"]="471156371"
  ["DCB_audio_part04_2018.10.06.tar.gz"]="478496612"
  ["DCB_audio_part05_2018.10.06.tar.gz"]="904081541"
  ["DCB_audio_part06_2018.10.06.tar.gz"]="670401934"
  ["DCB_audio_part07_2018.10.06.tar.gz"]="594417668"
  ["DCB_audio_part08_2018.10.06.tar.gz"]="633462590"
  ["DCB_audio_part09_2018.10.06.tar.gz"]="664400237"
  ["DCB_audio_part10_2018.10.06.tar.gz"]="530685203"
  ["DCB_audio_part11_2018.10.06.tar.gz"]="468514884"
  ["DCB_audio_part12_2018.10.06.tar.gz"]="521037029"
  ["DCB_audio_part13_2018.10.06.tar.gz"]="564766923"
  ["DCB_audio_part14_2018.10.06.tar.gz"]="128184960"
  ["DCB_elanfiles_2018.10.06.tar.gz"]="5032172"
  ["DCB_metadata_2018.10.06.txt"]="43302"
  ["DCB_textfiles_2018.10.06.tar.gz"]="2816920"
  ["DCB_textgrids_2018.10.06.tar.gz"]="4234932"
  ["DTA_audio_part01_2023.06.tar.gz"]="466988785"
  ["DTA_audio_part02_2023.06.tar.gz"]="542634532"
  ["DTA_audio_part03_2023.06.tar.gz"]="308039403"
  ["DTA_audio_part04_2023.06.tar.gz"]="495756211"
  ["DTA_audio_part05_2023.06.tar.gz"]="644922715"
  ["DTA_audio_part06_2023.06.tar.gz"]="609017557"
  ["DTA_audio_part07_2023.06.tar.gz"]="400027751"
  ["DTA_audio_part08_2023.06.tar.gz"]="633244891"
  ["DTA_audio_part09_2023.06.tar.gz"]="532734651"
  ["DTA_audio_part10_2023.06.tar.gz"]="522685486"
  ["DTA_elanfiles_2023.06.tar.gz"]="2770966"
  ["DTA_metadata_2023.06.txt"]="31226"
  ["DTA_textfiles_2023.06.tar.gz"]="1428948"
  ["DTA_textgrids_2023.06.tar.gz"]="2352507"
  ["LES_audio_part01_2021.07.tar.gz"]="511759806"
  ["LES_audio_part02_2021.07.tar.gz"]="557989800"
  ["LES_audio_part03_2021.07.tar.gz"]="716158028"
  ["LES_elanfiles_2021.07.tar.gz"]="1071225"
  ["LES_textfiles_2021.07.tar.gz"]="546430"
  ["LES_textgrids_2021.07.tar.gz"]="921486"
  ["PRV_audio_part01_2018.10.06.tar.gz"]="797045351"
  ["PRV_audio_part02_2018.10.06.tar.gz"]="919479624"
  ["PRV_audio_part03_2018.10.06.tar.gz"]="982116581"
  ["PRV_audio_part04_2018.10.06.tar.gz"]="565637234"
  ["PRV_elanfiles_2018.10.06.tar.gz"]="1884045"
  ["PRV_metadata_2018.10.06.txt"]="20393"
  ["PRV_textfiles_2018.10.06.tar.gz"]="894006"
  ["PRV_textgrids_2018.10.06.tar.gz"]="1566520"
  ["ROC_audio_part01_2020.05.tar.gz"]="601718376"
  ["ROC_audio_part02_2020.05.tar.gz"]="617531670"
  ["ROC_audio_part03_2020.05.tar.gz"]="797355036"
  ["ROC_audio_part04_2020.05.tar.gz"]="549776743"
  ["ROC_audio_part05_2020.05.tar.gz"]="312347159"
  ["ROC_elanfiles_2020.05.tar.gz"]="1406326"
  ["ROC_metadata_2020.05.txt"]="9748"
  ["ROC_textfiles_2020.05.tar.gz"]="801537"
  ["ROC_textgrids_2020.05.tar.gz"]="1188803"
  ["VLD_audio_part01_2021.07.tar.gz"]="581271031"
  ["VLD_audio_part02_2021.07.tar.gz"]="353884408"
  ["VLD_audio_part03_2021.07.tar.gz"]="574591219"
  ["VLD_audio_part04_2021.07.tar.gz"]="688030585"
  ["VLD_elanfiles_2021.07.tar.gz"]="1170913"
  ["VLD_textfiles_2021.07.tar.gz"]="667292"
  ["VLD_textgrids_2021.07.tar.gz"]="1002765"
)

set -eo pipefail

if $single; then
  filelist=( "$manifest" )
else
  if [ -f "$manifest" ]; then
      echo "$manifest is a file. Reading"
      readarray -t filelist < "$manifest"
  else
      echo "$manifest is not a file. Assuming a URL"
      filelist=( $(wget --no-check-certificate "$manifest" -O -) )
  fi
fi

for full_url in "${filelist[@]}"; do
    fname="$(basename "$full_url")"
    if [[ "$blacklist" =~ $fname ]]; then
        echo "$fname in blacklist. Not downloading"
        continue
    fi
    outfile="$store/$fname"
    efsize="${FILE2SIZE[$fname]}"

    if [ -f "$store/.$fname.complete" ]; then
        echo "$0: $fname was already successfully extracted into $store; skipping."
        continue
    fi

    if [ -f "$outfile" ]; then
      fsize="$(set -o pipefail; du -b "$outfile" 2>/dev/null | awk '{print $1}' || stat '-f %z' "$outfile")"
      if [ "$fsize" != "$efsize" ]; then
        if [ -z "$efsize" ]; then
            echo "$0: don't know the correct size of $outfile, so redownloading to be safe"
        else
            echo "$0: $outfile exists but is the wrong size. Removing"
        fi
        rm "$outfile"
      fi
    fi

    if [ ! -f "$outfile" ]; then
        mkdir -p "$store"
        wget --no-check-certificate -O "$outfile" "$full_url"
        fsize="$(set -o pipefail; du -b "$outfile" 2>/dev/null | awk '{print $1}' || stat '-f %z' "$outfile")"
        if [ ! -z "$efsize" ] && [ "$fsize" != "$efsize" ]; then
            echo "$0: downloaded $outfile, but it was the wrong size! Exiting"
            exit 1
        fi
    fi

    if [[ "$outfile" =~ .tar.gz ]]; then
        echo "$outfile is an archive. Extracting"
        tar -xvzf "$outfile" -C "$store"

        if $remove_archive; then
          echo "$0: removing $outfile file since --remove-archive option was supplied."
          rm "$outfile"
        fi
    fi

    touch "$store/.$fname.complete"
done

