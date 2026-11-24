# What a Python virtual environment isolates

A virtual environment is a directory that gives one project its own third-party packages. Python creates it on top of an existing installation, called the base interpreter. The standard library stays in that base installation. PEP 405 describes this split, and the `venv` documentation is the current reference.

The project in this repository is created with:

```text
python -m venv project\.venv
```

On Windows that produces this layout:

```text
project\.venv\
    pyvenv.cfg
    Scripts\
        python.exe
        pip.exe
        Activate.ps1
    Lib\
        site-packages\
```

## What is isolated

**The interpreter link.** `pyvenv.cfg` records `home`, the directory of the base interpreter that created the environment. `Scripts\python.exe` is a copy or a symlink of that interpreter, not a second implementation of Python. When it starts, it reads `pyvenv.cfg`. After startup, `sys.prefix` is the environment directory and `sys.base_prefix` is the base installation. The documented test is `sys.prefix != sys.base_prefix`.

**site-packages.** With the default `include-system-site-packages = false`, imports of third-party packages come from `Lib\site-packages` inside the environment. The base installation's site-packages, and the per-user site-packages from PEP 370, are left off `sys.path`. A package of the same name can exist in both places. Each import uses the copy that is on that interpreter's path.

**Scripts.** A package that installs a command puts that command in `Scripts\`. `pip` inside the environment installs into this environment without a separate target flag.

**PATH, after activation.** `Scripts\Activate.ps1` prepends `Scripts` to `PATH` and sets `VIRTUAL_ENV`. Typing `python` or `pip` then finds this environment. Activation is a convenience. The `venv` documentation states that it is not required: running `Scripts\python.exe` by its path uses the environment, because that executable reads `pyvenv.cfg`. `VIRTUAL_ENV` is set only when the environment has been activated, so it is not a reliable test. Compare `sys.prefix` with `sys.base_prefix` instead.

Installing `rich` also installs the packages it depends on. Those dependencies land in the same `site-packages`. A `pip list` comparison shows them.

## What is not isolated

**The operating system.** The process runs as the same user, with the same rights to files, the network, and other programs. A virtual environment is not a container and not a virtual machine.

**System libraries.** The interpreter loads DLLs and other shared libraries from the base installation and from Windows. The environment does not carry its own copy of the operating system.

**The base interpreter and the standard library.** `pyvenv.cfg` keeps a `version` and a `home`. `sys.base_prefix` still names the base installation. Deleting or upgrading that installation changes the environment. The environment does not contain a private copy of the standard library.

**Hardware.** CPU, memory, disk, and devices are the machine's. Timing and memory measurements taken inside the environment are measurements of that machine, subject to whatever else is running.

**Other software.** Browsers, editors, and packages installed for a different Python remain where they are. The environment does not hide them from the operating system. It only changes where this interpreter looks for third-party Python packages.

## Why a project uses one

The environment can hold the package versions that project was tried with, recorded in `requirements.txt`, without changing the interpreter used by other work. Deleting the directory removes those packages. Creating it again and installing the same requirements file rebuilds it. The `venv` documentation treats environments as disposable and tells you to recreate one rather than move it, because installed scripts store absolute paths.

## How to check the claim

Compare one base interpreter with one environment created from it:

- `sys.prefix`, `sys.base_prefix`, and `sys.path`
- `pyvenv.cfg` (`home`, `include-system-site-packages`, `version`)
- `pip list` in each interpreter
- an import of a package that was installed only into the environment, including the exception type if the base interpreter cannot import it
- the file path of that package when both interpreters can import it

On Python 3, a missing module is reported as `ModuleNotFoundError`. That class is a subclass of `ImportError`. Record the type the interpreter actually raised.

## References

- Python Software Foundation. `venv` — Creation of virtual environments. https://docs.python.org/3/library/venv.html
- Python Software Foundation. Virtual Environments and Packages. https://docs.python.org/3/tutorial/venv.html
- Python Software Foundation. `site` — Site-specific configuration hook. https://docs.python.org/3/library/site.html
- Python Enhancement Proposal 405. Python Virtual Environments. https://peps.python.org/pep-0405/
