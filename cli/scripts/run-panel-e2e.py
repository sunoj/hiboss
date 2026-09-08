# Starts an isolated local Worker on the remote E2E host and tests real CLI flows.
# Exports a runnable harness with independent D1 state, test identities, and cleanup.
# Dependencies: Python stdlib, installed workspace packages, and built Rust examples.

import hashlib
import os
import pathlib
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
WRANGLER = ROOT / 'node_modules/.bin/wrangler'


def run(arguments: list[str], log: pathlib.Path, environment: dict[str, str]) -> None:
    with log.open('w') as output:
        subprocess.run(arguments, cwd=ROOT / 'server', env=environment, stdin=subprocess.DEVNULL,
                       stdout=output, stderr=subprocess.STDOUT, check=True, timeout=180)


def seed_file(directory: pathlib.Path) -> pathlib.Path:
    agent = hashlib.sha256(b'hb_lifecycle_cli_test_only').hexdigest()
    boss = hashlib.sha256(b'hb_lifecycle_boss_test_only').hexdigest()
    path = directory / 'seed.sql'
    path.write_text(f"""INSERT INTO api_keys(id,name,key_hash) VALUES('lifecycle-cli-agent','CLI tests','{agent}');
INSERT INTO bosses(id,name,role) VALUES('lifecycle-cli-boss','Test Boss','manager');
INSERT INTO boss_agent_access(boss_id,agent_id) VALUES('lifecycle-cli-boss','lifecycle-cli-agent');
INSERT INTO boss_tokens(id,boss_id,label,token_hash) VALUES('test-token','lifecycle-cli-boss','Test','{boss}');
INSERT INTO sessions(id,agent_id,label) VALUES('lifecycle-cli-session','lifecycle-cli-agent','Remote E2E');
""")
    return path


def wait_ready(url: str, process: subprocess.Popen) -> None:
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError('Worker exited before becoming ready')
        try:
            urllib.request.urlopen(url + '/health', timeout=1).close()
            return
        except urllib.error.HTTPError:
            return
        except (urllib.error.URLError, TimeoutError):
            time.sleep(0.2)
    raise TimeoutError('Worker did not start')


def main() -> None:
    reports = ROOT / 'output/panel-lifecycle'
    reports.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='hiboss-worker-') as temporary:
        directory = pathlib.Path(temporary)
        environment = {**os.environ, 'WRANGLER_LOG_PATH': str(reports / 'wrangler')}
        database = ['--local', '--persist-to', str(directory / 'state')]
        run([str(WRANGLER), 'd1', 'migrations', 'apply', 'hiboss-db', *database], reports / 'migrations.log', environment)
        run([str(WRANGLER), 'd1', 'execute', 'hiboss-db', *database, '--file', str(seed_file(directory))], reports / 'seed.log', environment)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            port = listener.getsockname()[1]
        url = f'http://127.0.0.1:{port}'
        with (reports / 'worker.log').open('w') as output:
            process = subprocess.Popen([str(WRANGLER), 'dev', *database, '--port', str(port), '--ip', '127.0.0.1'],
                cwd=ROOT / 'server', env=environment, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                wait_ready(url, process)
                run(['python3', str(ROOT / 'cli/scripts/test-panel-lifecycle.py')], reports / 'cli-e2e.log',
                    {**environment, 'HIBOSS_PANEL_TEST_URL': url})
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=10)
        print((reports / 'cli-e2e.log').read_text())


if __name__ == '__main__':
    main()
