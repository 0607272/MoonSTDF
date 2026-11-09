"""Run the same compiled browser API under Node, independent of DOM layout."""
import json
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
script=r'''
const fs=require('node:fs');
require('./_build/js/debug/build/web/core/core.js');
const bytes=new Uint8Array(fs.readFileSync('fixtures/lot-a-le.stdf'));
const report=JSON.parse(MoonSTDF.inspect(bytes));
if(report.yield.yield!==0.5 || report.parts.length!==2)throw Error('browser report');
if(!MoonSTDF.html(bytes).includes('<svg'))throw Error('browser HTML');
const bad=JSON.parse(MoonSTDF.inspect(new Uint8Array([2,0,0,10,2])));
if(!bad.error || bad.offset!==0)throw Error('browser truncation');
console.log(JSON.stringify(report));
'''
p=subprocess.run(['node','-e',script],cwd=root,capture_output=True,text=True,encoding='utf8')
assert p.returncode==0,p.stderr
browser=json.loads(p.stdout)
cli=subprocess.run(['node','_build/js/debug/build/cmd/main/main.js','analyze','fixtures/lot-a-le.stdf'],cwd=root,capture_output=True,text=True,encoding='utf8',check=True)
assert browser==json.loads(cli.stdout),'Browser/CLI core semantic mismatch'
print('Browser shared-core checks passed')
