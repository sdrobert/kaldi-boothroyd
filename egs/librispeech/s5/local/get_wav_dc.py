#! /usr/bin/env python

import sys
import logging

import numpy as np

from pydrobert.kaldi.io import open as kaldi_open
from pydrobert.kaldi.io.argparse import KaldiParser
from pydrobert.kaldi.logging import kaldi_logger_decorator
from pydrobert.kaldi.logging import register_logger_for_kaldi


@kaldi_logger_decorator
def main(args=None):
    """Write DC offset of wav files to table"""

    logger = logging.getLogger(sys.argv[0])
    if not logger.handlers:
        logger.addHandler(logging.StreamHandler())
    register_logger_for_kaldi(logger)
    parser = KaldiParser(description=main.__doc__, logger=logger)
    parser.add_argument("--channel", type=int, default=-1)
    scale_by_grp = parser.add_mutually_exclusive_group()
    scale_by_grp.add_argument("--scale-by", type=float, default=1)
    scale_by_grp.add_argument("--inv-scale-by", type=float, default=None)
    parser.add_argument("wav", type="kaldi_rspecifier", help="rspecifier of wavs")
    parser.add_argument(
        "dc", type="kaldi_wspecifier", help="wspecifier of dc offset (float)"
    )

    options = parser.parse_args(args)

    if options.inv_scale_by is not None:
        options.scale_by = 1 / options.inv_scale_by

    reader = kaldi_open(options.wav, "wm")
    writer = kaldi_open(options.dc, "b", "w")

    utt_no = -1
    for utt_no, (utt, wav) in enumerate(reader.items()):
        if options.channel == -1 and wav.shape[0] != 1:
            logger.error(f"{utt}: expected mono; got {wav.shape[0]} channels")
        wav = wav[options.channel]
        writer.write(utt, wav.mean() * options.scale_by)

    logger.info(f"Processed {utt_no + 1} entries")


if __name__ == "__main__":
    main()
