# Starts the isolated questionnaire CLI/Worker E2E execution on a grok host only.
# Exports a runnable entry point; reuses migration, test identity, and process cleanup.
# Dependencies: Python stdlib and the shared panel E2E harness.

import pathlib
import runpy

DIRECTORY = pathlib.Path(__file__).resolve().parent
HARNESS = runpy.run_path(str(DIRECTORY.parent / 'run-panel-e2e.py'))

if __name__ == '__main__':
    HARNESS['main'](DIRECTORY / 'test-flow.py', 'questionnaire-e2e')
