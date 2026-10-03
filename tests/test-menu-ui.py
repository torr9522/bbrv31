#!/usr/bin/env python3
"""Render a deterministic menu in a real PTY at the supported widths."""
import fcntl, os, pathlib, pty, re, struct, subprocess, sys, termios

root = pathlib.Path(__file__).resolve().parents[1]
snapshots = root / 'tests/fixtures/menu'
ansi = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
setup = '''source src/menu.sh
detect_state() {
OS_NAME='Debian GNU/Linux 12'; VIRT=kvm; ARCH=amd64
RUNNING_KERNEL=6.18.54-x64v3-xanmod1
FORMAL_KERNEL_INSTALLED=YES; FORMAL_KERNEL_RUNNING=YES
FALLBACK_COUNT=2; CC_ACTIVE=bbr; QDISC='fq (mq)'
PROJECT_INSTALLED=YES; PROJECT_VERSION=TEST; PERSISTENCE=已启用; LATEST_VERSION=TEST
}
'''

def render(cols, no_color=False):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, cols, 0, 0))
    env = dict(os.environ, TERM='xterm', LC_ALL='C.UTF-8')
    env.pop('COLUMNS', None)
    env.pop('LINES', None)
    env.pop('NO_COLOR', None)
    if no_color:
        env['NO_COLOR'] = ''
    p = subprocess.Popen(['bash', '-c', setup + 'detect_state; render_ui'], cwd=root,
                         stdin=slave, stdout=slave, stderr=slave, env=env)
    os.close(slave)
    data = b''
    while True:
        try:
            data += os.read(master, 65536)
        except OSError:
            break
    os.close(master)
    assert p.wait() == 0
    raw = data.decode().replace('\r', '')
    plain = ansi.sub('', raw)
    plain = re.sub(r'\[v[0-9.]+\]', '[vTEST]', plain)
    return raw, plain

for cols in (60, 80, 100, 120):
    raw, plain = render(cols)
    assert '\x1b[1;32m' in raw and '\x1b[1;31m' in raw
    install_line = next(line for line in plain.splitlines() if '1. 安装' in line)
    assert ('2. 检查' in install_line) == (cols >= 96)
    target = snapshots / f'installed-{cols}col.txt'
    if '--update' in sys.argv:
        snapshots.mkdir(parents=True, exist_ok=True)
        target.write_text(plain)
    assert target.read_text() == plain
raw, plain = render(100, True)
assert '\x1b[1;' not in raw
target = snapshots / 'no-color.txt'
if '--update' in sys.argv:
    target.write_text(plain)
assert target.read_text() == plain
installed_setup = setup
setup += '''detect_installed() { :; }
eval "$(declare -f detect_state | sed '1s/detect_state/detect_original/')"
detect_state() { detect_original; FORMAL_KERNEL_INSTALLED=NO; FORMAL_KERNEL_RUNNING=NO; PROJECT_INSTALLED=NO; PROJECT_VERSION=未安装; PERSISTENCE=未启用; CC_ACTIVE=cubic; QDISC=fq_codel; }
'''
raw, plain = render(100, True)
target = snapshots / 'uninstalled-100col.txt'
if '--update' in sys.argv:
    target.write_text(plain)
assert target.read_text() == plain
setup = installed_setup
width = subprocess.check_output(['bash', '-c', "source src/menu-ui.sh; ui_width $'\\e[32m中文ABC\\e[0m'"], cwd=root, text=True)
assert width.strip() == '7'
plain = subprocess.check_output(['bash', '-c', setup + 'detect_state; render_ui'], cwd=root, text=True)
assert '\x1b' not in plain
# Run the original numeric dispatcher with harmless action recording.
script = setup + '''render() { :; }
pause() { :; }
run_action() { echo "ACTION=$1"; }
main
'''
out = subprocess.check_output(['bash', '-c', script], cwd=root,
                             input='1\n2\n3\n4\n5\n6\n7\n8\n9\n10\nabc\n999\n\n0\n', text=True)
actions = re.findall(r'ACTION=(\w+)', out)
assert actions == ['install', 'install', 'optimize', 'status', 'kernel', 'rollback', 'recover', 'advanced', 'update', 'uninstall']
assert out.count('无效选项') == 3
print('PASS menu widths 60/80/100/120, CJK/ANSI, colors, snapshots and numeric dispatch')
