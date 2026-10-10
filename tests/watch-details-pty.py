#!/usr/bin/env python3
"""Black-box release watch checks; all inputs live in the supplied test workspace."""
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import threading
import time
import unicodedata

workspace = Path(sys.argv[1]).resolve()
bash = sys.argv[2]
cli = workspace / '.ralph/bin/ralph'
status_file = workspace / '.ralph/status.json'
run_id = 'watch-regression'


def status(round=1, state='running', run=run_id, provider='codex', done=0, total=4):
    now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    data = dict(run_id=run, run_dir=f'.ralph/runs/{run}', workspace=str(workspace),
                provider=provider, model=None, effort=None, started_at=now, updated_at=now,
                task_started_at=now, round=round, task_try=1, tasks_total=total, tasks_checked=done,
                retry_count=0, next_retry_at=None, state=state,
                exit_reason='done' if state == 'finished' else None, last_error=None)
    tmp = status_file.with_suffix('.tmp')
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(status_file)


def log(round=1, run=run_id):
    path = workspace / f'.ralph/runs/{run}/rounds/round-{round:03d}/provider.stdout.log'
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def message(text):
    return json.dumps(dict(type='item.completed', item=dict(type='agent_message', text=text))) + '\n'


class Watch:
    def __init__(self, details=True, columns=120, rows=24, event_lines=None, no_color=False,
                 command=None, env=None):
        self.output = b''
        self.code = None
        self.size = f'{columns}x{rows}'
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', rows, columns, 0, 0))
            os.chdir(workspace)
            os.environ.update(env or {})
            os.environ.pop('RALPH_UI_STICKY_EVENT_LINES', None)
            if event_lines is not None:
                os.environ['RALPH_UI_STICKY_EVENT_LINES'] = str(event_lines)
            if no_color:
                os.environ['NO_COLOR'] = '1'
            args = [bash, str(cli)] + (command if command is not None else
                                     ['watch'] + (['--details'] if details else []))
            os.execv(bash, args)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, columns, 0, 0))

    def pump(self, duration):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.fd], [], [], min(.1, max(0, deadline-time.monotonic())))
            if ready:
                try:
                    chunk = os.read(self.fd, 65536)
                    if chunk:
                        self.output += chunk
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
            if self.code is None:
                pid, result = os.waitpid(self.pid, os.WNOHANG)
                if pid:
                    self.code = os.waitstatus_to_exitcode(result)
                    if self.code < 0:
                        self.code = 128 - self.code
            if self.code is not None and not ready:
                break

    def expect(self, text, timeout=8):
        deadline = time.monotonic() + timeout
        while text.encode() not in self.output and time.monotonic() < deadline:
            self.pump(.1)
            if self.code is not None:
                break
        assert text.encode() in self.output, f'missing {text!r}: {self.output[-2200:]!r}'

    def finish(self, code, timeout=5):
        deadline = time.monotonic() + timeout
        while self.code is None and time.monotonic() < deadline:
            self.pump(.1)
        assert self.code == code, f'{self.size}: exit {self.code}, expected {code}: {self.output[-1800:]!r}'

    def close(self):
        if self.code is None:
            os.kill(self.pid, signal.SIGTERM)
            self.pump(2)
            if self.code is None:
                os.kill(self.pid, signal.SIGKILL)
                _, result = os.waitpid(self.pid, 0)
                self.code = os.waitstatus_to_exitcode(result)
        os.close(self.fd)


def checked(name, action):
    action()
    print('  [PTY PASS] ' + name, flush=True)


def snapshot():
    long = 'FULL-' + 'x'*300 + '-END'
    events = [message(long),
        json.dumps(dict(type='item.completed', item=dict(type='command_execution',
            command='exit 9', aggregated_output='REAL-CODEX-OUTPUT', exit_code=9, status='failed')))+'\n',
        json.dumps(dict(type='item.completed', item=dict(type='reasoning', text='REASONING-SUMMARY')))+'\n',
        json.dumps(dict(type='item.completed', item=dict(type='file_change', status='completed',
            changes=[dict(path='changed.txt', kind='update')])) )+'\n',
        json.dumps(dict(type='item.completed', item=dict(type='mcp_tool_call', server='local', tool='inspect',
            status='completed', result=dict(content=[dict(type='text', text='MCP-RESULT')]))))+'\n',
        json.dumps(dict(event='step_update', step_update=dict(tool_name='read_file', state='DONE',
            tool_info=dict(error='AGY-ERROR', output='AGY-OUTPUT'))))+'\n',
        json.dumps(dict(event='result', result=dict(status='SUCCESS', response='FINAL-RESPONSE')))+'\n',
        json.dumps(dict(type='new-provider-event', payload='UNKNOWN-CONTENT'))+'\n',
        '{broken JSON UNPARSED-CONTENT\n',
        'plain stderr DIAGNOSTIC\n',
        message('CONTROL-\x1b[31m-TEXT'),
        message('LAST-NO-NEWLINE').rstrip('\n')]
    log().write_text(''.join(events))
    status(state='finished')
    result = subprocess.run([bash, str(cli), 'watch', '--details'], capture_output=True, text=True, timeout=8)
    assert result.returncode == 0, result.stderr
    for text in [long, 'REAL-CODEX-OUTPUT', '❌ command exit=9', 'REASONING-SUMMARY',
                 'changed.txt', 'MCP-RESULT', 'AGY-ERROR', 'AGY-OUTPUT', 'FINAL-RESPONSE',
                 'UNKNOWN-CONTENT', 'UNPARSED-CONTENT', 'DIAGNOSTIC', 'LAST-NO-NEWLINE']:
        assert text in result.stdout, f'missing {text}: {result.stdout}'
    assert '\x1b' not in result.stdout, 'terminal escape leaked into details'
    plain = subprocess.run([bash, str(cli), 'watch'], capture_output=True, text=True, timeout=5)
    assert plain.returncode == 0 and len(plain.stdout.splitlines()) == 1


def follow():
    status()
    log().write_text(message('INITIAL-REPLAY'))
    watcher = Watch()
    try:
        watcher.expect('INITIAL-REPLAY')
        status_file.write_text('')
        watcher.pump(.7)
        assert watcher.code is None, 'watch exited during transient status write'
        status()
        half = message('HALF-LINE-COMPLETED')
        with log().open('a') as stream:
            stream.write(half[:len(half)//2])
        watcher.pump(.7)
        assert b'HALF-LINE-COMPLETED' not in watcher.output
        with log().open('a') as stream:
            stream.write(half[len(half)//2:])
        watcher.expect('HALF-LINE-COMPLETED')
        # 同一个 round 路径，分别替换为短、等长和更长的新日志。
        for kind in ('short', 'equal', 'long'):
            old_size = log().stat().st_size
            line = message('RETRY-'+kind)
            size = {'short': len(line), 'equal': old_size, 'long': old_size+1000}[kind]
            if size < len(line):
                size = len(line)
            tmp = log().with_suffix('.new')
            padding = size-len(line)
            tmp.write_text(line + (' '*(padding-1)+'\n' if padding else ''))
            tmp.replace(log())
            watcher.expect('RETRY-'+kind)
        log(2).write_text(message('PREVIOUS-ROUND-TAIL'))
        status(round=2)
        watcher.expect('PREVIOUS-ROUND-TAIL')
        log(3).write_text(message('SKIPPED-ROUND-THREE'))
        log(4).write_text(message('LATEST-ROUND-FOUR'))
        status(round=4)
        watcher.expect('SKIPPED-ROUND-THREE')
        watcher.expect('LATEST-ROUND-FOUR')
        log(run='next-run').write_text(message('NEW-RUN-REPLAY'))
        status(run='next-run')
        watcher.expect('NEW-RUN-REPLAY')
        with log(run='next-run').open('a') as stream:
            stream.write(message('FINISHED-LAST-LINE').rstrip('\n'))
        status(state='finished', run='next-run')
        watcher.expect('FINISHED-LAST-LINE')
        watcher.finish(0)
    finally:
        watcher.close()


def corrupt_status():
    status_file.write_text('{broken')
    result = subprocess.run([bash, str(cli), 'watch', '--details'], capture_output=True, text=True, timeout=5)
    assert result.returncode == 1 and 'cannot read status.json' in result.stderr, result


def ctrl_c():
    # 对真实 Ralph + fake oneshot 的独立观察，不能只用一个无关 sleep 冒充 provider。
    status()
    (workspace / '.ralph/TASKS.md').write_text('- [ ] DEV-1: slow fake task\n')
    env = dict(os.environ, RALPH_PROVIDER='fake', RALPH_FAKE_CLI=bash,
               RALPH_FAKE_SCENARIO='slow', RALPH_FAKE_SLEEP='30')
    stderr = (workspace / 'ctrl-c-provider.stderr').open('w')
    provider = subprocess.Popen([bash, str(cli), 'run', '--provider', 'fake',
                                 '--max-round', '1', '--round-timeout', '60'],
                                cwd=workspace, env=env, start_new_session=True,
                                stdout=subprocess.DEVNULL, stderr=stderr)
    watcher = None
    try:
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            assert provider.poll() is None, (workspace / 'ctrl-c-provider.stderr').read_text()
            data = json.loads(status_file.read_text())
            if data['provider'] == 'fake' and data['round'] == 1:
                break
            time.sleep(.05)
        else:
            raise AssertionError('Ralph provider did not start')
        watcher = Watch()
        watcher.expect('state=running')
        os.write(watcher.fd, b'\x03')
        watcher.finish(130)
        assert provider.poll() is None, 'Ctrl-C stopped provider'
        assert json.loads(status_file.read_text())['state'] == 'running'
        assert (workspace / '.ralph/lock').exists(), 'watch released active run lock'
    finally:
        if watcher is not None:
            watcher.close()
        if provider.poll() is None:
            provider.terminate()
            try:
                provider.wait(timeout=8)
            except subprocess.TimeoutExpired:
                os.killpg(provider.pid, signal.SIGKILL)
                provider.wait(timeout=5)
        stderr.close()


def atomic_status():
    script = '''source "$1/.ralph/lib/common.sh"
source "$1/.ralph/lib/run.sh"
_RALPH_WORKSPACE="$1"
for (( round=1; round<=30; round++ )); do
  _ralph_write_status running atomic-status fake "" "" 2026-10-09T00:00:00Z "$round" 30 "$round"
done
'''
    writer = subprocess.Popen([bash, '-c', script, '_', str(workspace)],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    samples = 0
    try:
        deadline = time.monotonic() + 25
        while writer.poll() is None and time.monotonic() < deadline:
            data = json.loads(status_file.read_text())
            if data['run_id'] == 'atomic-status':
                assert data['round'] == data['tasks_checked'] and data['tasks_total'] == 30
                samples += 1
            time.sleep(.005)
        _, errors = writer.communicate(timeout=2)
        assert writer.returncode == 0, errors
        assert samples > 3, f'insufficient status samples: {samples}'
        print(f'    atomic status: {samples} valid concurrent snapshots', flush=True)
    finally:
        if writer.poll() is None:
            os.killpg(writer.pid, signal.SIGKILL)
            writer.wait(timeout=5)


def compact_rotation():
    status()
    log().write_text('')
    watcher = Watch(details=False)
    try:
        watcher.expect('codex')
        with log().open('a') as stream:
            stream.write(message('COMPACT-FIRST'))
        watcher.expect('COMPACT-FIRST')
        tmp = log().with_suffix('.replacement')
        tmp.write_text(message('COMPACT-AFTER-RETRY'))
        tmp.replace(log())
        watcher.expect('COMPACT-AFTER-RETRY', timeout=12)
        os.write(watcher.fd, b'\x03')
        watcher.finish(130)
    finally:
        watcher.close()


class TerminalScreen:
    """Interpret cursor moves, erasure and terminal wrapping, independently of Ralph."""
    def __init__(self, columns, rows=24):
        self.columns, self.rows = columns, rows
        self.lines = [[' ']*columns for _ in range(rows)]
        self.history = []
        self.row = self.column = 0
        self.wrap = True

    def down(self):
        self.row += 1
        if self.row == self.rows:
            self.history.append(''.join(self.lines.pop(0)))
            self.lines.append([' ']*self.columns)
            self.row -= 1

    def feed(self, output):
        text = output.decode('utf-8', errors='replace')
        i = 0
        while i < len(text):
            ch = text[i]
            if ch == '\x1b':
                m = re.match(r'\x1b\[([0-9;?]*)([A-Za-z])', text[i:])
                assert m, f'unsupported terminal escape: {text[i:i+20]!r}'
                arg, op = m.groups()
                if op == 'A': self.row = max(0, self.row-int(arg or '1'))
                elif op == 'K': self.lines[self.row][min(self.column, self.columns):] = [' ']*max(0, self.columns-self.column)
                elif op == 'J':
                    assert arg in ('', '0'), f'unsupported erase mode: {arg}'
                    self.lines[self.row][min(self.column, self.columns):] = [' ']*max(0, self.columns-self.column)
                    for row in range(self.row+1, self.rows): self.lines[row] = [' ']*self.columns
                elif arg == '?7' and op in ('h', 'l'): self.wrap = op == 'h'
                i += len(m.group(0))
                continue
            if ch == '\r': self.column = 0
            elif ch == '\n': self.down()
            elif ch == '\t': self.column = (self.column//8+1)*8
            elif ord(ch) >= 32:
                width = 0 if unicodedata.combining(ch) or ch in '\u200d\ufe0e\ufe0f' else (2 if unicodedata.east_asian_width(ch) in 'WF' else 1)
                if width:
                    if self.column+width > self.columns:
                        if self.wrap:
                            self.column = 0
                            self.down()
                        else: self.column = self.columns-width
                    self.lines[self.row][self.column] = ch
                    if width == 2: self.lines[self.row][self.column+1] = ''
                    self.column += width
            i += 1

    def text(self):
        return '\n'.join(self.history + [''.join(line) for line in self.lines])


def compact_no_header_drift():
    for columns, rows, event_lines in ((80, 24, None), (120, 24, None), (180, 24, None),
                                      (80, 8, None), (120, 12, 30), (80, 1, None), (80, 4, None)):
        status(provider='antigravity')
        (workspace / '.ralph/TASKS.md').write_text('- [ ] DEV-10: 按最新代码兼容方案返工开发并删除多余建表SQL\n')
        log().write_text('')
        watcher = Watch(details=False, columns=columns, rows=rows, event_lines=event_lines)
        try:
            watcher.expect('ralph')
            events = [dict(event='step_update', step_update=dict(tool_name='run_command', state='DONE',
                      tool_info=dict(output='项目小时聚合 ' + '用户要求不新增表、字段、索引或消息契约。'*30))),
                      dict(event='step_update', step_update=dict(tool_name='view_file', state='DONE',
                      tool_info=dict(output='🔧🚀工具结果 中文\t制表符 ' * 20)))]
            with log().open('a') as stream:
                for event in events: stream.write(json.dumps(event, ensure_ascii=False)+'\n')
            if rows > 5: watcher.expect('完成 ')
            watcher.pump(1.5)
            screen = TerminalScreen(columns, rows)
            screen.feed(watcher.output)
            assert screen.text().count('ralph ') == 1, f'{columns}x{rows}: duplicated header\n{screen.text()}'
            status(state='finished', provider='antigravity')
            watcher.expect('finished')
            watcher.pump(1)
            screen = TerminalScreen(columns, rows)
            screen.feed(watcher.output)
            assert screen.text().count('ralph ') == 1, f'{columns}x{rows}: frozen header drift\n{screen.text()}'
            os.write(watcher.fd, b'\x03')
            watcher.finish(130)
            screen = TerminalScreen(columns, rows)
            screen.feed(watcher.output)
            assert screen.wrap, 'terminal autowrap was not restored'
            attrs = termios.tcgetattr(watcher.fd)
            assert attrs[3] & termios.ECHO and attrs[3] & termios.ICANON, 'terminal input flags were not restored'
            assert attrs[6][termios.VINTR] == b'\x03', 'terminal interrupt key was not restored'
        finally:
            watcher.close()


def health_activity():
    # 通过实际底栏验证活动状态跨帧保留，覆盖有内容的日志静默与等长替换。
    program = r'''
set -eu
unset NO_COLOR
source .ralph/lib/sticky.sh
_RALPH_STICKY_LOG_PATH="$1"
proof_now=1000
date() { if [[ "${1:-}" == '+%s' ]]; then printf '%s\n' "$proof_now"; else command date "$@"; fi; }
_SLAST_ACTIVITY_TS=1000
_sdraw_bottom > "$2/first"
proof_now=1080
_sdraw_bottom > "$2/idle"
proof_now=1400
_sdraw_bottom > "$2/stalled"
printf 'replacement\n' > "$1.new"
mv "$1.new" "$1"
_sdraw_bottom > "$2/rotated"
'''
    path = workspace / 'health-provider.log'
    path.write_text('first event\n')
    result = subprocess.run([bash, '-c', program, 'health', str(path), str(workspace)],
                            cwd=workspace, capture_output=True, timeout=5)
    assert result.returncode == 0, result.stderr
    for name, color in [('first', 32), ('idle', 33), ('stalled', 31), ('rotated', 32)]:
        assert f'\x1b[{color}m●'.encode() in (workspace/name).read_bytes(), f'{name}: wrong activity light'


def compact_status_consistency():
    status(round=0, done=0, total=1000)
    watcher = Watch(details=False, columns=180)
    try:
        watcher.expect('/1000')
        for value in range(1, 101):
            status(round=value, done=value, total=1000)
            watcher.pump(.025)
        watcher.pump(.5)
        plain = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', watcher.output)
        frames = re.findall(rb'tasks (\d+)/1000.*?oneshots (\d+)', plain)
        assert len(frames) > 3, f'not enough frames: {frames}'
        assert all(done == round for done, round in frames), f'mixed status snapshots: {frames}'
        os.write(watcher.fd, b'\x03')
        watcher.finish(130)
    finally:
        watcher.close()


def compact_no_color():
    status()
    watcher = Watch(details=False, no_color=True)
    try:
        watcher.expect('ralph ')
        watcher.pump(.5)
        assert not re.search(rb'\x1b\[[0-9;]*m', watcher.output), 'NO_COLOR still emits display styles'
        assert b'\x1b[?7l' in watcher.output, 'cursor layout controls must remain available'
        os.write(watcher.fd, b'\x03')
        watcher.finish(130)
    finally:
        watcher.close()


def compact_env_configuration():
    config = workspace / '.ralph/.env'
    previous = config.read_bytes() if config.exists() else None
    config.write_text('RALPH_UI_STICKY_EVENT_LINES=1\n')
    try:
        for override, expected_rows in [(None, 6), (3, 8)]:
            status()
            watcher = Watch(details=False, event_lines=override)
            try:
                watcher.expect('ralph ')
                watcher.pump(1)
                # 第二帧回移的物理行数应来自 .env，进程环境显式值优先。
                assert f'\x1b[{expected_rows}A'.encode() in watcher.output, (
                    f'watch ignored UI config (override={override}): {watcher.output[-2000:]!r}')
                screen = TerminalScreen(120, 24)
                screen.feed(watcher.output)
                assert screen.text().count('ralph ') == 1
                os.write(watcher.fd, b'\x03')
                watcher.finish(130)
            finally:
                watcher.close()
    finally:
        if previous is None:
            config.unlink()
        else:
            config.write_bytes(previous)


def atomic_observer_snapshots():
    status(round=0, done=0, total=1000)
    stop = threading.Event()
    def update():
        value = 0
        while not stop.is_set():
            value += 1
            status(round=value, done=value, total=1000)
            stop.wait(.004)
    writer = threading.Thread(target=update)
    writer.start()
    try:
        for command in ['status', 'watch']:
            for _ in range(8):
                result = subprocess.run([bash, str(cli), command], capture_output=True,
                                        text=True, timeout=8)
                assert result.returncode == 0, result.stderr
                if command == 'status':
                    round_match = re.search(r'round:\s+(\d+)', result.stdout)
                    done_match = re.search(r'tasks:\s+(\d+) / 1000', result.stdout)
                else:
                    round_match = re.search(r'round (\d+)', result.stdout)
                    done_match = re.search(r'(\d+)/1000 tasks', result.stdout)
                assert round_match and done_match, result.stdout
                assert round_match[1] == done_match[1], f'{command} mixed snapshots: {result.stdout}'
    finally:
        stop.set()
        writer.join()


def ui_config_validation():
    program = '''set -eu
source .ralph/lib/sticky.sh
_SLAST_ACTIVITY_TS=$(date +%s)
_shealth >/dev/null
printf '%s %s %s' "$_SEVENT_WINDOW" "$_SHEALTH_GREEN" "$_SHEALTH_RED"
'''
    cases = [('08', '007', '0300', '8 7 300'),
             ('oops', 'a[$(touch ui-config-executed)]', 'oops', '6 60 300'),
             ('0', '400', '300', '6 60 300'),
             ('99999999999999999999', '-1', '0', '6 60 300')]
    for window, green, red, expected in cases:
        env = dict(os.environ, RALPH_UI_STICKY_EVENT_LINES=window,
                   RALPH_UI_HEALTH_GREEN_SEC=green, RALPH_UI_HEALTH_RED_SEC=red)
        result = subprocess.run([bash, '-c', program], cwd=workspace, env=env,
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 0 and result.stdout == expected, result
        assert not result.stderr, result.stderr
        assert not (workspace/'ui-config-executed').exists(), 'UI config executed shell code'


def sticky_run_interrupt():
    previous_run = json.loads(status_file.read_text())['run_id'] if status_file.exists() else None
    (workspace/'.ralph/TASKS.md').write_text('- [ ] DEV-1: slow fake task\n')
    watcher = Watch(details=False, command=['run', '--provider', 'fake', '-v', '--max-round', '1'],
                    env=dict(RALPH_FAKE_CLI=bash, RALPH_FAKE_SCENARIO='slow_child',
                             RALPH_FAKE_SLEEP='30', RALPH_PROVIDER_CONFIG_DIR=''))
    try:
        watcher.expect('ralph ')
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            data = json.loads(status_file.read_text())
            child_file = workspace/data['run_dir']/'rounds/round-001/slow-child.pid'
            if (data['run_id'] != previous_run and data['state'] == 'running' and
                    data['provider'] == 'fake' and data['round'] == 1 and child_file.exists()):
                break
            watcher.pump(.05)
        else:
            raise AssertionError('sticky fake provider child did not start')
        child = int(child_file.read_text())
        os.write(watcher.fd, b'\x03')
        watcher.finish(130)
        result = json.loads((workspace/data['run_dir']/'result.json').read_text())
        assert result['exit_reason'] == 'interrupted', result
        assert json.loads(status_file.read_text())['state'] == 'finished'
        assert not (workspace/'.ralph/lock').exists(), 'sticky interrupt retained lock'
        try:
            os.kill(child, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError('sticky interrupt retained fake provider child')
        attrs = termios.tcgetattr(watcher.fd)
        assert attrs[3] & termios.ECHO and attrs[3] & termios.ICANON
        assert attrs[6][termios.VINTR] == b'\x03'
    finally:
        watcher.close()


checked('non-TTY full events, real Codex fields, AGY error/output/final text, raw fallback and controls', snapshot)
checked('TTY replay, status recovery, partial line, three retry sizes, skipped rounds, run change and finish', follow)
checked('persistent corrupt status fails after bounded retries', corrupt_status)
checked('details Ctrl-C leaves provider and running state intact', ctrl_c)
checked('compact watch follows retry log inode replacement', compact_rotation)
checked('compact terminal screen has one header with long CJK/emoji/tab output at 80/120/180 columns, live and finished', compact_no_header_drift)
checked('compact activity persists across frames, turns yellow/red on idle and recovers after log replacement', health_activity)
checked('compact frames read progress and round from one atomic status snapshot', compact_status_consistency)
checked('compact NO_COLOR omits styles and preserves terminal layout controls', compact_no_color)
checked('compact watch loads .env UI configuration and respects process overrides', compact_env_configuration)
checked('status and non-TTY watch read one atomic snapshot per command', atomic_observer_snapshots)
checked('UI numbers use decimal and safely default invalid values without evaluation', ui_config_validation)
checked('run -v keyboard interrupt records final state, releases lock, restores tty and terminates provider child', sticky_run_interrupt)
checked('actual runtime status writer exposes only complete consistent JSON', atomic_status)
