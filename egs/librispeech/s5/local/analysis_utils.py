# Copyright Sean Robertson
# Apache 2.0

import re

from typing import Optional, Sequence, Tuple, Union, Callable
from glob import iglob
from math import log

import pandas as pd
import numpy as np

from scipy.interpolate import CubicSpline
from scipy.optimize import leastsq, curve_fit
from pydrobert.kaldi.io.table_streams import open_table_stream
from pydrobert.kaldi.io.enums import KaldiDataType
from recombinator.statistics import (
    estimate_standard_error_from_bootstrap,
    estimate_confidence_interval_from_bootstrap,
)
from patsy.highlevel import dmatrices

__all__ = [
    "agg_mean_by_lens",
    "bin_series",
    "boothroyd_fit",
    "boothroyd_func",
    "klakow_func",
    "log_boothroyd_func",
    "log_klakow_func",
    "log_zhang_func",
    "read_best_uttwers_as_df",
    "read_best_wers_as_df",
    "read_kaldi_table_as_df",
    "read_perps_as_df",
    "read_text_as_df",
    "zhang_fit",
    "zhang_func",
    "inv_zhang_func",
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
                    assert match, f"{path}@{no + 1}: {line}"
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
    r"^.*/(?P<mdl>[^/]+)/decode_(?P<latlm>[^_]+)(?:_rescore_(?P<reslm>[^_]+(?:_lstm_1a)?))?"
    r"_(?P<part>[^_/]+(?:_clean|_other)?)(?:_hires)?/(?P<snr>[^_]+)/"
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
                dict_[key] = float(val[3:])
            else:
                dict_[key] = float("inf")
        elif key == "part":
            dict_[key] = val.replace("_", "-")
    dict_["acc"] = 1 - dict_["wer"]


def read_best_wers_as_df(
    glob: str = "../exp/**/wer_best",
    path_pattern: re.Pattern = WER_PATH_PATTERN,
    file_pattern: re.Pattern = re.compile(
        r"%WER (?P<wer>\d+\.\d\d) \[ \d+ / \d+, (?P<ins>\d+) ins, (?P<del>\d+) del, "
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
    by_rank: bool = False,
    fmt: str = "{}",
    lower_quant: float = 0.0,
    upper_quant: float = 1.0,
) -> Tuple[pd.Series, list[float]]:
    qq = s.quantile([lower_quant, upper_quant])
    s = s.loc[(s >= qq[lower_quant]) & (s <= qq[upper_quant])]
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
    lens_column: str,
    val_columns: Union[str, Sequence[str]],
    group_by: Union[str, Sequence[str]],
) -> pd.DataFrame:
    df = df.copy()
    if isinstance(val_columns, str):
        val_columns = [val_columns]
    else:
        val_columns = list(val_columns)
    if lens_column in val_columns:
        val_columns.remove(lens_column)
        drop_lens = False
    else:
        drop_lens = True
    for val_column in val_columns:
        df[val_column] = df[val_column] * df[lens_column]

    df = df.groupby(group_by, observed=False)[val_columns + [lens_column]].sum()
    df = df.reset_index()
    for val_column in val_columns:
        df[val_column] = df[val_column] / df[lens_column]
    if drop_lens:
        df = df.drop(lens_column, axis=1)
    return df.reset_index()


def _resample_points(
    x: np.ndarray, y: np.ndarray, N: int
) -> tuple[np.ndarray, np.ndarray]:
    idx = np.argsort(x, kind="stable", axis=0)
    x, y = np.take_along_axis(x, idx, axis=0), np.take_along_axis(y, idx, axis=0)
    x, idx = np.unique(x, True)
    y = np.take_along_axis(y, idx, axis=0)
    cs = CubicSpline(x, y)
    x = np.linspace(x.min(), x.max(), N)
    y = cs(x)
    return x, y


def boothroyd_func(x: np.ndarray, k: float, c: float = 1) -> np.ndarray:
    return c * x**k


def log_boothroyd_func(x: np.ndarray, k: float, c: float = 1) -> np.ndarray:
    return k * x + np.log(c)


def _log_boothroyd_fit(y: np.ndarray, x: np.ndarray) -> np.ndarray:
    return np.linalg.lstsq(x, y, rcond=None)[0]


def _boothroyd_fit(y: np.ndarray, x: np.ndarray) -> np.ndarray:
    w0 = _log_boothroyd_fit(y, x)
    y = np.exp(y)
    return leastsq(lambda w: y - _bfunc(x, w), w0)[0]


def _bfunc(x: np.ndarray, w: np.ndarray) -> np.ndarray:
    return (np.exp(x) ** w).prod(1)


def _lbfunc(x: np.ndarray, w: np.ndarray) -> np.ndarray:
    return (x * w).sum(1)


def boothroyd_fit(
    df: pd.DataFrame,
    lwer_in: str = "lwer_in",
    lwer_out: str = "lwer_out",
    ent_bin: str = "ent_bin_in",
    snr: str = "snr",
    include_snr: bool = False,
    include_intercept: bool = False,
    exp_fit: bool = True,
    alpha: float = 0.05,
    bootstrap_size: int = 9999,
) -> pd.DataFrame:
    x: np.ndarray
    y: np.ndarray
    formula = f"{lwer_in} ~ {ent_bin}:{lwer_out}"
    if include_snr:
        formula += f" + {snr}"
    if not include_intercept:
        formula += " - 1"
    y, x = dmatrices(formula, df)
    y = y[..., 0]
    if exp_fit:
        fit = _boothroyd_fit
        func = lambda x, w: np.log(_bfunc(x, w))
    else:
        fit = _log_boothroyd_fit
        func = _lbfunc
    w = fit(y, x)
    records = []
    for i, name in enumerate(x.design_info.column_names):
        if name.startswith(ent_bin):
            name = name.split(":")[0][len(ent_bin) + 1 : -1]
        records.append(dict(name=name, coef=w[i]))
    records = pd.DataFrame.from_records(records)
    if bootstrap_size > 0:
        # in log space, the residuals are quite miniscule for high error (log e = 0) and
        # very large for low errors (log e -> -inf). In the face of heteroskedasticity,
        # we rely on the Wild Bootstrap
        yhat = func(x, w)
        resid = y - yhat
        Bw = np.zeros((bootstrap_size,) + w.shape)
        for b in range(bootstrap_size):
            by = yhat + resid * np.random.normal(size=y.shape)
            Bw[b] = fit(by, x)
        Bw = Bw.T
        records["bootstrap"] = list(Bw)
        records["se"] = [estimate_standard_error_from_bootstrap(*x) for x in zip(Bw, w)]
        records["bias"] = [(bw_i.mean() - w_i) for (bw_i, w_i) in zip(Bw, w)]
        cis = [
            estimate_confidence_interval_from_bootstrap(x, 100 - 100 * alpha)
            for x in Bw
        ]
        records["ci_low"] = [ci[0] for ci in cis] - records["bias"]
        records["ci_high"] = [ci[1] for ci in cis] - records["bias"]
    return records


def recip_zhang_func(x: np.ndarray, A: float, B: float, C: float) -> np.ndarray:
    return np.exp(-(x + B) / C) + A


def zhang_func(x: np.ndarray, A: float, B: float, C: float) -> np.ndarray:
    return 1 / recip_zhang_func(x, A, B, C)


def log_zhang_func(x: np.ndarray, A: float, B: float, C: float) -> np.ndarray:
    return -np.logaddexp(-(x + B) / C, np.log(A))


def inv_zhang_func(x: np.ndarray, A: float, B: float, C: float) -> np.ndarray:
    return C * np.log(x / (1 - A * x)) - B


def zhang_fit(
    x: np.ndarray,
    y: np.ndarray,
    fit_recip: bool = True,
    resample_points: Optional[int] = None,
) -> tuple[float, float, float]:
    if fit_recip:
        y = 1 / y
        fn = recip_zhang_func
    else:
        fn = zhang_func

    if resample_points is not None:
        x, y = _resample_points(x, y, resample_points)

    (A, B, C), _ = curve_fit(
        fn, x, y, (1.0, 0.0, 1.0), bounds=([1, -np.inf, 0.01], [np.inf, np.inf, np.inf])
    )
    return A, B, C


def klakow_func(x: np.ndarray, a: float, b: float = 1) -> np.ndarray:
    return boothroyd_func(x, a, b)


def log_klakow_func(x: np.ndarray, a: float, b: float = 1) -> np.ndarray:
    return log_boothroyd_func(x, a, b)
