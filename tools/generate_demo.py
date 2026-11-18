"""Reproduce review artifacts from real CLI validation and full-field output.

Run after moon build --target js. No extra Python packages are required.
"""
import argparse
import html
import json
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / '_build/js/debug/build/cmd/main/main.js'
SAMPLE = 'fixtures/v4-all-records-le.stdf'
OUTPUT = ROOT / 'examples/output'


def cli(command):
    result = subprocess.run(['node', str(CLI), command, SAMPLE], cwd=ROOT,
                            check=True, capture_output=True, text=True, encoding='utf8')
    return result.stdout


def generate(check=False):
    validation = json.loads(cli('validate'))
    if not validation['valid'] or validation['diagnostics']:
        raise ValueError('Sample did not pass structural validation')
    records = [json.loads(line) for line in cli('dump').splitlines()]
    assert validation['record_count'] == len(records) == 27
    assert len({r['name'] for r in records}) == 25
    manifest = json.loads((ROOT / 'fixtures/v4-coverage.json').read_text(encoding='utf8'))
    support = (ROOT / 'SUPPORT.md').read_text(encoding='utf8')
    rows = re.findall(r'^\| ([A-Z]+) \| (\d+)/(\d+) \| (\d+) \| 已支持 \|', support, re.M)
    assert len(rows) == 25 and len({r[0] for r in rows}) == 25, 'Incomplete SUPPORT.md'
    assert {name: int(count) for name, _, _, count in rows} == manifest['field_counts']
    assert {(int(typ), int(sub)) for _, typ, sub, _ in rows} == {
        tuple(record_id) for record_id in manifest['record_ids']}, 'Support IDs differ'
    ptr = next(r for r in records if r['name'] == 'PTR')
    pretty = lambda value: json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    # Reformat, never replace or invent values; keep all fields and raw bytes.
    compact_ptr = '{\n' + ',\n'.join(
        ('  "fields": [\n' + ',\n'.join(
            '    ' + json.dumps(field, ensure_ascii=False, separators=(',', ':'))
            for field in value) + '\n  ]') if key == 'fields'
        else '  ' + json.dumps(key) + ': ' + json.dumps(value, ensure_ascii=False)
        for key, value in ptr.items()) + '\n}\n'
    page = '''<!doctype html><html lang="en"><meta charset="utf-8">
<title>MoonSTDF — actual STDF V4 JSON output</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#eef2f6;color:#142a40;font:15px system-ui,sans-serif}
main{max-width:1500px;margin:auto;padding:28px}h1{margin:0 0 8px;font-size:28px}
p{margin:8px 0 18px;color:#465b70}.badge{background:#d8f3e6;color:#12573b;padding:5px 10px;border-radius:6px}
.grid{display:grid;grid-template-columns:370px minmax(0,1fr);gap:18px}section{background:white;border:1px solid #d0dbe6;border-radius:10px;overflow:hidden}
h2{font-size:16px;padding:14px 18px;margin:0;border-bottom:1px solid #dce4eb}
pre{padding:15px 18px;margin:0;font:12px/1.5 Consolas,monospace;white-space:pre-wrap;overflow-wrap:anywhere;color:#183d59}
a{color:#12649b}footer{margin-top:16px;color:#465b70;font-size:13px}
@media(max-width:850px){.grid{grid-template-columns:1fr}}
</style><main><h1>MoonSTDF / STDF V4 → JSON</h1>
<p><span class="badge">VALID · 27 records · 25 record types</span> CPU_TYPE 2 · IEEE little endian · original synthetic data</p>
<p>Input: <a href="../../fixtures/v4-all-records-le.stdf">v4-all-records-le.stdf</a> ·
<a href="records.jsonl">All records (JSONL)</a> · <a href="ptr-record.json">PTR JSON</a></p>
<div class="grid"><section><h2>validate · complete JSON result</h2><pre>VALIDATION</pre></section>
<section><h2>dump · complete PTR record / all 20 fields</h2><pre>RECORD</pre></section></div>
<footer>Actual CLI output, reformatted for reading. Reproduce: moon build --target js &amp;&amp; python tools/generate_demo.py<br>
Base V4 field decoding and documented checks; not a vendor interoperability or full conformance certificate.</footer></main></html>
'''.replace('VALIDATION', html.escape(pretty(validation))).replace('RECORD', html.escape(compact_ptr))
    files = {
        'records.jsonl': ''.join(json.dumps(r, ensure_ascii=False, separators=(',', ':')) + '\n' for r in records),
        'validation.json': pretty(validation),
        'ptr-record.json': pretty(ptr),
        'preview.html': page,
    }
    if not check:
        OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        path = OUTPUT / name
        if check:
            assert path.read_text(encoding='utf8') == content, f'Outdated example: {path}'
        else:
            path.write_bytes(content.encode('utf8'))
    print(('Checked' if check else 'Generated') + ': 27 records, 25 types, valid JSON examples')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    generate(parser.parse_args().check)
