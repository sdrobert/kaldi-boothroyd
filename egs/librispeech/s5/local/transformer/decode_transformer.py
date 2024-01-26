#! /usr/bin/env python

# Copyright 2024 Sean Robertson
# Apache 2.0

import sys
import logging

import torch

from pydrobert.kaldi.io.argparse import KaldiParser
from pydrobert.kaldi.io.table_streams import open_table_stream
from pydrobert.kaldi.logging import kaldi_logger_decorator
from pydrobert.kaldi.logging import register_logger_for_kaldi
from transformers import AutoProcessor, AutoModelForCTC


@kaldi_logger_decorator
def main(args=None):
    """\
Decode audio with HuggingFace's transformer package
"""

    logger = logging.getLogger(sys.argv[0])
    if not logger.handlers:
        logger.addHandler(logging.StreamHandler())
    register_logger_for_kaldi(logger)
    parser = KaldiParser(description=main.__doc__, logger=logger)
    parser.add_argument("--channel", type=int, default=-1)
    parser.add_argument("--device", type=torch.device, default=torch.device("cpu"))
    parser.add_argument("wav", type="kaldi_rspecifier", help="rspecifier of wavs")
    parser.add_argument("model_name", help="transformer model name")
    parser.add_argument(
        "hyp", type="kaldi_wspecifier", help="wspecifier of transcriptions"
    )

    options = parser.parse_args(args)

    processor = AutoProcessor.from_pretrained(options.model_name)
    model = AutoModelForCTC.from_pretrained(options.model_name).to(options.device)

    reader = open_table_stream(options.wav, "wm", "r", value_style="bs")
    writer = open_table_stream(options.hyp, "tv", "w")

    with torch.no_grad():
        for utt, (signal, rate) in reader.items():
            if options.channel == -1 and signal.shape[0] != 1:
                logger.error(f"{utt}: expected mono; got {signal.shape[0]} channels")
            inputs = processor(
                signal[options.channel],
                sampling_rate=rate,
                return_tensors="pt",
            )
            inputs = {k: v.to(options.device) for k, v in inputs.items()}
            logits = model(**inputs).logits
            ids = torch.argmax(logits, dim=-1)
            hyps = processor.batch_decode(ids)
            logger.info(f"{utt}: {hyps[0]}")
            writer.write(utt, hyps[0].strip().split())


if __name__ == "__main__":
    main()
