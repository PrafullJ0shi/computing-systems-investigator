# The Computing Systems Investigator

Individual assignment. Suggested length: 6–10 pages, excluding source code and supplementary evidence.

Instruction (delete before submission): copy this file to `report/REPORT.md`, replace every `<<FILL: ...>>` marker from your own run, and delete the instruction lines. Do not invent a number, a screenshot, or a command output. If a value was not exposed, write `not exposed` and keep the source.

## Cover page

| Item | Entry |
| --- | --- |
| Assignment title | The Computing Systems Investigator |
| Course | <<FILL: course>> |
| Name | <<FILL: your name>> |
| Roll number | <<FILL: roll number>> |
| Primary device | Windows laptop |
| Operating system | <<FILL: from evidence/summary.md, Caption, Version, BuildNumber, and OSArchitecture>> |
| Mission 3 option | Option 4 — What does an isolated environment actually mean? |
| Repository | <<FILL: public repository URL>> |

Serial numbers, MAC addresses, private IP addresses, usernames, and the computer name are omitted.

## Mission 1 — Know your machine

The profile below comes from `collect/mission1-device-profile.ps1` on the primary laptop. Each row is either observed on the device, omitted on purpose, or not exposed. A published specification, if you consult one, stays in its own column and needs a citation. The collector does not look up manufacturer pages for you.

| Component / area | Information | Value | Status | Source |
| --- | --- | --- | --- | --- |
| Device and operating system | Device type and model; operating system name, version, and architecture | <<FILL: from evidence/summary.md Mission 1>> | <<FILL: observed, omitted, or not exposed>> | Win32_ComputerSystem, Win32_SystemEnclosure, Win32_OperatingSystem |
| Processor | Vendor and model; cores and logical processors | <<FILL: from evidence/summary.md>> | <<FILL: status>> | Win32_Processor |
| Memory | RAM capacity and type. Cache only where the class returned it | <<FILL: from evidence/summary.md. Keep TotalPhysicalMemory and the sum of module capacities if both appear. Keep the raw SMBIOSMemoryType code.>> | <<FILL: status>> | Win32_ComputerSystem, Win32_PhysicalMemory, Win32_CacheMemory, Win32_Processor cache properties |
| Storage | Storage type, total capacity, and free space on fixed volumes | <<FILL: from evidence/summary.md. Use Get-PhysicalDisk MediaType for HDD, SSD, SCM, or Unspecified.>> | <<FILL: status>> | Win32_DiskDrive, Get-PhysicalDisk, Win32_LogicalDisk |
| Network and I/O | Connection type and status; one input/output capability | <<FILL: from evidence/summary.md. Adapters are type and status only.>> | <<FILL: status>> | Get-NetAdapter or Win32_NetworkAdapter; Win32_VideoController; Win32_Keyboard; Win32_PointingDevice |
| One interesting feature | One observed specification | <<FILL: the fact you chose>> | observed | <<FILL: the source row>> |

Status vocabulary:

- `observed` — the laptop returned this value.
- `omitted` — the collector did not read it, because it is a serial number, MAC address, IP address, username, or computer name.
- `not exposed` — the query returned nothing. Do not replace it with a guess.
- `published specification` — you read it in a manufacturer document. Cite that document and keep it separate from the observed value.

### One interpretation

<<FILL: choose one observed specification and explain what it suggests about the laptop's capability or a limit. Two to five sentences. Use only values from the table. If you also cite a published specification, say which sentence comes from the device and which comes from the document.>>

### Evidence

Command output: `evidence/summary.md`, Mission 1, and the matching `evidence/raw/m1-profile-*.txt` after you have checked it for personal data.

Optional screenshot: Settings, System, About, with the device name covered. File: <<FILL: filename, or "not taken">>.

## Mission 2 — Follow a computing task

Chosen activity: open a browser and load several tabs.

| Item | Entry |
| --- | --- |
| Browser | <<FILL: the browser you typed at the prompt>> |
| Pages | <<FILL: the public pages you typed>> |
| Where it ran | Local, on the primary Windows laptop |
| Collector | `collect/mission2-task-sampler.ps1` |
| Sample length | About 20 seconds at each stage. <<FILL: the sample counts from the stage statistics>> |

The script asks you to press Enter at each stage, then samples CPU percent, available memory, process count, browser working set, disk counters, and network counters. Take the screenshots during that window. The script cannot take them.

Task Manager: Ctrl+Shift+Esc. If the window is small, click More details. Do not open the Users tab. On the network graph, crop or cover any IPv4 address, IPv6 address, or hardware address.

| Stage | What to do while the sample runs | Screenshots |
| --- | --- | --- |
| Before | Browser fully closed, including a tray icon. Machine idle. | `m2-before-processes.png`, `m2-before-cpu.png`, `m2-before-memory.png`, `m2-before-disk.png`, `m2-before-network.png` |
| During | Pages loading. Browser left open. | `m2-during-processes.png`, `m2-during-cpu.png`, `m2-during-memory.png`, `m2-during-disk.png`, `m2-during-network.png` |
| After | Pages finished loading. Browser still open. | `m2-after-processes.png`, `m2-after-cpu.png`, `m2-after-memory.png`, `m2-after-disk.png`, `m2-after-network.png` |
| On closing | Browser closed. If it is still listed, say so. | `m2-on-closing-processes.png`, `m2-on-closing-cpu.png`, `m2-on-closing-memory.png`, `m2-on-closing-disk.png`, `m2-on-closing-network.png` |

Save them under `evidence/screenshots/`. Put Processes, CPU, and Memory in the report body. Put Disk and Network in an appendix so the report stays within the suggested length.

### Observation record

Means below are the arithmetic means calculated in `evidence/summary.md` from the CSV. Copy them. Leave a cell blank when the summary shows a blank mean, and write `not exposed` in the evidence column if the counter was missing.

| Stage | What did you observe? | Evidence captured |
| --- | --- | --- |
| Before | <<FILL: baseline CPU %, available memory, process count, browser working set>> | <<FILL: CSV stage `before` and screenshot filenames>> |
| During | <<FILL: what moved while the pages were loading>> | <<FILL: CSV stage `during` and screenshot filenames>> |
| After | <<FILL: what remained after the pages settled>> | <<FILL: CSV stage `after` and screenshot filenames>> |
| On closing | <<FILL: what changed after the browser was closed>> | <<FILL: CSV stage `on-closing` and screenshot filenames>> |

### Explanation

<<FILL: what changed, and how that connects to the browser, the operating system, and the hardware. Name the resource that moved the most in your numbers. If the browser remained after the last window closed, say what the on-closing row shows.>>

### Limitation

<<FILL: at least one thing the laptop or the method did not let you see. You may discuss any of these only if it matches your run: Task Manager and PowerShell were open during the sample; a browser splits work across processes; WorkingSet64 can count shared pages more than once; the first rate-counter read was discarded before recording; % Disk Time can read 0 or above 100. Quote the column you are relying on.>>

## Mission 3 — Explore, experiment and build

Selected option: Option 4. What does an isolated environment actually mean?

### Investigation question

What does a Python virtual environment isolate on this laptop, and what does it still share with the base interpreter and the operating system?

The computing concept is process and package isolation for a Python project: `sys.prefix`, `sys.base_prefix`, `site-packages`, and activation. `docs/CONCEPTS.md` is the background. The conclusion has to follow the outputs you captured.

### Prediction

Write this section before you run the collector. The paragraph below is an example. Read it. If it is what you expect, rewrite it in your own words so you can explain it, and record the time. If it is not what you expect, replace it. After you have seen the results, do not change this section. If you already ran the collector, say that here instead of back-dating a prediction.

Confirmation, written before the run:

- I wrote or confirmed this prediction before running Mission 3.
- Local date and time: <<FILL: your clock, before you type YES>>
- Collector confirmation UTC, from `evidence/summary.md`: <<FILL: Prediction confirmation UTC. It should be later than the time above.>>

Example prediction:

> I expect a virtual environment created with `python -m venv` to use the same Python version as the base interpreter, because the environment is a directory laid on top of that interpreter rather than a second copy of Python. I expect `sys.prefix` inside the environment to point at `.venv`, and `sys.base_prefix` to point at the base installation. I expect `rich`, after it is installed into the environment, to import from `.venv\Lib\site-packages`. I expect the base interpreter to fail the import if `rich` is not installed for it, and I will record the exception type it actually raises. I expect deleting `.venv` and creating it again from `requirements.txt` to produce the same package versions. I expect the environment to leave the operating system, the hardware, and the base interpreter in place.

<<FILL: your prediction, written before the run>>

### Environment and procedure

| Item | Entry |
| --- | --- |
| Device | The same Windows laptop as Missions 1 and 2 |
| Environment | Local. The project runs as `project\.venv\Scripts\python.exe` on this laptop. |
| Tools | Windows PowerShell 5.1, the Python named in the summary, the `venv` module, `pip`, and `rich==15.0.0` |
| Program | `python -m isolated_env` from the `project` directory |

The collector follows these steps. Confirm them against the console transcript. If a step failed, describe the failure and stop the account at that step.

1. Record `where.exe python`, `where.exe py`, `where.exe python3`, and `py -0p` when the launcher exists.
2. Run `python -c` to print `sys.executable`, `sys.prefix`, `sys.base_prefix`, and `sys.path`, then `pip list`, on the base interpreter.
3. Create `project\.venv` with `python -m venv`.
4. Repeat the interpreter print, `pip list`, and the JSON probe inside the environment.
5. Install `project\requirements.txt` with the environment's pip.
6. Run `python -m isolated_env` with the environment's interpreter.
7. Import `rich` in the environment and in the base interpreter. Save the exception type and message when an import fails.
8. Compare `site-packages` paths and the two `pip list` results.
9. Save `pyvenv.cfg` and the size of the `.venv` directory.
10. In a child process only, dot-source `Activate.ps1` and record `where.exe python` and `sys.prefix`. The parent process does not activate the environment.
11. Delete `project\.venv` and repeat the create, install, and run once. Compare `pyvenv.cfg`, package versions, directory size, and the project exit code.
12. Leave the second environment in place.

### Actual evidence

Copy from `evidence/summary.md`. Do not type a value that is not in that file or in a raw file you have read.

| Evidence | Your result |
| --- | --- |
| Base interpreter version and executable | <<FILL: from the Mission 3 table>> |
| `sys.prefix` and `sys.base_prefix` inside the environment | <<FILL: from the isolation block>> |
| Does `base_prefix` match the base interpreter prefix? | <<FILL: yes or no, from the isolation block>> |
| `rich` in the environment (importable, version, file) | <<FILL>> |
| `rich` in the base interpreter | <<FILL: importable, or the captured error type and message. If the type is ModuleNotFoundError, write that type.>> |
| Do the `rich` file paths differ, if both imports worked? | <<FILL: differ, same, or not comparable>> |
| `site-packages` paths | <<FILL: the redacted paths>> |
| `pip list` difference, base versus run 1 | <<FILL>> |
| `pyvenv.cfg` home, include-system-site-packages, version | <<FILL: home will be redacted>> |
| Run 1 and run 2 size in bytes, and whether they matched | <<FILL>> |
| Run 1 and run 2 project exit codes | <<FILL>> |
| `pip list` difference, run 1 versus run 2 | <<FILL>> |
| Parent `where.exe python` unchanged after the child activation | <<FILL: true or false>> |
| Child activation output | <<FILL: one or two redacted lines, or "see summary">> |

### Working artefact

The artefact is the project in `project/` and the environment the collector builds at `project\.venv`.

- Source: `project/isolated_env/report.py`, `project/isolated_env/__main__.py`, `project/requirements.txt`
- Pinned package: `rich==15.0.0`
- Run, from the `project` directory: `.\.venv\Scripts\python.exe -m isolated_env`
- Execution evidence: <<FILL: the run 1 exit code and the renderer line from the command log or the summary. State whether the renderer was `rich` or `plain`.>>
- Public repository: <<FILL: URL>>

The program prints the interpreter paths and whether `rich` imported. That is the demonstration. It does not read personal files or device identifiers.

### Analysis

<<FILL: answer from your table, after the run. What did the environment isolate? What stayed shared? Use `sys.prefix`, `sys.base_prefix`, the `rich` file or the captured exception, `pyvenv.cfg`, and the pip comparison. Say what `include-system-site-packages` was. If the base interpreter also imported `rich`, explain the path comparison and do not claim an ImportError. If packages other than `rich` appeared, identify them as dependencies installed with it, using the pip output.>>

### Reproducibility and limitations

Another person can clone the public repository and run:

```text
powershell -ExecutionPolicy Bypass -File collect\run-all.ps1
```

Mission 3 can be repeated on its own only by running that entry point, or by running `collect\mission3-venv-investigation.ps1` after the prediction is written. The second `project\.venv` is the one left on disk.

Limits of this investigation:

<<FILL: what you could not observe or control. Include any step that failed. If you want a starting list to check against your log, consider: the base interpreter may already have had `rich`; directory sizes need not match to the byte when the package set matches; the environment still uses the base standard library; activation was shown in a child process so the collector's own PATH would stay unchanged; the GitHub Actions log is a remote smoke test and is not a measurement of this laptop. Keep only the points your evidence supports.>>

## Mission 4 — Engineering notebook

### Prompts

1. What was one prediction that turned out to be incorrect, incomplete, or more complicated than you expected?

   <<FILL>>

2. Which observation or result surprised you most? Why?

   <<FILL>>

3. What conclusion can you support directly with the evidence you collected?

   <<FILL: name the file or the table row>>

4. What could you not observe or measure on your device, and how did you work around that limitation?

   <<FILL>>

5. What would you investigate next if you had more time?

   <<FILL>>

6. One thoughtful question about computing systems that arose from your own investigation. This question is not graded.

   <<FILL>>

### Reflection

<<FILL: 150–200 words, written after the investigation. Describe what you understand now that you did not understand before. Count the words before you submit.>>

Word count: <<FILL: number>>

### AI-use record

| Item | What to record |
| --- | --- |
| AI tool(s) | Grok Bot assistant |
| Key prompts | <<FILL: the prompts that materially influenced the investigation. Write this honestly.>> |
| Relevant assistance | <<FILL: a short account of the assistance you actually relied on>> |
| Your decision | <<FILL: what you accepted, changed, rejected, or verified>> |
| Corrections | <<FILL: any inaccurate, incomplete, or unsupported suggestion, and how you checked it. If you found none, say what you checked.>> |
| Code assistance | <<FILL: which parts of the repository were drafted with assistance, and how you tested them on your own Windows laptop. A script does not become your evidence until you have run it locally.>> |

## References

Python Software Foundation. `venv` — Creation of virtual environments. Python 3 documentation. https://docs.python.org/3/library/venv.html

Python Software Foundation. Virtual Environments and Packages. Python 3 documentation. https://docs.python.org/3/tutorial/venv.html

Python Software Foundation. `site` — Site-specific configuration hook. Python 3 documentation. https://docs.python.org/3/library/site.html

Python Enhancement Proposal 405. Python Virtual Environments. https://peps.python.org/pep-0405/

Python Packaging Authority. pip documentation. https://pip.pypa.io/en/stable/

Python Packaging Authority. pip install. https://pip.pypa.io/en/stable/cli/pip_install/

Python Software Foundation. Python Releases for Windows. https://www.python.org/downloads/windows/

Python Software Foundation. Python launcher for Windows. https://docs.python.org/3/using/windows.html

Will McGugan and contributors. rich 15.0.0. https://pypi.org/project/rich/15.0.0/

Microsoft. Get-CimInstance. https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance

Microsoft. Get-PhysicalDisk. https://learn.microsoft.com/en-us/powershell/module/storage/get-physicaldisk

Microsoft. Get-NetAdapter. https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter

Microsoft. Get-Counter. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-counter

Microsoft. Get-Process. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-process

Microsoft. Win32_ComputerSystem. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem

Microsoft. Win32_OperatingSystem. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem

Microsoft. Win32_Processor. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-processor

Microsoft. Win32_PhysicalMemory. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-physicalmemory

Microsoft. Win32_DiskDrive. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-diskdrive

Microsoft. Win32_LogicalDisk. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk

Microsoft. Win32_CacheMemory. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-cachememory

Microsoft. Win32_SystemEnclosure. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-systemenclosure

Microsoft. Win32_NetworkAdapter. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-networkadapter

Microsoft. Win32_VideoController. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-videocontroller

Microsoft. where. https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/where

<<FILL: any manufacturer document you used for a published specification. Delete this row if you did not use one.>>

## Appendix A — Screenshot index

| File | Stage | In the report? |
| --- | --- | --- |
| <<FILL: evidence/screenshots/m2-before-processes.png>> | Before | Body |
| <<FILL: remaining files you actually saved>> | <<FILL>> | Body or appendix |

## Appendix B — How the report file is built

`report/build.py` does not fill markers. After `report/REPORT.md` is complete:

```text
python report\build.py
```

Pandoc commands, from the repository root:

```text
pandoc report/REPORT.md -o report/dist/Computing-Systems-Investigator.docx
pandoc report/REPORT.md -o report/dist/Computing-Systems-Investigator.pdf
```

Pandoc: https://pandoc.org/installing.html

## Submission checklist

- [ ] All four missions are in this report.
- [ ] The primary device and operating system are identified, without serial numbers, MAC addresses, private IP addresses, usernames, or the computer name.
- [ ] Mission 2 uses observations from the browser task I performed.
- [ ] Mission 3 is only Option 4.
- [ ] Mission 3 has a question, a prediction written beforehand, a procedure, actual evidence, and an explanation.
- [ ] The working artefact, the repository URL, and the reproduction steps are included.
- [ ] Mission 4 has the engineering notebook, a 150–200 word reflection, and the AI-use record.
- [ ] External sources are cited.
- [ ] The GitHub Actions log is identified as remote, and is not presented as a measurement of this laptop.
