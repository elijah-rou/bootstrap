#!/usr/bin/env python3
"""Offline grouping, precision, and output checks for modelusage."""

import contextlib
import csv
import importlib.machinery
import importlib.util
import io
import json
import sys
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/modelusage"
LOADER = importlib.machinery.SourceFileLoader("modelusage", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
usage = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = usage
with patch.object(sys, "dont_write_bytecode", True):
    LOADER.exec_module(usage)


def row(host="alpha", source="pi", date="2021-01-01", model="model-a", tokens=1, cost=0.1):
    return usage.UsageRow(host, source, date, model, tokens, tokens * 2, tokens * 3, tokens * 4, cost)


def output(rows, output_format, period="daily"):
    stream = io.StringIO()
    with patch.object(sys, "argv", ["modelusage", "--hosts", "localhost", "--format", output_format, "--period", period]), \
            patch.object(usage, "normalize_hosts", return_value=["fixture"]), \
            patch.object(usage, "collect_host", return_value=(rows, [])), contextlib.redirect_stdout(stream):
        status = usage.main()
    return status, stream.getvalue()


def test_export_grouping_and_order():
    rows = [row(host="beta"), row(source="claude-code"), row(model="model-b"), row(tokens=2), row()]
    result = usage.aggregate(rows)
    assert [(r.host, r.source, r.model) for r in result] == [
        ("alpha", "claude-code", "model-a"), ("alpha", "pi", "model-a"),
        ("alpha", "pi", "model-b"), ("beta", "pi", "model-a"),
    ]
    assert result[1] == row(tokens=3, cost=0.2)

def test_period_grouping_and_calendar_boundaries():
    rows = [row(), row(host="beta", source="claude-code", date="2021-01-03", tokens=2),
            row(date="2021-01-04", tokens=4), row(model="model-b", cost=2)]
    result = usage.period_totals(rows, "weekly")
    assert [(r.date, r.model, r.input_tokens) for r in result] == [
        ("2021-W01", "model-a", 4), ("2020-W53", "model-b", 1), ("2020-W53", "model-a", 3),
    ]
    assert all(r.host == r.source == "" for r in result)
    for period, expected in (("daily", "2021-01-01"), ("weekly", "2020-W53"),
                             ("monthly", "2021-01"), ("yearly", "2021")):
        assert usage.period_key("2021-01-01", period) == expected

def test_integer_precision_and_ordered_float_addition():
    rows = [row(tokens=2**60, cost=1e16), row(cost=1), row(cost=1)]
    for result in (usage.aggregate(rows), usage.period_totals(rows, "yearly")):
        total = result[0]
        assert (total.input_tokens, total.output_tokens, total.cache_creation_tokens,
                total.cache_read_tokens) == tuple((2**60 + 2) * i for i in range(1, 5))
        assert isinstance(total.input_tokens, int)
        assert total.cost_usd == 1e16

def test_stable_period_ties():
    result = usage.period_totals([row(model="z"), row(model="a")], "daily")
    assert [r.model for r in result] == ["z", "a"]

def test_output_formats():
    rows = [row(tokens=2), row()]
    status, text = output(rows, "json")
    assert status == 0
    assert json.loads(text) == [row(tokens=3, cost=0.2).__dict__]
    _, text = output(rows, "csv")
    assert list(csv.reader(io.StringIO(text)))[1] == [
        "2021-01-01", "alpha", "pi", "model-a", "3", "6", "9", "12", "0.200000"]
    _, text = output(rows, "markdown")
    assert "| 2021-01-01 | alpha | pi | model-a | 3 | 6 | 9 | 12 | 0.2000 |\n" in text
    assert text.endswith("\nTotal cost: $0.2000\n")
    _, text = output(rows, "box", "weekly")
    assert "2020-W53" in text
    assert "$0.20" in text
    assert "Total" in text

def test_empty_results():
    assert usage.aggregate([]) == []
    assert usage.period_totals([], "monthly") == []
    for output_format in ("json", "csv", "markdown", "box"):
        status, text = output([], output_format)
        assert status == 2
        assert text


if __name__ == "__main__":
    for case in (test_export_grouping_and_order, test_period_grouping_and_calendar_boundaries,
                 test_integer_precision_and_ordered_float_addition, test_stable_period_ties,
                 test_output_formats, test_empty_results):
        case()
        print(f"PASS {case.__name__}")
