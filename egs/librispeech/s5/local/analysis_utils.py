# Copyright Sean Robertson
# Apache 2.0
#
# regress2 was formatted, but otherwise copied verbatim from
#
# https://github.com/OceanOptics/pylr2/blob/master/pylr2/regress2.py
#
# which is MIT-licensed

import re

from typing import Optional, Sequence, Tuple, Union, Callable
from glob import iglob
from math import log

import pandas as pd
import numpy as np
import statsmodels as sm

from scipy.interpolate import CubicSpline
from scipy.optimize import curve_fit
from pydrobert.kaldi.io.table_streams import open_table_stream
from pydrobert.kaldi.io.enums import KaldiDataType


__all__ = [
    "agg_mean_by_lens",
    "bin_series",
    "boothroyd_fit",
    "boothroyd_func",
    "klakow_fit",
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


def regress2(_x, _y, _method_type_1 = "ordinary least square",
             _method_type_2 = "reduced major axis",
             _weight_x = [], _weight_y = [], _need_intercept = True):
    # Regression Type II based on statsmodels
    # Type II regressions are recommended if there is variability on both x and y
    # It's computing the linear regression type I for (x,y) and (y,x)
    # and then average relationship with one of the type II methods
    #
    # INPUT:
    #   _x <np.array>
    #   _y <np.array>
    #   _method_type_1 <str> method to use for regression type I:
    #     ordinary least square or OLS <default>
    #     weighted least square or WLS
    #     robust linear model or RLM
    #   _method_type_2 <str> method to use for regression type II:
    #     major axis
    #     reduced major axis <default> (also known as geometric mean)
    #     arithmetic mean
    #   _need_intercept <bool>
    #     True <default> add a constant to relation (y = a x + b)
    #     False force relation by 0 (y = a x)
    #   _weight_x <np.array> containing the weigth of x
    #   _weigth_y <np.array> containing the weigth of y
    #
    # OUTPUT:
    #   slope
    #   intercept
    #   r
    #   std_slope
    #   std_intercept
    #   predict
    #
    # REQUIRE:
    #   numpy
    #   statsmodels
    #
    # The code is based on the matlab function of MBARI.
    # AUTHOR: Nils Haentjens
    # REFERENCE: https://www.mbari.org/products/research-software/matlab-scripts-linear-regressions/

    # Check input
    if _method_type_2 != "reduced major axis" and _method_type_1 != "ordinary least square":
        raise ValueError("'" + _method_type_2 + "' only supports '" + _method_type_1 + "' method as type 1.")

    # Set x, y depending on intercept requirement
    if _need_intercept:
        x_intercept = sm.add_constant(_x)
        y_intercept = sm.add_constant(_y)

    # Compute Regression Type I (if type II requires it)
    if (_method_type_2 == "reduced major axis" or
        _method_type_2 == "geometric mean"):
        if _method_type_1 == "OLS" or _method_type_1 == "ordinary least square":
            if _need_intercept:
                [intercept_a, slope_a] = sm.OLS(_y, x_intercept).fit().params
                [intercept_b, slope_b] = sm.OLS(_x, y_intercept).fit().params
            else:
                slope_a = sm.OLS(_y, _x).fit().params
                slope_b = sm.OLS(_x, _y).fit().params
        elif _method_type_1 == "WLS" or _method_type_1 == "weighted least square":
            if _need_intercept:
                [intercept_a, slope_a] = sm.WLS(
                    _y, x_intercept, weights=1. / _weight_y).fit().params
                [intercept_b, slope_b] = sm.WLS(
                    _x, y_intercept, weights=1. / _weight_x).fit().params
            else:
                slope_a = sm.WLS(_y, _x, weights=1. / _weight_y).fit().params
                slope_b = sm.WLS(_x, _y, weights=1. / _weight_x).fit().params
        elif _method_type_1 == "RLM" or _method_type_1 == "robust linear model":
            if _need_intercept:
                [intercept_a, slope_a] = sm.RLM(_y, x_intercept).fit().params
                [intercept_b, slope_b] = sm.RLM(_x, y_intercept).fit().params
            else:
                slope_a = sm.RLM(_y, _x).fit().params
                slope_b = sm.RLM(_x, _y).fit().params
        else:
            raise ValueError("Invalid literal for _method_type_1: " + _method_type_1)

    # Compute Regression Type II
    if (_method_type_2 == "reduced major axis" or
        _method_type_2 == "geometric mean"):
        # Transpose coefficients
        if _need_intercept:
            intercept_b = -intercept_b / slope_b
        slope_b = 1 / slope_b
        # Check if correlated in same direction
        if np.sign(slope_a) != np.sign(slope_b):
            raise RuntimeError('Type I regressions of opposite sign.')
        # Compute Reduced Major Axis Slope
        slope = np.sign(slope_a) * np.sqrt(slope_a * slope_b)
        if _need_intercept:
            # Compute Intercept (use mean for least square)
            if _method_type_1 == "OLS" or _method_type_1 == "ordinary least square":
                intercept = np.mean(_y) - slope * np.mean(_x)
            else:
                intercept = np.median(_y) - slope * np.median(_x)
        else:
            intercept = 0
        # Compute r
        r = np.sign(slope_a) * np.sqrt(slope_a / slope_b)
        # Compute predicted values
        predict = slope * _x + intercept
        # Compute standard deviation of the slope and the intercept
        n = len(_x)
        diff = _y - predict
        Sx2 = np.sum(np.multiply(_x, _x))
        den = n * Sx2 - np.sum(_x) ** 2
        s2 = np.sum(np.multiply(diff, diff)) / (n - 2)
        std_slope = np.sqrt(n * s2 / den)
        if _need_intercept:
            std_intercept = np.sqrt(Sx2 * s2 / den)
        else:
            std_intercept = 0
    elif (_method_type_2 == "Pearson's major axis" or
          _method_type_2 == "major axis"):
        if not _need_intercept:
            raise ValueError("Invalid value for _need_intercept: " + str(_need_intercept))
        xm = np.mean(_x)
        ym = np.mean(_y)
        xp = _x - xm
        yp = _y - ym
        sumx2 = np.sum(np.multiply(xp, xp))
        sumy2 = np.sum(np.multiply(yp, yp))
        sumxy = np.sum(np.multiply(xp, yp))
        slope = ((sumy2 - sumx2 + np.sqrt((sumy2 - sumx2)**2 + 4 * sumxy**2)) /
                 (2 * sumxy))
        intercept = ym - slope * xm
        # Compute r
        r = sumxy / np.sqrt(sumx2 * sumy2)
        # Compute standard deviation of the slope and the intercept
        n = len(_x)
        std_slope = (slope / r) * np.sqrt((1 - r ** 2) / n)
        sigx = np.sqrt(sumx2 / (n - 1))
        sigy = np.sqrt(sumy2 / (n - 1))
        std_i1 = (sigy - sigx * slope) ** 2
        std_i2 = (2 * sigx * sigy) + ((xm ** 2 * slope * (1 + r)) / r ** 2)
        std_intercept = np.sqrt((std_i1 + ((1 - r) * slope * std_i2)) / n)
        # Compute predicted values
        predict = slope * _x + intercept
    elif _method_type_2 == "arithmetic mean":
        if not _need_intercept:
            raise ValueError("Invalid value for _need_intercept: " + str(_need_intercept))
        n = len(_x)
        sg = np.floor(n / 2)
        # Sort x and y in order of x
        sorted_index = sorted(range(len(_x)), key=lambda i: _x[i])
        x_w = np.array([_x[i] for i in sorted_index])
        y_w = np.array([_y[i] for i in sorted_index])
        x1 = x_w[1:sg + 1]
        x2 = x_w[sg:n]
        y1 = y_w[1:sg + 1]
        y2 = y_w[sg:n]
        x1m = np.mean(x1)
        x2m = np.mean(x2)
        y1m = np.mean(y1)
        y2m = np.mean(y2)
        xm = (x1m + x2m) / 2
        ym = (y1m + y2m) / 2
        slope = (x2m - x1m) / (y2m - y1m)
        intercept = ym - xm * slope
        # r (to verify)
        r = []
        # Compute predicted values
        predict = slope * _x + intercept
        # Compute standard deviation of the slope and the intercept
        std_slope = []
        std_intercept = []

    # Return all that
    return {"slope": float(slope), "intercept": intercept, "r": r,
            "std_slope": std_slope, "std_intercept": std_intercept,
            "predict": predict}

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


def boothroyd_fit(
    x: np.ndarray,
    y: np.ndarray,
    fit_exponent: bool = False,
    add_intercept: bool = False,
    resample_points: Optional[int] = None,
    method_i = "OLS",
    method_ii = "reduced major axis",
) -> tuple[float, float]:
    if fit_exponent:
        x, y = np.exp(x), np.exp(y)
        fn = boothroyd_func
    else:
        fn = log_boothroyd_func

    if resample_points is not None:
        x, y = _resample_points(x, y, resample_points)
    
    # dict_ = regress2(x, y, method_i, method_ii, _need_intercept=add_intercept)
    # k = dict_['slope']
    # c = np.exp(dict_['intercept']) if add_intercept else 1
    
    p0 = (1.0, 1.0) if add_intercept else (1.0,)
        
    fit, _ = curve_fit(
        fn, x, y, p0
    )
    k, c = fit[0], fit[1] if add_intercept else 1.0
    return k, c
    
def recip_zhang_func(x: np.ndarray, A: float, B: float, C: float) -> np.ndarray:
    return np.exp(-(x + B) / C) + A


def zhang_func(x: np.ndarray, A: float, B: float, C: float) -> np.ndarray:
    return 1 / recip_zhang_func(x, A, B, C)


def log_zhang_func(x: np.ndarray, A: float, B: float, C: float) -> np.ndarray:
    return -np.logaddexp(-(x + B) / C, np.log(A))


def inv_zhang_func(x : np.ndarray, A: float, B: float, C: float) -> np.ndarray:
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


def klakow_fit(
    x: np.ndarray,
    y: np.ndarray,
    fit_exponent: bool = False,
    add_intercept: bool = True,
    resample_points: Optional[int] = None,
) -> tuple[float, float]:
    return boothroyd_fit(x, y, fit_exponent, add_intercept, resample_points)
