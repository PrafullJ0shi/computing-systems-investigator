"""Tests for the environment report. They do not read a device profile."""

import json
import subprocess
import sys
from pathlib import Path

import pytest

from isolated_env.report import (
    inspect_interpreter,
    is_virtual_environment,
    main,
    render_plain,
)


def test_distinct_prefixes_are_a_virtual_environment():
    assert is_virtual_environment(r"C:\work\project\.venv", r"C:\Python312") is True


def test_same_prefix_is_not_a_virtual_environment():
    assert is_virtual_environment(r"C:\Python312", r"C:\Python312") is False


def test_windows_case_and_trailing_slash_do_not_look_like_a_venv():
    assert is_virtual_environment(r"C:/Python312/", r"c:\python312") is False


def test_empty_prefix_is_not_a_virtual_environment():
    assert is_virtual_environment("", r"C:\Python312") is False


def test_inspect_interpreter_has_the_comparison_fields():
    info = inspect_interpreter()
    expected = {
        "version",
        "executable",
        "prefix",
        "base_prefix",
        "in_virtual_environment",
        "rich_importable",
        "rich_version",
        "rich_location",
        "rich_error_type",
        "rich_error",
    }
    assert expected <= set(info)
    assert info["in_virtual_environment"] is is_virtual_environment(
        info["prefix"], info["base_prefix"]
    )
    assert isinstance(info["rich_importable"], bool)


def test_plain_report_names_the_renderer_and_the_prefix():
    text = render_plain(inspect_interpreter())
    assert "sys.prefix" in text
    assert "Renderer: plain" in text


def test_main_prints_a_report_and_returns_zero(capsys):
    assert main([]) == 0
    captured = capsys.readouterr()
    assert "sys.prefix" in captured.out
    assert "Renderer" in captured.out


def test_installed_rich_reports_a_version_and_a_location():
    pytest.importorskip("rich")
    info = inspect_interpreter()
    assert info["rich_importable"] is True
    assert info["rich_version"]
    assert info["rich_location"].endswith(".py")


def test_rich_renderer_when_the_package_is_installed():
    pytest.importorskip("rich")
    from isolated_env.report import render_rich

    text = render_rich(inspect_interpreter())
    assert "Python environment" in text
    assert "Renderer" in text
    assert "rich" in text


def test_probe_script_prints_json():
    script = Path(__file__).resolve().parents[2] / "collect" / "py" / "probe_interpreter.py"
    completed = subprocess.run(
        [sys.executable, str(script)],
        check=False,
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0, completed.stderr
    payload = json.loads(completed.stdout)
    assert "prefix" in payload
    assert "base_prefix" in payload
    assert "path" in payload
    assert "rich" in payload
    assert "importable" in payload["rich"]
