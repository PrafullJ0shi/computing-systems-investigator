"""Describe the Python interpreter that is running this program.

The investigation compares this output between a virtual environment and
the base interpreter. The program reads interpreter state only. It does
not read personal files, device identifiers, or the network.
"""

from __future__ import annotations

import io
import sys
from typing import Any


def normalise_prefix(path: str) -> str:
    """Fold a Windows or POSIX prefix so the same directory compares equal.

    Windows accepts either slash and ignores case. A trailing separator
    does not make a different directory. The comparison is written out
    here so it does not depend on the host running the tests.
    """

    text = path.strip().replace("\\", "/")
    while text.endswith("/") and len(text) > 3:
        text = text[:-1]
    return text.casefold()


def is_virtual_environment(prefix: str, base_prefix: str) -> bool:
    """Return True when the two prefixes are different directories.

    Inside a virtual environment, sys.prefix names the environment and
    sys.base_prefix names the base installation.
    """

    if not prefix or not base_prefix:
        return False
    return normalise_prefix(prefix) != normalise_prefix(base_prefix)


def package_version(distribution: str) -> str:
    """Return the installed distribution version, or an empty string.

    rich 15 does not set rich.__version__. The version recorded by pip is
    available from importlib.metadata, which is part of the standard library.
    """

    try:
        from importlib.metadata import version
    except Exception:
        return ""
    try:
        return version(distribution)
    except Exception:
        return ""


def inspect_interpreter() -> dict[str, Any]:
    """Collect the facts the investigation compares. Importing rich is one of them."""

    info: dict[str, Any] = {
        "version": sys.version.split()[0] if sys.version else "",
        "executable": sys.executable,
        "prefix": sys.prefix,
        "base_prefix": sys.base_prefix,
        "in_virtual_environment": is_virtual_environment(sys.prefix, sys.base_prefix),
        "rich_importable": False,
        "rich_version": "",
        "rich_location": "",
        "rich_error_type": "",
        "rich_error": "",
    }
    try:
        import rich
    except Exception as exc:
        # The failure itself is evidence. Record the type and the message.
        info["rich_error_type"] = type(exc).__name__
        info["rich_error"] = str(exc)
        return info

    info["rich_importable"] = True
    version = package_version("rich")
    if not version:
        version = getattr(rich, "__version__", "")
    info["rich_version"] = "" if version is None else str(version)
    location = getattr(rich, "__file__", "")
    info["rich_location"] = "" if location is None else str(location)
    return info


_ROWS = (
    ("version", "Python version"),
    ("executable", "Executable"),
    ("prefix", "sys.prefix"),
    ("base_prefix", "sys.base_prefix"),
    ("in_virtual_environment", "Virtual environment"),
    ("rich_importable", "rich importable"),
    ("rich_version", "rich version"),
    ("rich_location", "rich location"),
)


def render_plain(info: dict[str, Any]) -> str:
    """Plain-text report used when rich cannot be imported."""

    lines = ["Python environment", ""]
    for key, label in _ROWS:
        lines.append(f"{label}: {info.get(key, '')}")
    if not info.get("rich_importable"):
        lines.append(
            "rich error: {0}: {1}".format(
                info.get("rich_error_type", ""),
                info.get("rich_error", ""),
            )
        )
    lines.append("Renderer: plain")
    return "\n".join(lines) + "\n"


def render_rich(info: dict[str, Any]) -> str:
    """Table rendered with rich. Raises ImportError if rich is absent."""

    from rich.console import Console
    from rich.table import Table

    buffer = io.StringIO()
    console = Console(file=buffer, width=120, force_terminal=False, color_system=None)
    table = Table(title="Python environment")
    table.add_column("Item")
    table.add_column("Value")
    for key, label in _ROWS:
        table.add_row(label, str(info.get(key, "")))
    if not info.get("rich_importable"):
        table.add_row(
            "rich error",
            "{0}: {1}".format(info.get("rich_error_type", ""), info.get("rich_error", "")),
        )
    table.add_row("Renderer", "rich")
    console.print(table)
    return buffer.getvalue()


def main(argv: list[str] | None = None) -> int:
    """Print the environment report and return 0.

    argv is accepted so tests can call main without touching the real
    command line. The program has no flags.
    """

    del argv
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    info = inspect_interpreter()
    if info.get("rich_importable"):
        try:
            text = render_rich(info)
        except Exception:
            text = render_plain(info)
    else:
        text = render_plain(info)
    sys.stdout.write(text)
    sys.stdout.flush()
    return 0
