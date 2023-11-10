# Copyright Sean Robertson
# Apache 2.0

from typing import Union, Callable

import pandas as pd

from pydrobert.kaldi.io.table_streams import open_table_stream
from pydrobert.kaldi.io.enums import KaldiDataType


__all__ = [
    "read_kaldi_table_as_df",
]


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
