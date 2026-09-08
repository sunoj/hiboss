# Exercises global guidance installation through the built CLI in a temporary home.
# Verifies refresh, idempotency, dry-run, and preservation of unrelated instructions.
# Dependencies: Python stdlib and cli/target/debug/hiboss; no credentials or network.

import pathlib
import json
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BINARY = ROOT / 'cli/target/debug/hiboss'


def main() -> None:
    with tempfile.TemporaryDirectory(prefix='hiboss-guidance-') as directory:
        home = pathlib.Path(directory)
        codex = home / '.codex/AGENTS.md'
        codex.parent.mkdir()
        codex.write_text('# Existing rules\nRun E2E only on the authorized remote host.\n')
        command = [str(BINARY), 'setup', 'agents', '--home-dir', str(home)]
        subprocess.run(command + ['--dry-run'], check=True, capture_output=True)
        assert not (home / '.claude').exists()
        subprocess.run(command, check=True, capture_output=True)
        first = codex.read_text()
        assert first.startswith('# Existing rules\nRun E2E only on the authorized remote host.')
        assert first.count('<!-- hiboss:panels:begin -->') == 1
        assert 'hiboss panel' in (home / '.claude/CLAUDE.md').read_text()
        assert '"passed": 13' in (home / '.config/hiboss/panel-agent-guide.md').read_text()
        subprocess.run(command, check=True, capture_output=True)
        assert codex.read_text() == first
        codex.write_text(first.replace('Dynamic notifications / live cards / Panels', 'OUTDATED_GUIDANCE'))
        subprocess.run(command, check=True, capture_output=True)
        assert codex.read_text() == first
        codex.write_text('<!-- hiboss:panels:begin -->broken')
        result = subprocess.run(command, capture_output=True)
        assert result.returncode != 0
        assert codex.read_text() == '<!-- hiboss:panels:begin -->broken'
        guide = subprocess.run([str(BINARY), 'panel', 'guide'], check=True, capture_output=True, text=True)
        assert 'Finish and verify' in guide.stdout
        example = json.loads(guide.stdout.split('```json\n')[1].split('```')[0])
        publication = home / 'example.json'
        publication.write_text(json.dumps(example))
        subprocess.run([str(BINARY), 'panel', 'validate', str(publication)], check=True, capture_output=True)
        print('PASS agent guidance: discover → preview → install → refresh → preserve → reject broken markers')


if __name__ == '__main__':
    main()
