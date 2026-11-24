# Computing Systems Investigator

[![ci](https://github.com/PrafullJ0shi/computing-systems-investigator/actions/workflows/ci.yml/badge.svg)](https://github.com/PrafullJ0shi/computing-systems-investigator/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE)](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows)
[![Python 3.9+](https://img.shields.io/badge/Python-3.9%2B-3776AB)](https://www.python.org/downloads/windows/)

Local collectors for a Windows laptop, and a small Python project that runs in a virtual environment.

The device profile, the browser-task samples, and the virtual-environment comparison are produced by running the collectors on that laptop. The GitHub Actions workflow runs the same virtual-environment steps on a hosted runner as a smoke test. Output from that job is remote. It is not evidence about the laptop.

## Reproduce on Windows

Use Windows 10 or Windows 11 and Windows PowerShell 5.1. Python 3.9 or newer is required for Mission 3 because `project/requirements.txt` pins `rich==15.0.0`. Administrator rights are not required. Mission 3 needs a network connection while `pip` installs packages into `project\.venv`.

1. Clone the repository and open PowerShell.
2. Change to the repository root.
3. Open `report/REPORT_TEMPLATE.md`. Write the Mission 3 prediction, in your own words, before you continue. Record the local time next to it.
4. Run:

```text
powershell -ExecutionPolicy Bypass -File collect\run-all.ps1
```

`-ExecutionPolicy Bypass` applies only to that process. It does not change the stored execution policy.

5. Follow the prompts. Mission 2 samples for about 20 seconds at each of four stages and names the Task Manager screenshots to take during each sample. The checklist is also written under `evidence\raw\`.
6. Mission 3 asks you to type `YES` only after the prediction is written. If `project\.venv` already exists, it asks you to type `DELETE` before removing that directory. It then creates the environment, removes it, and creates it again. The second environment is left in place.

Run the project later from the `project` directory:

```text
.\.venv\Scripts\python.exe -m isolated_env
```

Activation is not required. `docs/CONCEPTS.md` explains why.

If Python is missing, or older than 3.9, the collector stops Mission 3 and writes install steps to `evidence\raw\`. Use the current-user installer from [python.org](https://www.python.org/downloads/windows/). Leave "Install for all users" unchecked, and check "Add python.exe to PATH".

## Where the code runs

| Activity | Where it runs |
| --- | --- |
| `collect\run-all.ps1`, the device profile, the browser samples, and `project\.venv` | The investigator's Windows laptop. Local. |
| GitHub Actions workflow `ci` | A GitHub-hosted `windows-latest` runner. Remote. Do not paste that log into the report as a measurement of the laptop. |

## What to send

- The public repository URL.
- The report as PDF or DOCX, after `report/REPORT_TEMPLATE.md` has been copied to `report/REPORT.md` and the `<<FILL: ...>>` markers have been replaced from your own run.
- `evidence/summary.md`, after you have read its redaction check.
- The Task Manager screenshots named in that summary.
- A file from `evidence/raw/` only after you have read it. The command log and the console transcript can contain your username inside a path or in the transcript header.

`evidence/summary.md`, `evidence/raw/`, and `evidence/screenshots/` are gitignored so a later commit does not publish the laptop's profile.

## Safety

The collectors do not ask for administrator rights. They do not change the registry, the firewall, Windows Update, or the execution policy. They do not request serial numbers, MAC addresses, IP addresses, usernames, or the computer name.

Mission 1 reads CIM classes and a small set of cmdlets, and keeps a whitelist of properties. Mission 2 reads performance counters and process working sets. It does not read command lines or window titles. Mission 3 writes only `project\.venv` and `evidence\`. Deleting a virtual environment is limited to a directory named `.venv` inside this repository, or to a `csi-smoke-*` directory under `TEMP` when the remote smoke test runs.

Read `evidence/summary.md` before you send it. The script redacts the user-profile path, a username path segment, the computer name, MAC addresses, and private IP addresses in the values it copies. The check at the bottom of the summary reports anything it still finds.

## Layout

| Path | Purpose |
| --- | --- |
| `collect\run-all.ps1` | Entry point. |
| `collect\mission1-device-profile.ps1` | Device profile. |
| `collect\mission2-task-sampler.ps1` | Before, during, after, and on-closing samples. |
| `collect\mission3-venv-investigation.ps1` | Virtual-environment investigation. `-Smoke` is the remote check. |
| `collect\py\probe_interpreter.py` | JSON probe run by both interpreters. |
| `project\` | The small program and its tests. |
| `docs\CONCEPTS.md` | What a virtual environment isolates. |
| `report\REPORT_TEMPLATE.md` | Report structure and placeholders. |
| `report\build.py` | Builds the filled report with pandoc. |

## Tests

From `project`, with Python 3.10 or newer (`pytest==9.2.0` requires 3.10; the project itself requires 3.9):

```text
python -m pip install -r requirements-dev.txt
python -m pytest tests -q
```

## Report

```text
copy report\REPORT_TEMPLATE.md report\REPORT.md
```

Replace every marker from `evidence\summary.md` and your screenshots. Then:

```text
python report\build.py
```

Pandoc is required: https://pandoc.org/installing.html

```text
pandoc report/REPORT.md -o report/dist/Computing-Systems-Investigator.docx
pandoc report/REPORT.md -o report/dist/Computing-Systems-Investigator.pdf
```

PDF output also needs a PDF engine. The DOCX needs only pandoc.

## License

MIT. See `LICENSE`.
