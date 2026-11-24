"""Put the project directory on sys.path so tests can import isolated_env."""

import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[1]
project_text = str(PROJECT_DIR)
if project_text not in sys.path:
    sys.path.insert(0, project_text)
