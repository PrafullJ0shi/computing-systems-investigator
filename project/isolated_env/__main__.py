"""Allow `python -m isolated_env` from the project directory."""

import sys

from isolated_env.report import main

if __name__ == "__main__":
    sys.exit(main())
