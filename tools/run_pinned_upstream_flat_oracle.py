#!/usr/bin/env python3
"""Run the pinned upstream TSV stage while deliberately skipping Hail outputs.

Usage:
  python tools/run_pinned_upstream_flat_oracle.py \
    /path/to/clinvarbitration/checkout submission.txt.gz variant.txt.gz output-root

The checkout must be at commit 658b9f241eb2d43aa11214b153b19c1e18a16337.
The decision module is loaded without modification. Inert stand-ins satisfy its
Hail and loguru imports; execution stops when the upstream main function reaches
Hail, after it has written output-root.tsv.
"""
import importlib.util
from pathlib import Path
import subprocess
import sys
import types

PINNED_COMMIT = "658b9f241eb2d43aa11214b153b19c1e18a16337"


class StopAfterTSV(Exception):
    """Expected stop immediately after the upstream TSV is written."""


class DummyContext:
    @staticmethod
    def init_spark(*args, **kwargs):
        raise StopAfterTSV()


class DummyTable:
    pass


class Logger:
    def info(self, message):
        print(message, flush=True)

    def warning(self, message):
        print(f"WARNING: {message}", flush=True)


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: run_pinned_upstream_flat_oracle.py CHECKOUT "
            "SUBMISSION_SUMMARY VARIANT_SUMMARY OUTPUT_ROOT"
        )
    checkout, submissions, variants, output_root = map(Path, sys.argv[1:])
    commit = subprocess.check_output(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
    ).strip()
    if commit != PINNED_COMMIT:
        raise SystemExit(f"checkout is {commit}; expected {PINNED_COMMIT}")

    hail = types.ModuleType("hail")
    hail.Table = DummyTable
    hail.context = DummyContext
    hail.tint32 = object()
    sys.modules["hail"] = hail
    loguru = types.ModuleType("loguru")
    loguru.logger = Logger()
    sys.modules["loguru"] = loguru

    source = checkout / "src/clinvarbitration/scripts/resummarise_clinvar.py"
    spec = importlib.util.spec_from_file_location("pinned_resummarise_clinvar", source)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    try:
        module.main(
            subs=str(submissions),
            variants=str(variants),
            output_root=str(output_root),
            assembly="GRCh38",
        )
    except StopAfterTSV:
        print("Stopped after the upstream TSV stage; Hail/VCF/PM5 were not run.")


if __name__ == "__main__":
    main()
