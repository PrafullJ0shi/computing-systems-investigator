"""Print interpreter facts as JSON.

The Windows collector runs this file with the system interpreter and again
with the virtual environment's interpreter. It writes only JSON to stdout.
Paths may contain the account name; the collector redacts those in
evidence/summary.md and leaves this process's stdout in the local raw log.
"""

from __future__ import annotations

import json
import platform
import site
import sys


def package_version(distribution: str) -> str:
    try:
        from importlib.metadata import version
    except Exception:
        return ""
    try:
        return version(distribution)
    except Exception:
        return ""


def build_probe() -> dict:
    site_packages: list[str] = []
    site_packages_error = ""
    try:
        values = site.getsitepackages()
        site_packages = [str(item) for item in values]
    except Exception as exc:
        site_packages_error = "{0}: {1}".format(type(exc).__name__, exc)

    try:
        user_site = site.getusersitepackages()
        user_site_text = "" if user_site is None else str(user_site)
    except Exception as exc:
        user_site_text = ""
        site_packages_error = (site_packages_error + " " + str(exc)).strip()

    rich_info = {
        "importable": False,
        "version": "",
        "file": "",
        "error_type": "",
        "error": "",
    }
    try:
        import rich
    except Exception as exc:
        rich_info["error_type"] = type(exc).__name__
        rich_info["error"] = str(exc)
    else:
        rich_info["importable"] = True
        version = package_version("rich")
        if not version:
            version = getattr(rich, "__version__", "")
        location = getattr(rich, "__file__", "")
        rich_info["version"] = "" if version is None else str(version)
        rich_info["file"] = "" if location is None else str(location)

    return {
        "executable": sys.executable,
        "version": sys.version,
        "version_info": [sys.version_info[0], sys.version_info[1], sys.version_info[2]],
        "prefix": sys.prefix,
        "exec_prefix": sys.exec_prefix,
        "base_prefix": sys.base_prefix,
        "base_exec_prefix": sys.base_exec_prefix,
        "path": [str(item) for item in sys.path],
        "site_packages": site_packages,
        "site_packages_error": site_packages_error,
        "user_site": user_site_text,
        "enable_user_site": bool(getattr(site, "ENABLE_USER_SITE", False)),
        "platform": platform.platform(),
        "implementation": platform.python_implementation(),
        "rich": rich_info,
    }


def main() -> int:
    json.dump(build_probe(), sys.stdout, indent=2, ensure_ascii=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
