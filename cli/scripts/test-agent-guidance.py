# Exercises installed agent instructions, refresh, hook prompts, and normal completion.
# Exports a remote-only CLI E2E entry point with isolated agent/config directories.
# Dependencies: Python stdlib and the compiled hiboss binary on a grok host.

import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BINARY = ROOT / 'cli/target/debug/hiboss'
BEGIN = '<!-- hiboss:panels:begin -->'
END = '<!-- hiboss:panels:end -->'
OLD = '<!-- hiboss:begin -->\nNEVER just stop; ask for next steps.\n<!-- hiboss:end -->'


def run(directory: pathlib.Path, *arguments: str, ok: bool = True) -> subprocess.CompletedProcess:
    environment = {**os.environ, 'XDG_CONFIG_HOME': str(directory / 'config'),
                   'HIBOSS_PROJECT_DIR': str(directory),
                   'PATH': str(BINARY.parent) + os.pathsep + os.environ['PATH']}
    result = subprocess.run([str(BINARY), *arguments], cwd=directory, env=environment,
                            capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
    assert (result.returncode == 0) == ok, (arguments, result.stdout, result.stderr)
    return result


def install_and_refresh(directory: pathlib.Path) -> None:
    codex = directory / '.codex/AGENTS.md'
    claude = directory / '.claude/CLAUDE.md'
    codex.parent.mkdir()
    claude.parent.mkdir()
    codex.write_text(f'Preserve Codex rules.\n{BEGIN}\nOutdated panel instructions.\n{END}\nTail.\n')
    claude.write_text(f'Preserve Claude rules.\n{OLD}\n')
    run(directory, 'setup', 'agents', '--home-dir', str(directory))
    for path in [codex, claude]:
        content = path.read_text()
        assert 'Preserve' in content and content.count(BEGIN) == 1
        assert 'Prefer HiBoss' in content and 'hiboss request' in content
        assert 'NEVER just stop' not in content and 'Outdated' not in content
    assert 'Tail.' in codex.read_text()
    before = [p.read_bytes() for p in [codex, claude]]
    run(directory, 'setup', 'agents', '--home-dir', str(directory))
    assert before == [p.read_bytes() for p in [codex, claude]]
    guide = directory / '.config/hiboss/panel-agent-guide.md'
    assert guide.read_text() == run(directory, 'panel', 'guide').stdout.rstrip('\n') + '\n'
    assert '"kind": "intake"' in guide.read_text()
    example = json.loads(guide.read_text().split('```json\n')[1].split('```')[0])
    publication = directory / 'report.json'
    publication.write_text(json.dumps(example))
    run(directory, 'panel', 'validate', str(publication))


def dry_run_and_invalid_markers(directory: pathlib.Path) -> None:
    destination = directory / 'dry'
    run(directory, 'setup', 'agents', '--home-dir', str(destination), '--dry-run')
    assert not destination.exists()
    destination.mkdir()
    codex = destination / '.codex/AGENTS.md'
    claude = destination / '.claude/CLAUDE.md'
    codex.parent.mkdir()
    claude.parent.mkdir()
    codex.write_text('Keep unchanged.\n')
    for malformed in [END, BEGIN, f'{BEGIN}\nx\n{END}\n{BEGIN}']:
        claude.write_text(malformed)
        run(directory, 'setup', 'agents', '--home-dir', str(destination), ok=False)
        assert codex.read_text() == 'Keep unchanged.\n' and claude.read_text() == malformed
        assert not (destination / '.config').exists()


def hooks_refresh_and_remove(directory: pathlib.Path) -> None:
    project = directory / 'project'
    project.mkdir()
    instructions = project / '.claude/CLAUDE.md'
    instructions.parent.mkdir()
    instructions.write_text(f'Keep project rules.\n{OLD}\n')
    for _ in range(2):
        run(directory, 'setup', 'hooks', '--dir', str(project))
        content = instructions.read_text()
        assert content.count(BEGIN) == 1 and 'hiboss request' in content
        assert 'NEVER just stop' not in content
    run(directory, 'setup', 'hooks', '--dir', str(project), '--remove')
    assert instructions.read_text().strip() == 'Keep project rules.'


def session_hooks(directory: pathlib.Path) -> None:
    assert run(directory, 'hook', 'stop').returncode == 0
    try:
        result = run(directory, 'hook', 'session-start')
        assert 'Prefer HiBoss' in result.stdout and 'hiboss request' in result.stdout
        assert 'NEVER just stop' not in result.stdout
        assert 'proceed safely on timeout' not in result.stdout
    finally:
        run(directory, 'hook', 'stop')


def main() -> None:
    with tempfile.TemporaryDirectory(prefix='hiboss-agent-e2e-') as temporary:
        directory = pathlib.Path(temporary)
        install_and_refresh(directory)
        dry_run_and_invalid_markers(directory)
        hooks_refresh_and_remove(directory)
        session_hooks(directory)
    print('PASS: 4 agent guidance flows — install/refresh, dry-run/invalid markers, hook setup/removal, session start/stop')


if __name__ == '__main__':
    main()
