# Exercises real Rust panel handlers against an isolated local Cloudflare Worker.
# Exports a runnable integration smoke test; uses test-only identities and files.
# Dependencies: Python stdlib, the panel-lifecycle-driver example, and local D1 seeds.

import json
import os
import time
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
os.environ['HIBOSS_PROJECT_DIR'] = str(ROOT)
BASE = os.environ.get('HIBOSS_PANEL_TEST_URL', 'http://127.0.0.1:8798')
DRIVER = ROOT / 'cli/target/debug/examples/panel-lifecycle-driver'
COMMAND = [str(DRIVER), '--server', BASE, '--key', 'hb_lifecycle_cli_test_only']


def session_path() -> pathlib.Path:
    value = str(ROOT)
    digest = 0xcbf29ce484222325
    for byte in value.encode():
        digest = ((digest ^ byte) * 0x100000001b3) & 0xffffffffffffffff
    return pathlib.Path(f'/tmp/hiboss-session-{digest:016x}')


def epoch_path(panel_id: str) -> pathlib.Path:
    return pathlib.Path(f'{session_path()}-panel-{panel_id}-epoch')


def cli(*args: str, input_text: str | None = None) -> str:
    result = subprocess.run(COMMAND + list(args), input=input_text, text=True, capture_output=True, timeout=25)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout.strip()


def expect_failure(*args: str, contains: str) -> None:
    result = subprocess.run(COMMAND + list(args), text=True, capture_output=True, timeout=25)
    assert result.returncode != 0 and contains in result.stderr, result.stderr


def checkpoint(panel_id: str) -> dict:
    return json.loads(cli('state', panel_id))


def transition(directory: pathlib.Path, panel_id: str, action: str, version: int, **extra: object) -> dict:
    state = checkpoint(panel_id)
    document = dict(protocolVersion=2, action=action, expectedMetadataVersion=version, expectedDefinitionRevision=1,
                    expectedEpoch=state['epoch'] if state['leaseExpiresAt'] else None,
                    expectedState=dict(epoch=state['epoch'], sequence=state['sequence']), openRequests='reject', **extra)
    path = directory / f'{panel_id}-{action}.json'
    path.write_text(json.dumps(document))
    args = ('lifecycle', panel_id, str(path), '--idempotency-key', f'{panel_id}-{action}-{version}')
    first = json.loads(cli(*args))
    assert json.loads(cli(*args)) == first, 'Retry changed the operation receipt'
    return first


def complete(panel_id: str, task: dict) -> dict:
    result = json.loads(cli('complete', panel_id, '--title', 'Lifecycle complete', '--final-task', json.dumps(task)))
    assert result['lifecycle']['taskState'] == 'completed'
    return result


def verify_crash_recovery(panel_id: str, task: dict) -> dict:
    process = subprocess.Popen(COMMAND + ['stream', panel_id], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        process.stdin.write(json.dumps(task) + '\n')
        process.stdin.flush()
        for _ in range(30):
            if checkpoint(panel_id)['observationVersion'] > 0 and epoch_path(panel_id).is_file(): break
            time.sleep(0.1)
        assert checkpoint(panel_id)['observationVersion'] > 0 and epoch_path(panel_id).is_file()
        process.kill()
        process.wait(timeout=5)
    finally:
        if process.poll() is None: process.kill(); process.wait(timeout=5)
    changed = {**task, 'stage': 'Recovered after crash'}
    assert cli('update', panel_id, json.dumps({'stage': changed['stage']})).strip() == '1'
    return changed


def run_scenario(directory: pathlib.Path, fixture: str, action: str) -> None:
    document = json.loads((ROOT / 'panel-runtime/fixtures/examples' / f'{fixture}.json').read_text())
    document.update(targetBossId='lifecycle-cli-boss', sessionId='lifecycle-cli-session', taskKey=fixture,
                    lifecycle=dict(mode='monitor' if fixture == 'service-monitor' else 'run', expectedUpdateIntervalSeconds=5))
    path = directory / f'{fixture}.json'
    path.write_text(json.dumps(document))
    assert cli('validate', str(path)) == 'valid'
    panel_id = json.loads(cli('publish', str(path), '--idempotency-key', f'{directory.name}-{fixture}'))['panelId']
    task = document['initialState']['task']
    if fixture == 'service-monitor': verify_heartbeat(panel_id, task)
    assert cli('update', panel_id, json.dumps({'stage': f'First {fixture}'})).strip() == '1'
    assert cli('update', panel_id, json.dumps({'stage': f'Second {fixture}'})).strip() == '1'
    task = {**task, 'stage': f'Second {fixture}'}
    if fixture == 'download-progress':
        task = verify_crash_recovery(panel_id, task)
    # A repeated observation must be acknowledged even if its values have not changed.
    if fixture != 'service-monitor': assert 'ack 0' in cli('stream', panel_id, input_text=json.dumps(task) + '\n')
    observed = checkpoint(panel_id)
    expected_observations = 5 if fixture == 'download-progress' else 3
    assert observed['observationVersion'] == expected_observations and observed['sequence'] >= 0, (fixture, observed)
    assert transition(directory, panel_id, 'pause', 1)['lifecycle']['taskState'] == 'paused'
    assert transition(directory, panel_id, 'resume', 2)['lifecycle']['taskState'] == 'running'
    changed = {**task, 'stage': f'Observed {fixture}'}
    assert 'ack 1' in cli('stream', panel_id, input_text=json.dumps(changed) + '\n')
    assert checkpoint(panel_id)['task'] == changed
    result = dict(title=f'{fixture}: {action}')
    if action == 'fail': result['code'] = 'test_failure'
    receipt = complete(panel_id, changed) if action == 'complete' else transition(directory, panel_id, action, 3, finalTask=changed, result=result)
    expected = dict(complete='completed', fail='failed', cancel='cancelled')[action]
    assert receipt['lifecycle']['taskState'] == expected
    assert checkpoint(panel_id)['task'] == changed
    detail = json.loads(cli('show', panel_id, '--json'))
    assert detail['metadataVersion'] == 4 and detail['finalSnapshot']['task'] == changed
    if action == 'complete':
        expect_failure('publish', str(path), '--idempotency-key', f'{directory.name}-{fixture}', '--run-id', directory.name, contains='ended panel')
        assert 'relay' in cli('doctor')
    print(f'PASS {fixture}: publish → observe → pause → resume → update → {expected} → reload')


def verify_heartbeat(panel_id: str, task: dict) -> None:
    process = subprocess.Popen(COMMAND + ['stream', panel_id], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        process.stdin.write(json.dumps(task) + '\n')
        process.stdin.flush()
        for _ in range(30):
            before = checkpoint(panel_id)
            if before['observationVersion'] == 1: break
            time.sleep(0.1)
        assert before['observationVersion'] == 1
        time.sleep(16)
        after = checkpoint(panel_id)
        assert after['leaseExpiresAt'] > before['leaseExpiresAt'], 'Idle producer did not renew its lease'
        assert after['lastObservedAt'] == before['lastObservedAt'], 'Heartbeat refreshed stale data'
        assert after['staleAt'] == before['staleAt']
        process.stdin.close()
        assert process.wait(timeout=5) == 0
        assert 'ack 0' in process.stdout.read()
    finally:
        if process.poll() is None: process.terminate(); process.wait(timeout=5)


def main() -> None:
    session_path().write_text('lifecycle-cli-session')
    assert 'relay: not checked (no panel yet)' in cli('doctor')
    with tempfile.TemporaryDirectory(prefix='hiboss-panel-flow-') as directory:
        for fixture, action in [('download-progress', 'complete'), ('e2e-test-run', 'fail'),
                                ('benchmark-sweep', 'complete'), ('service-monitor', 'cancel')]:
            run_scenario(pathlib.Path(directory), fixture, action)


if __name__ == '__main__':
    main()
