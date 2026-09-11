# Exercises publication, revision, waiting, recovery, and receipt acknowledgement.
# Exports an E2E runner that uses the actual Rust questionnaire command handlers.
# Dependencies: Python stdlib, request-driver, and an isolated Worker with test seeds.

import json
import os
import pathlib
import re
import subprocess
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[3]
BASE = os.environ['HIBOSS_PANEL_TEST_URL']
DRIVER = ROOT / 'cli/target/debug/examples/request-driver'
COMMAND = [str(DRIVER), '--server', BASE, '--key', 'hb_lifecycle_cli_test_only']


def cli(*args: str) -> dict:
    result = subprocess.run(COMMAND + list(args), text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def api(path: str, body: dict, boss: bool = False) -> dict:
    token = 'hb_lifecycle_boss_test_only' if boss else 'hb_lifecycle_cli_test_only'
    request = urllib.request.Request(BASE + '/api/' + path, data=json.dumps(body).encode(), headers={
        'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json', 'Idempotency-Key': 'questionnaire-panel',
    })
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def validate_guide_example(panel_id: str, directory: pathlib.Path) -> None:
    guide = (ROOT / 'cli/resources/panel-agent-guide.md').read_text()
    examples = [json.loads(block) for block in re.findall(r'```json\n(.*?)\n```', guide, re.S)]
    intake = next(example for example in examples if example.get('kind') == 'intake')
    path = directory / 'guide-intake.json'
    path.write_text(json.dumps(intake))
    request_id = cli('publish', panel_id, str(path), '--idempotency-key', 'installed-guide-example')['requestId']
    assert cli('show', request_id)['definition']['context'] == intake['context']
    cli('withdraw', request_id, '--expected-revision', '1', '--reason', 'Guide example validated')


def main() -> None:
    document = json.loads((ROOT / 'panel-runtime/fixtures/examples/e2e-test-run.json').read_text())
    document.update(targetBossId='lifecycle-cli-boss', sessionId='lifecycle-cli-session', taskKey='questionnaire-e2e')
    panel_id = api('panels', document)['panelId']
    sample = cli('publish', panel_id, str(ROOT / 'panel-runtime/fixtures/questionnaire-intake.json'), '--idempotency-key', 'research-example')
    assert cli('show', sample['requestId'])['definition']['kind'] == 'intake'
    cli('withdraw', sample['requestId'], '--expected-revision', '1', '--reason', 'Example validated')
    with tempfile.TemporaryDirectory(prefix='questionnaire-cli-') as temporary:
        validate_guide_example(panel_id, pathlib.Path(temporary))
        form = pathlib.Path(temporary) / 'form.json'
        form.write_text(json.dumps(dict(
            kind='intake', title='Research settings', blocking=True, priority='normal', catalogId='hiboss.panel', catalogVersion=1,
            context={'candidate': 'build-42'}, defaults={'count': 3},
            answerSchema={'type': 'object', 'properties': {'count': {'type': 'integer', 'minimum': 1}}, 'required': ['count'], 'additionalProperties': False},
            formSpec={'root': 'count', 'elements': {'count': {'type': 'NumberInput', 'props': {'label': 'Count', 'value': {'$bindState': '/form/count'}}, 'children': []}}},
        )))
        published = cli('publish', panel_id, str(form), '--idempotency-key', 'questionnaire-1')
        assert cli('publish', panel_id, str(form), '--idempotency-key', 'questionnaire-1') == published
        request_id = published['requestId']
        assert cli('list', panel_id)['needsInput'] is True
        assert cli('wait', request_id, '--timeout', '0') == {'requestId': request_id, 'state': 'open', 'timedOut': True}
        assert cli('replace', request_id, str(form), '--expected-revision', '1')['requestRevision'] == 2
        assert cli('show', request_id, '--revision', '1')['definitionRevision'] == 1
        payload = dict(protocolVersion=1, purpose='hiboss.interaction-submit', submissionId='questionnaire-cli-answer', requestId=request_id,
                       requestRevision=2, bossId='lifecycle-cli-boss', answers={'count': 5})
        receipt = api(f'interaction-requests/{request_id}/submissions', payload, boss=True)
        assert api(f'interaction-requests/{request_id}/submissions', payload, boss=True) == receipt
        answer = cli('wait', request_id, '--timeout', '1')
        assert answer['answers'] == {'count': 5} and answer['delivery'] == 'pending'
        assert cli('ack', request_id, answer['submissionId'])['delivery'] == 'delivered'
        assert cli('show', request_id)['submission']['delivery'] == 'delivered'
        second = cli('publish', panel_id, str(form), '--idempotency-key', 'questionnaire-2')['requestId']
        assert cli('withdraw', second, '--expected-revision', '1', '--reason', 'Question no longer needed')['state'] == 'withdrawn'
        assert cli('wait', second, '--timeout', '0')['submission'] is None
        assert cli('list', panel_id)['needsInput'] is False
    print('PASS: 5 CLI flows — publication/retry, pending timeout, revision/readback, answer/retry/ack, withdrawal')


if __name__ == '__main__':
    main()
