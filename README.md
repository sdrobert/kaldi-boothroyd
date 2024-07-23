# kaldi-boothroyd

This is the companion repository to the paper

> Robertson, S., Penn, G., Dunbar, E. "Quantifying the Role of Textual
  Predictability in Automatic Speech Recognition", Proc. INTERSPEECH 2024 (to
  appear)

This is a modified, trimmed-down version of the [Kaldi
repository](https://github.com/kaldi-asr/kaldi). The paper's recipes and
supplemental figures may be found in `egs/librispeech/s5` folder.

Kaldi is Apache-2.0 licensed, with details in the [COPYING](./COPYING) file. We
release our modifications under the same license.

## Viewing the analysis

The analysis was run in
[local/analysis.ipynb](./egs/librispeech/s5/local/analysis.ipynb), with figures
output to the [figs](./egs/librispeech/s5/figs) subdirectory, all in the
[s5](./egs/librispeech/s5) recipe. All files can be rendered from GitHub
without special setup or software.

## Re-running the analysis

Re-running `analysis.ipynb`, or the entire experiment from scratch, is
considerably more complicated. You have to set up a Python environment,
download the requisite data, and compute or download various artifacts derived
from the recipe.

### Installation

An [explicit spec
file](https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html#id3)
for a Linux-64 Conda environment may be found in this repo's root directory
with the name [explicit-environment.yaml](./explicit-environment.yaml). You may
attempt to recreate the environment on other platforms with
[environment.yml](./environment.yml), though inevitably there will be
version mismatches.

**NOTE:** we install a [Conda-forge version of
Kaldi](https://anaconda.org/conda-forge/kaldi) into the environment. The Kaldi
source code has been stripped from this repository.

### Using our artifacts

We have made our artifacts available on
[Huggingface](https://huggingface.co/sdrobert/kaldi-boothroyd-exp). This
includes error rate computations by SNR and model, perplexity computations, and
the `tri6b` model (the only model we tested which wasn't available online
already). To use them for the analysis, you can clone the HuggingFace
repository into the `exp` folder of the s5 recipe:

``` sh
cd egs/librispeech/s5
git clone https://huggingface.co/sdrobert/kaldi-boothroyd-exp exp
```

However, you'll have to download and prep the corpora used in the analysis
separately. We focused on [LibriSpeech](https://www.openslr.org/12/) and
[CORAAL](https://oraal.uoregon.edu/coraal). **Please review their licenses
before downloading!** Download scripts are available as
[local/download_and_untar.sh](./egs/librispeech/s5/local/download_and_untar.sh)
and [local/download_coraal.sh](./egs/librispeech/s5/local/download_coraal.sh);
prep scripts are available as
[local/data_prep.sh](./egs/librispeech/s5/local/data_prep.sh) and
[local/coraal_data_prep.sh](./egs/librispeech/s5/local/coraal_data_prep.sh).

Once you've downloaded and prepped everything, your s5 directory should look
like this:

```
exp/
  chain_cleaned/
  facebook/
  ...
data/
  ATL/
  ...
  dev_clean/
  ...
local/
  analysis.ipynb
  ...
cmd.sh
path.sh
run.sh
...
```

You can then run `analysis.ipynb` from the local folder. **Make sure to
activate the Conda environment first!**

### Starting from scratch

*These commands were from memory. Please use your discretion.*

If you have a lot of time on your hands or want to run an analysis on other
corpora, you'll first want to run (at least) up to the end of stage 4 in
[run.sh](./egs/librispeech/s5/run.sh) so that all n-gram LMs are downloaded and
converted to FSTs. You might have to update
[path.sh](./egs/librispeech/s5/path.sh) to make sure your conda environment is
activating. The remainder of the script may be used to train `tri6b` and
`tdnn_1d_sp` (though a pretrained version of the latter will be downloaded by
the following scripts).

To derive the artifacts necessary to analyze a corpus, you need that corpus to
be formatted in the [usual Kaldi
way](https://kaldi-asr.org/doc/data_prep.html). If a partition of the
corpus is stored in `data/my-partition`, then the following call should
succeed:

``` sh
. path.sh
validate_data_dir.sh --no-feats data/my-partition
```

Afterwards, you can compute the per-utterance perplexity of that partition
with the command

``` sh
local/run_pp.sh --part my-partition
```

The RNN-LM mentioned in the paper will be downloaded as a side-effect of this
script. Check [local/run_pp.sh](./egs/librispeech/s5/local/run_pp.sh) for
more options.

Similarily, we may calculate error rates on this partition with the
`tdnn_1d_sp` model across various SNRs with the command

``` sh
local/run_snr.sh --part my-partition
```

Again, check [local/run_snr.sh](./egs/librispeech/s5/local/run_snr.sh) for
more options.

If all went well, you should be able to update the `PART_RENAMES` and
`PART2RENAMES` constants in `analysis.ipynb` with your partition. A similar
strategy may be employed for new models (use the `--mdl` flag) as well as
for the existing model/partition combinations.

If you're troubleshooting, the more complicated logic behind the analysis may
be found in the
[analysis_utils.py](./egs/librispeech/s5/local/analysis_utils.py) helper file.
Note that many table fields are gleaned using regular expressions of file paths
and contents, making them susceptible to breakage. If you're using new data
or models, double-check that those expressions are working as intended.
