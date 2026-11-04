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
import shutil
import signal
import struct
import subprocess
import sys
import termios
import tempfile
import threading
import time
import unicodedata

workspace = Path(sys.argv[1]).resolve()
bash = sys.argv[2]
cli = workspace / '.ralph/bin/ralph'
status_file = workspace / '.ralph/status.json'
run_id = 'watch-regression'


def status(round=1, state='running', run=run_id, provider='codex', done=0, total=4, task_index=None, title='Task'):
    now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    data = dict(run_id=run, run_dir=f'.ralph/runs/{run}', workspace=str(workspace),
                provider=provider, model=None, effort=None, started_at=now, updated_at=now,
                task_started_at=now, round=round, task_try=1, tasks_total=total, tasks_checked=done,
                retry_count=0, next_retry_at=None, state=state,
                exit_reason='done' if state == 'finished' else None, last_error=None)
    if task_index is not None:
        data['round_task'] = dict(index=task_index, total=total, title=title)
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
                 command=None, env=None, reply_lines=None):
        self.output = b''
        self.code = None
        self.size = f'{columns}x{rows}'
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', rows, columns, 0, 0))
            os.chdir(workspace)
            os.environ.pop('RALPH_UI_STICKY_EVENT_LINES', None)
            os.environ.pop('RALPH_UI_STICKY_REPLY_LINES', None)
            os.environ.update(env or {})
            if reply_lines is not None:
                os.environ['RALPH_UI_STICKY_REPLY_LINES'] = str(reply_lines)
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
    initial = message('INITIAL-REPLAY').encode()
    log().write_bytes(b'\0'*len(initial) + b'\n' + initial)
    watcher = Watch()
    try:
        watcher.expect('INITIAL-REPLAY')
        watcher.pump(.8)
        assert watcher.output.count(b'INITIAL-REPLAY') == 1, 'binary stderr moved the details cursor backwards'
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
        log(2000000).write_text(message('LATEST-SPARSE-ROUND'))
        status(round=2000000)
        watcher.expect('SKIPPED-ROUND-THREE')
        watcher.expect('LATEST-SPARSE-ROUND')
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
    status(run='before-atomic-writer')
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


def compact_frame(watcher, contains, timeout=8):
    """Check the last painted screen, not text left over from an earlier frame."""
    columns, rows = map(int, watcher.size.split('x'))
    deadline = time.monotonic()+timeout
    lines = []
    while time.monotonic() < deadline and watcher.code is None:
        watcher.pump(.1)
        complete, marker, _ = watcher.output.rpartition(b'\x1b[?7h')
        if marker:
            screen = TerminalScreen(columns, rows)
            screen.feed(complete + marker)
            lines = [''.join(row).rstrip() for row in screen.lines]
            start = next((i for i, line in enumerate(lines) if line.startswith('ralph ')), None)
            if start is None: continue
            lines = lines[start:]
            if any(contains in line for line in lines):
                return lines
    raise AssertionError(f'{contains!r} missing from latest screen: {lines}')


def compact_messages():
    def encode(event):
        return json.dumps(event, ensure_ascii=False)+'\n'

    def delta(step, text, session='session'):
        return encode(dict(event='step_update', step_update=dict(conversation_id=session,
                      step_type='agent_response', step_index=step, text_delta=text)))

    status(provider='antigravity', done=1, total=3, task_index=2)
    history = delta(83, 'First frag') + delta(83, 'ment\r\n\tsecond  part')
    for n in range(9):
        history += encode(dict(event='step_update', step_update=dict(state='DONE',
                          tool_name=f'tool-{n}', tool_info=dict(output='💬 tool output'))))
    log().write_text(history)
    w = Watch(details=False, no_color=True, columns=80)
    try:
        lines = compact_frame(w, 'tool-8')
        assert 'tasks 2/3' in lines[0] and lines[8].startswith('──'), lines
        assert re.fullmatch(r'\[\d\d:\d\d:\d\d\] 💬 First fragment second part', lines[2]), lines
        stamp = lines[2][:10]
        deadline = time.monotonic()+2
        while time.strftime('[%H:%M:%S]') == stamp and time.monotonic()<deadline:
            w.pump(.05)
        assert not lines[3] and all(f'tool-{n}' in line for n, line in enumerate(lines[4:8], 5)), lines
        assert log().read_text() == history

        # Split in the middle of a multibyte character, then deliver a new step in two parts.
        raw = delta(83, ' 世界').encode()
        cut = raw.index('世'.encode())+1
        with log().open('ab') as f: f.write(raw[:cut])
        w.pump(.4)
        with log().open('ab') as f: f.write(raw[cut:])
        lines = compact_frame(w, 'second part 世界')
        assert lines[2].startswith(stamp)
        with log().open('a') as f:
            f.write(delta(84, 'New ') + delta(83, 'stale') + delta(84, 'reply'))
        assert compact_frame(w, 'New reply')[2][11:] == '💬 New reply'
        with log().open('a') as f:
            f.write(delta(1, 'Other ', 'session/b') + delta(84, 'late') + delta(1, 'session', 'session/b'))
        assert compact_frame(w, 'Other session')[2].endswith('💬 Other session')

        # Same pathname/step index on retry; text-free events must clear old text too.
        retry = log().with_suffix('.retry')
        retry.write_text(encode(dict(type='error', message='retry started')))
        retry.replace(log())
        assert '本轮暂未收到模型文字' in compact_frame(w, 'retry started')[2]
        with log().open('a') as f: f.write(delta(84, 'Retry reply'))
        assert compact_frame(w, 'Retry reply')[2].endswith('💬 Retry reply')

        status(round=2, task_index=2)
        codex = encode(dict(type='item.completed', item=dict(id='a', type='agent_message', text='Codex full')))
        log(2).write_text(codex*2)
        assert compact_frame(w, 'Codex full')[2].endswith('💬 Codex full')
        log(3).write_text(encode(dict(type='assistant', message=dict(id='m', content=[
            dict(type='text',text='Claude\nfirst'),dict(type='tool_use',name='Read'),
            dict(type='text',text='second')]))))
        status(round=3, task_index=3)
        lines = compact_frame(w, 'Claude first second')
        assert lines[2].endswith('💬 Claude first second') and 'Read' in lines[7]
        with log(3).open('a') as f:
            f.write(encode(dict(type='result',result='FINAL '+'中'*150+' HIDDEN-END')).rstrip())
        status(round=3, state='finished', total=3, done=3)
        lines = compact_frame(w,'all tasks done')
        assert 'tasks 3/3' in lines[0] and '💬 FINAL ' in lines[2] and lines[3].endswith('...'),lines
        assert 'HIDDEN-END' not in ''.join(lines)
        details = subprocess.check_output([bash, str(cli), 'watch','--details'],text=True)
        assert 'HIDDEN-END' in details
    finally:
        w.close()


def mock_antigravity(scenario):
    mock_bin = Path(tempfile.mkdtemp(prefix='mock-sticky-', dir=workspace))
    (mock_bin/'agy').symlink_to(Path(__file__).resolve().parent/'fixtures/mock-antigravity')
    return dict(PATH=str(mock_bin)+':'+os.environ['PATH'], HOME=str(mock_bin/'home'),
                ANTIGRAVITY_APP_DATA_DIR=str(mock_bin/'antigravity-data'),
                RALPH_PROVIDER_CONFIG_DIR='', RALPH_MOCK_ALLOW_TASK_WRITE='1',
                RALPH_MOCK_ANTIGRAVITY_SCENARIO=scenario)


def compact_dispatch():
    # Only the middle task is pending. checked+1 would incorrectly select 3/3.
    tasks = workspace/'.ralph/TASKS.md'
    tasks.write_text('- [x] DEV-1: done\n- [ ] DEV-2: dispatched task\n- [X] QA-3: done\n')
    env = mock_antigravity('sticky_progress')
    gate = Path(env['HOME']).parent/'finish'
    env['RALPH_MOCK_STICKY_GATE'] = str(gate)
    run = Watch(command=['run','--provider','antigravity','-v'], reply_lines=3, no_color=True, env=env)
    observer = None
    try:
        live = compact_frame(run, 'tool-H')
        assert '[ ]' not in tasks.read_text()
        data = json.loads(status_file.read_text())
        assert data['tasks_checked']==2 and data['round_task']==dict(index=2,total=3,title='DEV-2: dispatched task'),data
        observer = Watch(details=False,no_color=True)
        for lines, reply_rows in ((live, 3), (compact_frame(observer,'tool-H'), 2)):
            assert 'tasks 2/3' in lines[0] and 'oneshots 1' in lines[0], lines
            first_event = 2 + reply_rows
            assert lines[2].endswith('💬 Pinned reply from three fragments') and not any(lines[3:first_event])
            assert all(f'tool-{letter}' in lines[first_event+i] for i, letter in enumerate('EFGH'))
            assert lines[first_event+4].startswith('──')
            assert 'DEV-2: dispatched task' in lines[first_event+5] and 'round 1/∞' in lines[first_event+5]
        gate.touch()
        run.finish(0,timeout=12)
        assert b'FINAL-WITHOUT-LF' in run.output and b'all tasks done' in run.output
        finished = compact_frame(observer,'all tasks done')
        assert 'tasks 3/3' in finished[0] and 'oneshots 1' in finished[0] and 'FINAL-WITHOUT-LF' in finished[2]
    finally:
        gate.touch()
        if observer is not None: observer.close()
        run.close()


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
    status(round=0, done=0, total=1000, task_index=1)
    watcher = Watch(details=False, columns=180)
    try:
        watcher.expect('/1000')
        for value in range(1, 101):
            status(round=value, done=0, total=1000, task_index=value+1)
            watcher.pump(.025)
        watcher.pump(.5)
        plain = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', watcher.output)
        frames = re.findall(rb'tasks (\d+)/1000.*?oneshots (\d+)', plain)
        assert len(frames) > 3, f'not enough frames: {frames}'
        assert all(int(index) == int(round) + 1 for index, round in frames), f'mixed status snapshots: {frames}'
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
    status()
    events = [dict(type='tool_use', name=f'event-{i}') for i in range(8)]
    log().write_text(message('R'*500) + ''.join(json.dumps(e)+'\n' for e in events))
    cases = [
        ('', None, None, 24, 2, 4),
        ('RALPH_UI_STICKY_REPLY_LINES=3', None, None, 24, 3, 4),
        ('RALPH_UI_STICKY_EVENT_LINES=6', None, None, 24, 2, 6),
        ('\ufeffRALPH_UI_STICKY_REPLY_LINES="3"\r\nRALPH_UI_STICKY_EVENT_LINES=6\r', None, None, 24, 3, 6),
        ('RALPH_UI_STICKY_REPLY_LINES=1\nRALPH_UI_STICKY_EVENT_LINES=4', None, 2, 24, 1, 2),
        ('RALPH_UI_STICKY_REPLY_LINES=1\nRALPH_UI_STICKY_EVENT_LINES=2', 3, None, 24, 3, 2),
        ('', 999999999, 999999999, 10, 3, 1),
    ]
    try:
        for settings, replies, events_override, rows, shown_replies, shown_events in cases:
            config.write_text(settings+'\n')
            watcher = Watch(details=False, columns=60, rows=rows, reply_lines=replies,
                            event_lines=events_override, no_color=True)
            try:
                lines = compact_frame(watcher, 'event-7')
                first_event = 2 + shown_replies
                assert all('R'*16 in line for line in lines[2:first_event]), lines
                assert lines[first_event-1].endswith('...'), lines
                for i, line in enumerate(lines[first_event:first_event+shown_events], 8-shown_events):
                    assert f'event-{i}' in line, lines
                assert lines[first_event+shown_events].startswith('──'), lines
                watcher.expect(f'\x1b[{5+shown_replies+shown_events}A')
                screen = TerminalScreen(60, rows)
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


def compact_live_resize():
    run = 'resize-unicode'
    status(run=run, task_index=1, title='中文任务'*20)
    path = log(run=run)
    path.write_text(message('界'*180))
    w = Watch(details=False, columns=50, rows=18, reply_lines=3, event_lines=2,
              no_color=True, env={'LC_ALL':'C'})
    try:
        for tag, cols, rows, replies, events in [('t1',50,18,3,2), ('t2',34,8,1,1), ('t3',96,24,3,2)]:
            fcntl.ioctl(w.fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
            with path.open('a') as stream:
                stream.write(json.dumps(dict(type='tool_use', name=tag, parameters='工具'*40))+'\n')
            deadline = time.monotonic()+6
            while time.monotonic()<deadline:
                w.pump(.1)
                complete, end, _ = w.output.rpartition(b'\x1b[?7h')
                frame = complete.rpartition(b'\x1b[?7l')[2]
                if end and tag.encode() in frame and frame.count(b'\n') == 5+replies+events:
                    break
            else: raise AssertionError(f'{tag}: no complete resized frame')
            frame.decode('utf-8')  # Reply, tool and title must all end on character boundaries.
            screen = TerminalScreen(cols, rows)
            screen.feed(b'\x1b[?7l'+frame+end)
            lines = [''.join(row).rstrip() for row in screen.lines]
            truncated = replies == 1
            visible = (cols-14-(3 if truncated else 0))//2
            assert lines[2].endswith('💬 '+'界'*visible+('...' if truncated else '')), lines
            assert tag in lines[2+replies+events-1] and lines[2+replies+events].startswith('──'), lines
        os.write(w.fd, b'\x03')
        w.finish(130)
    finally:
        w.close()


def compact_large_reply():
    run = 'large-public-reply'
    status(run=run, task_index=1)
    path = log(run=run)
    big = 'R'*(512*1024)+'DETAILS-TAIL'
    path.write_text(message(big)+json.dumps(dict(type='tool_use',name='after-large'))+'\n')
    # Oversized settings on a small terminal must not turn into a multi-gigabyte cache.
    check = '''set -eu
source .ralph/lib/sticky.sh
ralph_sticky_drain_log "$1"
printf '%s %s' "${#_SREPLY_TEXT}" "$_SEVENT_WINDOW"
'''
    env = dict(os.environ, RALPH_UI_STICKY_REPLY_LINES='999999999', RALPH_UI_STICKY_EVENT_LINES='999999999')
    sizes = subprocess.check_output([bash,'-c',check,'_',str(path)], cwd=workspace, env=env, timeout=6)
    assert tuple(map(int, sizes.split())) == (131073,65535), sizes
    w = Watch(details=False, columns=180, rows=50, reply_lines=999999999, event_lines=999999999, no_color=True)
    try:
        lines = compact_frame(w, 'after-large', timeout=6)
        assert '💬 '+'R'*60 in lines[2] and lines[44].endswith('...') and 'after-large' in lines[45], lines
        with path.open('a') as stream:
            stream.write(message('before'+' '*(1024*1024)+'after'))
        assert compact_frame(w,'before after',timeout=6)[2].endswith('💬 before after')
        details = subprocess.check_output([bash,str(cli),'watch','--details'], timeout=8)
        assert big.encode() in details and b'DETAILS-TAIL' in path.read_bytes()
        os.write(w.fd,b'\x03')
        w.finish(130)
    finally:
        w.close()


def screen_resize_history():
    # A real emulator can restore old Ralph rows from its scrollback when the
    # window grows. An isolated snapshot of the most recent frame cannot see them.
    run = 'screen-resize'
    status(run=run, task_index=1)
    path = log(run=run)
    path.write_text(message('visible progress '*30))
    scratch = Path(__file__).resolve().parents[1]/'.tmp'
    with tempfile.TemporaryDirectory(dir=scratch, prefix='s.') as sock:
        env = dict(os.environ, SCREENDIR=sock, HOME=sock, SCREENRC='/dev/null', SYSSCREENRC='/dev/null',
                   TERM='xterm-256color', NO_COLOR='1', RALPH_UI_STICKY_REPLY_LINES='3', RALPH_UI_STICKY_EVENT_LINES='2')
        screen = [shutil.which('screen'), '-c', '/dev/null']
        def control(*args):
            return subprocess.run(screen+['-S','r','-p','0','-X',*args], cwd=workspace, env=env,
                                  capture_output=True, timeout=4).returncode
        server = subprocess.Popen(screen+['-ln','-U','-D','-m','-S','r',bash,'-c',
            'printf "%s\\n" ORIGINAL-SHELL-LINE; exec "$1" "$2" watch','_',bash,str(cli)],
            cwd=workspace, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for i,(cols,rows) in enumerate([(96,24),(34,8),(96,24)]):
                deadline = time.monotonic()+7
                while control('width','-w',str(cols),str(rows)) and time.monotonic()<deadline:
                    time.sleep(.05)
                marker = f'step{i}'
                with path.open('a') as stream:
                    stream.write(json.dumps(dict(type='tool_use',name=marker))+'\n')
                dump = Path(sock)/f'frame-{i}'
                while time.monotonic()<deadline:
                    control('hardcopy',str(dump))
                    view = dump.read_bytes() if dump.exists() else b''
                    if marker.encode() in view and b'visible progress' in view and b'Ctrl+C' in view:
                        break
                    time.sleep(.08)
                else: raise AssertionError(f'GNU Screen {cols}x{rows}: incomplete display')
                assert sum(line.startswith(b'ralph ') for line in view.split(b'\n')) == 1, (cols, rows, view)
            history = Path(sock)/'history'
            deadline = time.monotonic()+3
            while time.monotonic()<deadline:
                control('hardcopy','-h',str(history))
                if history.exists() and b'ORIGINAL-SHELL-LINE' in history.read_bytes(): break
                time.sleep(.05)
            else: raise AssertionError('resize erased earlier shell output')
        finally:
            control('stuff','\x03')
            try: server.wait(timeout=4)
            except subprocess.TimeoutExpired:
                control('quit')
                server.wait(timeout=4)


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
printf '%s %s %s %s' "$_SREPLY_ROWS" "$_SEVENT_WINDOW" "$_SHEALTH_GREEN" "$_SHEALTH_RED"
'''
    cases = [('03', '08', '007', '0300', '3 8 7 300'),
             ('5', 'oops', 'a[$(touch ui-config-executed)]', 'oops', '5 4 60 300'),
             ('a[$(touch ui-config-executed)]', '6', '60', '300', '2 6 60 300'),
             ('0', '0', '400', '300', '2 4 60 300'),
             ('-1', '99999999999999999999', '-1', '0', '2 4 60 300')]
    for replies, window, green, red, expected in cases:
        env = dict(os.environ, RALPH_UI_STICKY_REPLY_LINES=replies, RALPH_UI_STICKY_EVENT_LINES=window,
                   RALPH_UI_HEALTH_GREEN_SEC=green, RALPH_UI_HEALTH_RED_SEC=red)
        result = subprocess.run([bash, '-c', program], cwd=workspace, env=env,
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 0 and result.stdout == expected, result
        assert not result.stderr, result.stderr
        assert not (workspace/'ui-config-executed').exists(), 'UI config executed shell code'

    probe = [bash, '-c', 'source .ralph/lib/sticky.sh; _srefresh_size; printf "%s/%s" "$_SCOLS" "$_SROWS"']
    for cols, rows, expected in [('08','09',b'8/9'), ('999999999','999999999',b'80/24')]:
        env = dict(os.environ, COLUMNS=cols, LINES=rows)
        result = subprocess.run(probe, cwd=workspace, env=env, capture_output=True, start_new_session=True, timeout=4)
        assert result.returncode == 0 and result.stdout == expected and not result.stderr, result
    master, slave = pty.openpty()
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH',12,48,0,0))
        result = subprocess.run(probe, cwd=workspace, env=dict(os.environ, COLUMNS='999999999', LINES='999999999'),
                                stdout=slave, stderr=subprocess.PIPE, start_new_session=True, timeout=4)
        assert result.returncode == 0 and not result.stderr and select.select([master],[],[],2)[0]
        assert os.read(master,128) == b'48/12', 'detached stdout PTY geometry was ignored'
    finally:
        os.close(master)
        os.close(slave)


def sticky_run_interrupt():
    previous_run = json.loads(status_file.read_text())['run_id'] if status_file.exists() else None
    (workspace/'.ralph/TASKS.md').write_text('- [ ] DEV-1: slow fake task\n')
    watcher = Watch(details=False, reply_lines=999999999, command=['run', '--provider', 'fake', '-v', '--max-round', '1'],
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
        with (child_file.parent/'provider.stdout.log').open('a') as stream:
            stream.write(message('PUBLIC-BURST-'+'x'*(512*1024)))
        watcher.expect('PUBLIC-BURST-', timeout=6)
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


def dispatch_identity():
    tasks = workspace/'.ralph/TASKS.md'
    tasks.write_text('- [ ] Repeat this task\n'*2)
    result = subprocess.run([bash, str(cli), 'run', '--provider', 'fake', '--max-round', '1'],
                            env=dict(os.environ, RALPH_FAKE_CLI=bash, RALPH_FAKE_SCENARIO='happy',
                                     RALPH_PROVIDER_CONFIG_DIR=''), capture_output=True, timeout=15)
    data = json.loads(status_file.read_text())
    assert result.returncode == 0 and data['round'] == 2 and data['task_try'] == 1, (result.stderr, data)
    assert data['round_task']['index'] == 2 and 'HUMAN' not in tasks.read_text()

    tasks.write_text('- [ ] Check off then fail\n')
    result = subprocess.run([bash, str(cli), 'run', '--provider', 'antigravity', '--max-retry', '1',
                             '--retry-schedule', '1'], env=dict(os.environ, **mock_antigravity('checked_network_error')),
                            capture_output=True, timeout=15)
    data = json.loads(status_file.read_text())
    run_dir = workspace/data['run_dir']
    final = json.loads((run_dir/'result.json').read_text())
    meta = json.loads((run_dir/'rounds/round-001/meta.json').read_text())
    assert result.returncode == 2 and data['exit_reason'] == final['exit_reason'] == 'provider_failed', data
    assert data['round'] == final['rounds'] == data['tasks_checked'] == 1, (data, final)
    assert data['last_error']['type'] == 'network' and meta['terminal_status'] == 'error', meta
    assert not (workspace/'.ralph/lock').exists()


def dispatch_boundaries():
    tasks = workspace/'.ralph/TASKS.md'
    for missing in (False, True):
        tasks.write_text('- [ ] Single task\n')
        env = mock_antigravity('sticky_progress')
        gate = Path(env['HOME']).parent/'finish'
        env['RALPH_MOCK_STICKY_GATE'] = str(gate)
        w = Watch(command=['run','--provider','antigravity','-v'], no_color=True, env=env)
        try:
            compact_frame(w, 'tool-H')
            if missing:
                tasks.rename(tasks.with_suffix('.saved'))
            else:
                tasks.write_text('# Empty package\n')
            gate.touch()
            w.finish(2 if missing else 0, timeout=8)
            final = json.loads(status_file.read_text())
            assert final['round'] == 1 and final['exit_reason'] == ('provider_failed' if missing else 'done'), final
            if missing: assert 'TASKS.md' in final['last_error']['message']
        finally:
            gate.touch()
            w.close()
    # A fast provider can finish while the supervisor is sleeping until the timeout check.
    tasks.write_text('- [ ] Finishes before deadline\n')
    result = subprocess.run([bash, str(cli), 'run', '--provider', 'fake', '--round-timeout', '1'],
                            env=dict(os.environ, RALPH_FAKE_CLI=bash, RALPH_FAKE_SCENARIO='happy',
                                     RALPH_PROVIDER_CONFIG_DIR=''), capture_output=True, timeout=8)
    assert result.returncode == 0 and json.loads(status_file.read_text())['exit_reason'] == 'done', result

    # Hold the real pre-dispatch Git scan so Ctrl-C arrives before the first provider call.
    tasks.write_text('- [ ] Never dispatched\n')
    probe = Path(tempfile.mkdtemp(dir=workspace))
    hook = probe/'before-dispatch.sh'
    hook.write_text('''git() {
  if [[ "$1" == ls-files && "${2:-}" == -s ]]; then
    touch "$TMPDIR/scanning"
    while [[ ! -f "$TMPDIR/resume" ]]; do sleep .05; done
  fi
  command git "$@"
}
''')
    w = Watch(command=['run','--provider','fake','-v'],
              env=dict(TMPDIR=str(probe), BASH_ENV=str(hook), RALPH_FAKE_CLI=bash,
                       RALPH_FAKE_SCENARIO='happy', RALPH_PROVIDER_CONFIG_DIR=''))
    try:
        deadline = time.monotonic()+8
        while not (probe/'scanning').exists() and time.monotonic()<deadline: w.pump(.05)
        assert (probe/'scanning').exists()
        os.write(w.fd, b'\x03')
        (probe/'resume').touch()
        w.finish(130)
        final = json.loads(status_file.read_text())
        assert final['round'] == 0 and final['round_task'] is None and final['exit_reason'] == 'interrupted', final
        assert not list((workspace/final['run_dir']).glob('rounds/round-*')) and not list(probe.glob('ralph-prompt-*'))
        assert not (workspace/'.ralph/lock').exists() and '[ ]' in tasks.read_text()
    finally:
        (probe/'resume').touch()
        w.close()


def retry_backoff():
    tasks = workspace/'.ralph/TASKS.md'
    for interrupt in (True, False):
        tasks.write_text('- [ ] First\n- [ ] Second\n')
        w = Watch(command=['run', '--provider', 'fake', '-v', '--max-retry', '1',
                           '--retry-schedule', '20' if interrupt else '2'],
                  env=dict(RALPH_FAKE_CLI=bash, RALPH_FAKE_SCENARIO='rate_limit', RALPH_PROVIDER_CONFIG_DIR=''))
        try:
            deadline = time.monotonic()+8
            while time.monotonic() < deadline:
                w.pump(.05)
                data = json.loads(status_file.read_text()) if status_file.exists() else {}
                if data.get('state') == 'running' and data.get('retry_count') == 1 and data.get('next_retry_at'):
                    break
            else:
                raise AssertionError('provider did not enter retry backoff')
            failed_log = workspace/data['run_dir']/'rounds/round-001/provider.stdout.log'
            identity = failed_log.stat().st_ino
            if interrupt:
                os.write(w.fd, b'\x03')
                w.finish(130, timeout=4)
            else:
                tasks.write_text('- [x] First\n- [ ] Second\n')
                w.finish(2, timeout=8)
            final = json.loads(status_file.read_text())
            assert final['exit_reason'] == ('interrupted' if interrupt else 'provider_failed'), final
            assert final['round'] == final['round_task']['index'] == 1
            assert failed_log.stat().st_ino == identity and not (workspace/'.ralph/lock').exists()
            assert termios.tcgetattr(w.fd)[6][termios.VINTR] == b'\x03'
        finally:
            w.close()


def noisy_replay():
    path = log(run='binary-burst')
    def delta(text):
        return (json.dumps(dict(event='step_update', step_update=dict(step_index=1, text_delta=text)))+'\n').encode()
    first = delta('first')
    prefix = b'\0'*len(first) + b'\n' + first
    path.write_bytes(prefix)
    program = r'''set -eu
source .ralph/lib/sticky.sh
ralph_sticky_read_log "$1"
ralph_sticky_read_log "$1"
printf '%s\n%s\n' "$_SREAD_POS" "$_SREPLY_TEXT"
'''
    def replay(script):
        return subprocess.check_output([bash, '-c', script, '_', str(path)], cwd=workspace,
                                       text=True, timeout=8).splitlines()
    assert replay(program) == [str(len(prefix)), 'first']
    tool = dict(event='step_update', step_update=dict(state='DONE', tool_name='big-tool',
                tool_info=dict(output='word '*52428)))
    raw = prefix + b'99999999\n{broken\n' + delta('x')*512 + (json.dumps(tool)+'\n').encode() + delta(' end').rstrip()
    path.write_bytes(raw)
    batch = r'''set -eu
source .ralph/lib/sticky.sh
ralph_sticky_read_log "$1"
echo "$_SREAD_POS"
ralph_sticky_drain_log "$1"
printf '%s\n%s\n%s\n' "$_SREAD_POS" "$_SREPLY_TEXT" "${_SEV_MSGS[*]}"
'''
    pos, end, reply, event = replay(batch)
    assert 0 < int(pos) < len(raw) and int(end) == len(raw), (pos, end)
    assert reply == 'first' + 'x'*512 + ' end' and 'big-tool → word' in event
    with path.open('ab') as f: f.write(b'\n' + message('BURST-COMPLETE').encode())
    status(run='binary-burst', state='finished', done=1, total=1, task_index=1)
    w = Watch(details=False, no_color=True)
    try:
        lines = compact_frame(w, 'BURST-COMPLETE')
        assert lines[2].endswith('💬 BURST-COMPLETE') and 'big-tool' in lines[7], lines
        screen = TerminalScreen(120)
        screen.feed(w.output)
        assert screen.text().count('ralph ') == 1 and b'Broken pipe' not in w.output, screen.text()
    finally:
        w.close()
    assert path.read_bytes() == raw + b'\n' + message('BURST-COMPLETE').encode()


def malformed_watch_metadata():
    run = 'bad-metadata'
    path = log(run=run)
    path.write_text(message('Visible progress'))
    status(run=run, provider='local\x1b[2J\x9b', total=3, task_index='1\x1b[2J\nFORGED')
    injected = 'a[$(touch invalid-metadata-executed)]'
    (path.parents[2]/'context.json').write_text(json.dumps(dict(max_round=injected, stall_limit=injected)))
    (path.parent/'meta.json').write_text(json.dumps(dict(stall_count=injected)))
    for args in (['watch'], ['watch', '--details']):
        output = subprocess.check_output([bash, str(cli), *args], timeout=5)
        assert b'\x1b[2J' not in output and '\x9b'.encode() not in output
    saved_status = status_file.with_suffix('.saved')
    w = Watch(details=False, no_color=True)
    try:
        lines = compact_frame(w, 'Visible progress')
        assert 'tasks -/3' in lines[0] and 'round 1/∞' in lines[9] and 'stall 0/5' in lines[9], lines
        assert b'\x1b[2J' not in w.output and '\x9b'.encode() not in w.output
        status_file.rename(saved_status)
        w.pump(.7)
        os.write(w.fd, b'\x03')
        w.finish(130)
    finally:
        w.close()
        if saved_status.exists():
            saved_status.replace(status_file)
    assert not (workspace/'invalid-metadata-executed').exists()


checked('non-TTY full events, real Codex fields, AGY error/output/final text, raw fallback and controls', snapshot)
checked('TTY replay, status recovery, partial line, three retry sizes, skipped rounds, run change and finish', follow)
checked('persistent corrupt status fails after bounded retries', corrupt_status)
checked('details Ctrl-C leaves provider and running state intact', ctrl_c)
checked('compact watch follows retry log inode replacement', compact_rotation)
checked('compact replay: provider message boundaries, timestamp, partial UTF-8, retry, wrap and final flush', compact_messages)
checked('real run -v and late watch: dispatched ordinal, independent reply height, four tools and completion', compact_dispatch)
checked('compact terminal screen has one header with long CJK/emoji/tab output at 80/120/180 columns, live and finished', compact_no_header_drift)
checked('compact activity persists across frames, turns yellow/red on idle and recovers after log replacement', health_activity)
checked('compact frames read progress and round from one atomic status snapshot', compact_status_consistency)
checked('compact NO_COLOR omits styles and preserves terminal layout controls', compact_no_color)
checked('compact watch loads .env UI configuration and respects process overrides', compact_env_configuration)
checked('live terminal resize keeps Chinese reply, title and events valid in the C locale', compact_live_resize)
if shutil.which('screen'):
    checked('GNU Screen resize restores one visible header and preserves pre-run shell history', screen_resize_history)
checked('bounded public replies and large whitespace runs keep compact and full views usable', compact_large_reply)
checked('status and non-TTY watch read one atomic snapshot per command', atomic_observer_snapshots)
checked('UI numbers use decimal and safely default invalid values without evaluation', ui_config_validation)
checked('run -v keyboard interrupt records final state, releases lock, restores tty and terminates provider child', sticky_run_interrupt)
checked('duplicate titles have separate tries and checked-off provider errors retain the failed round', dispatch_identity)
checked('empty and missing task sources stop dispatch; completed providers retain success at the timeout check', dispatch_boundaries)
checked('retry backoff accepts Ctrl-C and preserves the failed dispatch when the pending task changes', retry_backoff)
checked('binary and forged cursors, bounded bursts, large tool output and unterminated final delta', noisy_replay)
checked('damaged status, context and meta fields cannot write terminal controls or shell arithmetic', malformed_watch_metadata)
checked('actual runtime status writer exposes only complete consistent JSON', atomic_status)
