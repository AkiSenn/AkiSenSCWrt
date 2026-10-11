#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
lock = json.loads((root / 'sources.lock.json').read_text())
source = Path(sys.argv[1]).resolve()
source.mkdir(parents=True, exist_ok=False)
def git(*args):
    subprocess.run(['git', '-C', str(source), *args], check=True)
git('init')
git('remote', 'add', 'origin', lock['source']['url'])
git('fetch', '--depth=1', 'origin', lock['source']['commit'])
git('checkout', '--detach', 'FETCH_HEAD')
(source / 'feeds.conf.default').write_text(''.join(
    f"src-git {name} {spec['url']}^{spec['commit']}\n"
    for name, spec in lock['feeds'].items()), newline='\n')
print('Pinned firmware source:', lock['source']['commit'])
