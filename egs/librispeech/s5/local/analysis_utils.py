# Copyright Sean Robertson
# Apache 2.0

import re
import os

from typing import Union, Callable
from glob import iglob

import pandas as pd

from pydrobert.kaldi.io.table_streams import open_table_stream
from pydrobert.kaldi.io.enums import KaldiDataType


__all__ = ["read_kaldi_table_as_df", "read_best_wers_as_df", "read_best_uttwers_as_df"]


def read_kaldi_table_as_df(
    rspecifier: str,
    kaldi_dtype: Union[KaldiDataType, str],
    key: str = "utt",
    val: str = "val",
    key_as_index: bool = True,
    apply: Callable = lambda x: x,
    **open_kwargs
) -> pd.DataFrame:
    with open_table_stream(rspecifier, kaldi_dtype, **open_kwargs) as table:
        df = pd.DataFrame.from_records(
            [(x[0], apply(x[1])) for x in table.items()],
            index=key if key_as_index else None,
            columns=[key, val],
        )
    return df


def read_best_wers_as_df(
    glob: str = "../exp/**/wer_best",
    path_pattern: re.Pattern = re.compile(
        r"^.*/(?P<mdl>[^/]+)/decode_(?P<latlm>[^_]+)(?:_rescore_(?P<reslm>[^/]+))?"
        r"_(?P<part>(?:dev|test)_(?:clean|other))_(?P<snr>[^_]+)(:?_hires)?"
        r"(:?_perp(?P<perp_idx>\d+)_(?P<perp_tot>\d+))?/wer_best$"
    ),
    file_pattern: re.Pattern = re.compile(
        r"%WER (?P<wer>\d\d?.\d\d) \[ \d+ / \d+, (?P<ins>\d+) ins, (?P<del>\d+) del, "
        r"(?P<sub>\d+) sub \] .*/wer_(?P<lmwt>\d+)_(?P<wip>[\d.]+)\w*$"
    ),
) -> pd.DataFrame:
    dicts: list[dict] = []
    for path in iglob(glob, recursive=True):
        match = path_pattern.match(path)
        assert match, path
        dict_ = match.groupdict()
        dict_["path"] = os.path.dirname(path)
        with open(path) as file_:
            txt = file_.read()
        match = file_pattern.match(txt)
        assert match, (path, txt)
        dict_.update(match.groupdict())
        for key, val in tuple(dict_.items()):
            if val is None:
                if key == "perp_tot":
                    dict_[key] = dict_["perp_idx"] = 1
                elif key == "reslm":
                    dict_[key] = dict_["latlm"]
            elif key in {"wip"}:
                dict_[key] = float(val)
            elif key == "wer":
                dict_[key] = float(val) / 100
            elif key in {"ins", "del", "sub", "lmwt", "perp_idx", "perp_tot"}:
                dict_[key] = int(val)
            elif key == "snr":
                if val.startswith("snr"):
                    dict_[key] = int(val[3:])
                else:
                    dict_[key] = None
            elif key == "part":
                dict_[key] = val.replace("_", "-")
        dicts.append(dict_)
    return pd.DataFrame.from_records(dicts)


def read_best_uttwers_as_df(
    glob: str = "../exp/**/uttwer_best",
) -> pd.DataFrame:
    dicts: list[dict] = []
    for path in iglob(glob, recursive=True):
        dir_ = os.path.dirname(path)
        with open(path) as file_:
            for line in file_:
                utt, wer = line.strip().split()
                wer = float(wer)
                dicts.append({"path": dir_, "utt": utt, "wer": wer})
    return pd.DataFrame.from_records(dicts)
