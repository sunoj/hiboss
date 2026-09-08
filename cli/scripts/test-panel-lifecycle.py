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
BASE = os.environ.get('HIBOSS_PANEL_TEST_URL', 'http://127.0.0.1:8798')
DRIVER = ROOT / 'cli/target/debug/examples/panel-lifecycle-driver'
COMMAND = [str(DRIVER), '--server', BASE, '--key', 'hb_lifecycle_cli_test_only']


def cli(*args: str, input_text: str | None = None) -> str:
    result = subprocess.run(COMMAND + list(args), input=input_text, text=True, capture_output=True, timeout=25)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout.strip()


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


def run_scenario(directory: pathlib.Path, fixture: str, action: str) -> None:
    document = json.loads((ROOT / 'panel-runtime/fixtures/examples' / f'{fixture}.json').read_text())
    document.update(targetBossId='lifecycle-cli-boss', sessionId='lifecycle-cli-session', taskKey=fixture,
                    lifecycle=dict(mode='monitor' if fixture == 'service-monitor' else 'run', expectedUpdateIntervalSeconds=5))
    path = directory / f'{fixture}.json'
    path.write_text(json.dumps(document))
    assert cli('validate', str(path)) == 'valid'
    panel_id = json.loads(cli('publish', str(path), '--idempotency-key', f'{directory.name}-{fixture}'))['panelId']
    task = document['initialState']['task']
    # A repeated observation must be acknowledged even if its values have not changed.
    if fixture == 'service-monitor': verify_heartbeat(panel_id, task)
    else: assert 'ack 0' in cli('stream', panel_id, input_text=json.dumps(task) + '\n')
    observed = checkpoint(panel_id)
    assert observed['observationVersion'] == 1 and observed['sequence'] == 0
    assert transition(directory, panel_id, 'pause', 1)['lifecycle']['taskState'] == 'paused'
    assert transition(directory, panel_id, 'resume', 2)['lifecycle']['taskState'] == 'running'
    changed = {**task, 'stage': f'Observed {fixture}'}
    assert 'ack 1' in cli('stream', panel_id, input_text=json.dumps(changed) + '\n')
    assert checkpoint(panel_id)['task'] == changed
    result = dict(title=f'{fixture}: {action}')
    if action == 'fail': result['code'] = 'test_failure'
    receipt = transition(directory, panel_id, action, 3, finalTask=changed, result=result)
    expected = dict(complete='completed', fail='failed', cancel='cancelled')[action]
    assert receipt['lifecycle']['taskState'] == expected
    assert checkpoint(panel_id)['task'] == changed
    detail = json.loads(cli('show', panel_id, '--json'))
    assert detail['metadataVersion'] == 4 and detail['finalSnapshot']['task'] == changed
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
    with tempfile.TemporaryDirectory(prefix='hiboss-panel-flow-') as directory:
        for fixture, action in [('download-progress', 'complete'), ('e2e-test-run', 'fail'),
                                ('benchmark-sweep', 'complete'), ('service-monitor', 'cancel')]:
            run_scenario(pathlib.Path(directory), fixture, action)


if __name__ == '__main__':
    main()
