export KALDI_ROOT=`pwd`/../../..
if [ "$CONDA_DEFAULT_ENV" != "kaldi-boothroyd" ]; then
  if [ "$(hostname)" = "hal9000" ]; then
    eval "$(micromamba shell hook --shell bash)"
    micromamba activate kaldi-boothroyd || exit 1
  else
    conda activate kaldi-boothroyd || exit 1
  fi
fi
export PATH="$PWD/utils:$PATH"
export LC_ALL=C
export PYTHONUNBUFFERED=1
# [ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
# . $KALDI_ROOT/tools/config/common_path.sh
# [ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
