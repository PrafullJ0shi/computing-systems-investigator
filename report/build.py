"""Build a filled report into DOCX or PDF with pandoc.

This script does not fill placeholders and does not invent measurements.
Copy report/REPORT_TEMPLATE.md to report/REPORT.md, replace every
<<FILL: ...>> marker from your own evidence, then run:

    python report/build.py

Pandoc is required: https://pandoc.org/installing.html

DOCX needs only pandoc. PDF also needs a PDF engine that pandoc can find
(for example wkhtmltopdf or tectonic). If PDF conversion fails, send the
DOCX.

Equivalent commands, from the repository root:

    pandoc report/REPORT.md -o report/dist/Computing-Systems-Investigator.docx
    pandoc report/REPORT.md -o report/dist/Computing-Systems-Investigator.pdf
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "report" / "REPORT.md"
TEMPLATE = ROOT / "report" / "REPORT_TEMPLATE.md"
DIST = ROOT / "report" / "dist"
DOCX = DIST / "Computing-Systems-Investigator.docx"
PDF = DIST / "Computing-Systems-Investigator.pdf"


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    allow_placeholders = "--allow-placeholders" in args

    if not SOURCE.exists():
        print("No filled report at report/REPORT.md.")
        print("Copy the template and replace every marker from your own evidence:")
        print("  copy report\\REPORT_TEMPLATE.md report\\REPORT.md")
        print("Template:", TEMPLATE)
        print()
        print("Then install pandoc from https://pandoc.org/installing.html and run:")
        print("  python report\\build.py")
        print()
        print("Or call pandoc directly:")
        print("  pandoc report/REPORT.md -o report/dist/Computing-Systems-Investigator.docx")
        print("  pandoc report/REPORT.md -o report/dist/Computing-Systems-Investigator.pdf")
        return 1

    text = SOURCE.read_text(encoding="utf-8")
    if "<<FILL:" in text and not allow_placeholders:
        print("report/REPORT.md still contains <<FILL: ...>> markers.")
        print("Replace them from evidence/summary.md and your screenshots.")
        print("The script will not build a submission that still has empty markers.")
        print("Pass --allow-placeholders only for a private draft.")
        return 2

    pandoc = shutil.which("pandoc")
    if pandoc is None:
        print("pandoc was not found on PATH.")
        print("Install it from https://pandoc.org/installing.html")
        print("The filled Markdown at report/REPORT.md is ready for that step.")
        return 1

    DIST.mkdir(parents=True, exist_ok=True)
    docx = subprocess.run(
        [pandoc, str(SOURCE), "-o", str(DOCX), "--from", "markdown", "--standalone"],
        check=False,
    )
    if docx.returncode != 0:
        print("pandoc could not write the DOCX.")
        return docx.returncode
    print("Wrote", DOCX)

    pdf = subprocess.run(
        [pandoc, str(SOURCE), "-o", str(PDF), "--from", "markdown", "--standalone"],
        check=False,
    )
    if pdf.returncode != 0:
        print("DOCX was written. PDF was not, because no PDF engine is available.")
        print("Send the DOCX, or install a PDF engine and run this script again.")
        return 0
    print("Wrote", PDF)
    return 0


if __name__ == "__main__":
    sys.exit(main())
