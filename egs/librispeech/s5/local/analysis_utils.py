# Copyright Sean Robertson
# Apache 2.0

import re

from typing import Optional, Sequence, Tuple, Union, Callable
from glob import iglob
from math import log

import pandas as pd

from pydrobert.kaldi.io.table_streams import open_table_stream
from pydrobert.kaldi.io.enums import KaldiDataType


__all__ = [
    "read_kaldi_table_as_df",
    "read_best_wers_as_df",
    "read_best_uttwers_as_df",
    "read_perps_as_df",
    "read_text_as_df",
    "bin_series",
    "agg_mean_by_lens",
]


def read_kaldi_table_as_df(
    rspecifier: str,
    kaldi_dtype: Union[KaldiDataType, str],
    key: str = "utt",
    val: str = "val",
    key_as_index: bool = True,
    apply: Callable = lambda x: x,
    **open_kwargs,
) -> pd.DataFrame:
    with open_table_stream(rspecifier, kaldi_dtype, **open_kwargs) as table:
        df = pd.DataFrame.from_records(
            [(x[0], apply(x[1])) for x in table.items()],
            index=key if key_as_index else None,
            columns=[key, val],
        )
    return df


def _read_as_df(
    glob: str,
    file_pattern: Union[str, re.Pattern],
    path_pattern: Optional[re.Pattern] = None,
    entry_fix: Callable[[dict], None] = None,
) -> pd.DataFrame:
    dicts: list[dict] = []
    for path in iglob(glob, recursive=True):
        if path_pattern is None:
            path_dict = dict()
        else:
            match = path_pattern.match(path)
            assert match, path
            path_dict = match.groupdict()
        with open(path) as file_:
            for no, line in enumerate(file_):
                if isinstance(file_pattern, str):
                    utt, val = line.strip().split(maxsplit=1)
                    dict_ = {"utt": utt, file_pattern: val}
                else:
                    match = file_pattern.match(line)
                    assert match, f"{path}:{no + 1}"
                    dict_ = match.groupdict()
                dict_.update(path_dict)
                if entry_fix:
                    entry_fix(dict_)
                dicts.append(dict_)
    return pd.DataFrame.from_records(dicts)


def read_perps_as_df(
    glob: str = "../exp/**/perp",
    path_pattern: re.Pattern = re.compile(
        r".*/(?P<perplm>[^/]+)_perp_(?P<part>[^/]+)/perp$"
    ),
) -> pd.DataFrame:
    def entry_fix(dict_: dict):
        dict_["part"] = dict_["part"].replace("_", "-")
        dict_["perp"] = float(dict_["perp"])
        dict_["ent"] = log(dict_["perp"])

    return _read_as_df(glob, "perp", path_pattern, entry_fix)


def read_text_as_df(
    glob: str = "../data/*/text",
    path_pattern: re.Pattern = re.compile(r".*/(?P<part>[^/]+)/text$"),
) -> pd.DataFrame:
    def entry_fix(dict_: dict):
        dict_["part"] = dict_["part"].replace("_", "-")
        dict_["len"] = len(dict_["text"].split())

    return _read_as_df(glob, "text", path_pattern, entry_fix)


WER_PATH_PATTERN = re.compile(
    r"^.*/(?P<mdl>[^/]+)/decode_(?P<latlm>[^_]+)(?:_rescore_(?P<reslm>[^/]+))?"
    r"_(?P<part>(?:dev|test)_(?:clean|other))(:?_hires)?/(?P<snr>[^_]+)/"
    r"(?:utt)?wer_best$"
)


def _wer_entry_fix(dict_: dict):
    for key, val in tuple(dict_.items()):
        if val is None:
            if key == "reslm":
                dict_[key] = dict_["latlm"]
        elif key in {"wip"}:
            dict_[key] = float(val)
        elif key == "wer":
            dict_[key] = float(val) / 100
        elif key in {"ins", "del", "sub", "lmwt"}:
            dict_[key] = int(val)
        elif key == "snr":
            if val.startswith("snr"):
                dict_[key] = int(val[3:])
            else:
                dict_[key] = None
        elif key == "part":
            dict_[key] = val.replace("_", "-")
    dict_["acc"] = 1 - dict_["wer"]


def read_best_wers_as_df(
    glob: str = "../exp/**/wer_best",
    path_pattern: re.Pattern = WER_PATH_PATTERN,
    file_pattern: re.Pattern = re.compile(
        r"%WER (?P<wer>\d\d?.\d\d) \[ \d+ / \d+, (?P<ins>\d+) ins, (?P<del>\d+) del, "
        r"(?P<sub>\d+) sub \] .*/wer_(?P<lmwt>\d+)_(?P<wip>[\d.]+)\w*$"
    ),
) -> pd.DataFrame:
    return _read_as_df(glob, file_pattern, path_pattern, _wer_entry_fix)


def read_best_uttwers_as_df(
    glob: str = "../exp/**/uttwer_best",
    path_pattern: re.Pattern = WER_PATH_PATTERN,
) -> pd.DataFrame:
    return _read_as_df(glob, "wer", path_pattern, _wer_entry_fix)


def bin_series(
    s: pd.Series,
    bins: Union[int, Sequence[float]],
    by_rank: bool = True,
    fmt: str = "{}",
) -> Tuple[pd.Series, list[float]]:
    v = s.rank() if by_rank else s
    bin_vals = pd.cut(v, bins, labels=False)
    if isinstance(bins, int):
        num_bins = bins
        bin_bounds = [float(s[bin_vals == i].min()) for i in range(num_bins)]
        bin_bounds.append(s.max())
    else:
        bin_bounds = list(bins)
        num_bins = len(bins) - 1
    bin_map = dict(
        (i, f"({fmt},{fmt}]".format(bin_bounds[i], bin_bounds[i + 1]))
        for i in range(num_bins)
    )
    return (
        bin_vals.map(bin_map).astype(
            pd.CategoricalDtype(list(bin_map.values()), ordered=True)
        ),
        bin_bounds,
    )


def agg_mean_by_lens(
    df: pd.DataFrame,
    lens: pd.Series,
    val_columns: Union[str, Sequence[str]],
    group_by: Union[str, Sequence[str]],
) -> pd.DataFrame:
    df = df.copy().join(lens)
    df[val_columns] *= lens
    df = df.groupby(group_by, observed=True)
    if isinstance(val_columns, str):
        df = df[[val_columns, lens.name]]
    else:
        val_columns = list(val_columns)
        val_columns.append(lens.name)
        df = df[val_columns]
    df = df.sum()
    df[val_columns] /= df[lens.name]
    return df.drop(lens.name, axis=1).reset_index()
