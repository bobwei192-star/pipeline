#!/usr/bin/env python3
"""Compare good vs bad kernel ComfyUI SDXL benchmark JSON results."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load_result(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path}: root must be an object")
    return data


def median_sec(data: dict[str, Any]) -> float | None:
    value = data.get("median_sec")
    if value is None:
        return None
    return float(value)


def classify(good_median: float | None, bad_median: float | None) -> tuple[str, float | None, float | None]:
    """Return (verdict, slowdown_ratio, throughput_drop)."""
    if good_median is None or bad_median is None or good_median <= 0:
        return "BLOCKER", None, None

    slowdown = bad_median / good_median
    drop = 1.0 - (good_median / bad_median)

    if slowdown >= 5.0:
        return "BLOCKER", slowdown, drop
    if drop > 0.20:
        return "FAIL", slowdown, drop
    if drop >= 0.10:
        return "WARNING", slowdown, drop
    return "PASS", slowdown, drop


def format_summary(
    good: dict[str, Any],
    bad: dict[str, Any],
    verdict: str,
    slowdown: float | None,
    drop: float | None,
) -> str:
    lines = [
        "## ROCm kernel regression compare",
        "",
        f"- good kernel: `{good.get('kernel_release', '?')}` (role={good.get('kernel_role', '?')})",
        f"- bad kernel: `{bad.get('kernel_release', '?')}` (role={bad.get('kernel_role', '?')})",
        f"- good median_sec: `{good.get('median_sec')}`",
        f"- bad median_sec: `{bad.get('median_sec')}`",
        f"- good timeout_count: `{good.get('timeout_count', 0)}`",
        f"- bad timeout_count: `{bad.get('timeout_count', 0)}`",
    ]
    if slowdown is not None:
        lines.append(f"- slowdown_ratio: `{slowdown:.3f}x`")
    if drop is not None:
        lines.append(f"- throughput_drop: `{drop * 100:.1f}%`")
    lines.extend(["", f"**Verdict: {verdict}**", ""])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--good", required=True, type=Path, help="Baseline (good kernel) JSON")
    parser.add_argument("--bad", required=True, type=Path, help="Candidate (bad kernel) JSON")
    parser.add_argument(
        "--summary",
        type=Path,
        default=None,
        help="Optional path to write markdown summary (e.g. $GITHUB_STEP_SUMMARY)",
    )
    args = parser.parse_args(argv)

    good = load_result(args.good)
    bad = load_result(args.bad)
    verdict, slowdown, drop = classify(median_sec(good), median_sec(bad))
    summary = format_summary(good, bad, verdict, slowdown, drop)
    print(summary)

    if args.summary is not None:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(summary, encoding="utf-8")
    elif "GITHUB_STEP_SUMMARY" in __import__("os").environ:
        summary_path = Path(__import__("os").environ["GITHUB_STEP_SUMMARY"])
        with summary_path.open("a", encoding="utf-8") as fh:
            fh.write(summary)
            fh.write("\n")

    if verdict in ("BLOCKER", "FAIL"):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
