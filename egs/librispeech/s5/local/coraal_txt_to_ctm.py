#! /usr/bin/env python

import os
import sys
import argparse
import re

from functools import reduce

SPKR_PATTERN = re.compile(
    r"^(?P<code>[A-Z]{3})_se(?P<se>\d)_ag(?P<ag>\d)_(?P<gen>[mfn])_(?P<num>\d+)$"
)

SKIP_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\["),  # overlapping speech
    re.compile(r"[(]"),  # some form of line-level note
)

REPLACE_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"<[^>]+>"), "<SPOKEN_NOISE>"),  # non-speech noises
    (re.compile(r"\/[^/]+\/"), "<UNK>"),  # unintelligible, misspoken, redacted, etc.
    (re.compile(r"[.,?!]"), " "),  # punctuation
    (re.compile(r"-"), " "),  # restarts and spelling out acronyms
    (re.compile(r"  +"), " "),  # multiple spaces
    (re.compile(r"^ "), ""),  # sentence-initial space
    (re.compile(r" $"), ""),  # sentence-final space
)


def main(args=None):
    "Convert CORAAL transcription file into STM transcription, with filtering"

    parser = argparse.ArgumentParser(description=main.__doc__)
    parser.add_argument("--precision", type=int, default=3)
    parser.add_argument("--channel", default="A")
    parser.add_argument("--min-duration", type=float, default=1.0)
    parser.add_argument("--min-words", type=int, default=3)
    parser.add_argument("in_file", type=argparse.FileType("r"))
    parser.add_argument(
        "out_file", nargs="?", type=argparse.FileType("w"), default=sys.stdout
    )
    options = parser.parse_args(args)

    name = os.path.basename(options.in_file.name).rsplit(".", maxsplit=1)[0]

    for no, line in enumerate(options.in_file):
        line: str
        try:
            _, spkr, st, content, et = line.strip().split("\t")
            match = SPKR_PATTERN.match(spkr)
            if match is None:
                continue
            st, et = float(st), float(et)
            if (et - st) < options.min_duration:
                continue
            content = content.upper()
            if any(pattern.search(content) for pattern in SKIP_PATTERNS):
                continue
            content = reduce(lambda x, y: y[0].sub(y[1], x), REPLACE_PATTERNS, content)
            if len(content.split()) < options.min_words:
                continue
            options.out_file.write(
                f"{name} {options.channel} {spkr} {st:.0{options.precision}f} "
                f"{et:.0{options.precision}f} {content}\n"
            )
        except Exception as e:
            raise ValueError(f"could not parse {name} line {no + 1}") from e


if __name__ == "__main__":
    main()
