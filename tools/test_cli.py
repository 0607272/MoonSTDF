"""End-to-end CLI contract, run after moon build --target js."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / '_build/js/debug/build/cmd/main/main.js'

def run(*args, ok=True):
    p = subprocess.run(['node', str(CLI), *map(str,args)], cwd=ROOT,
                       capture_output=True, text=True, encoding='utf-8')
    assert (p.returncode == 0) == ok, (args,p.returncode,p.stdout,p.stderr)
    return p

def main():
    assert CLI.exists(), f'Build CLI first: missing {CLI}'
    assert 'MoonSTDF' in run('--help').stdout
    expected=json.loads((ROOT/'fixtures/expected.json').read_text(encoding='utf-8'))
    for name,want in expected.items():
        path=ROOT/'fixtures'/name
        if 'expected_error' in want:
            malformed=run('analyze',path,ok=False)
            assert malformed.returncode==2 and 'truncated' in malformed.stderr.lower()
            continue
        report=json.loads(run('analyze',path).stdout)
        assert report['record_count']==want['record_count'],name
        assert report['yield']==want['yield'],name
        assert len(report['parts'])==len(want['parts']),name
        for part,target in zip(report['parts'],want['parts']):
            for key in ('head','site','x','y','outcome','hard_bin','soft_bin'):
                assert part[key]==target[key],(name,key)
            assert len(part['tests'])==target['test_count'],name
        if 'ptr_100_mean' in want:
            tests={t['context']['test_number']:t for t in report['tests']}
            assert tests[100]['mean']==want['ptr_100_mean']
            assert tests[100]['usable_samples']==tests[100]['executions']==2
            assert tests[200]['mean']==want['mpr_200_mean']
            assert tests[200]['usable_samples']==2 and tests[200]['executions']==1
            assert tests[300]['executions']==1
            assert not report['diagnostics'],(name,report['diagnostics'])
        else:
            assert all(not t['values'] for part in report['parts'] for t in part['tests'])
        assert len(report['unknown_records'])==(3 if 'ptr_100_mean' in want else 0)
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp)
        bad = p/'bad.stdf'
        bad.write_bytes(bytes([2,0,0,10,2]))
        assert 'offset' in run('analyze',bad,ok=False).stderr.lower()
        run('analyze',p/'absent.stdf',ok=False)
        run('nonsense',ok=False)
        incomplete = p/'far-only.stdf'
        incomplete.write_bytes(bytes([2,0,0,10,2,4]))
        for command in ('compare','retest'):
            partial=json.loads(run(command,incomplete,incomplete).stdout)
            assert any(d['code']=='missing-mrr' and 'before' in d['message'] for d in partial['diagnostics'])
            assert any(d['code']=='missing-mir' and 'after' in d['message'] for d in partial['diagnostics'])
        fixture = ROOT/'fixtures/lot-a-le.stdf'
        if fixture.exists():
            a = json.loads(run('analyze',fixture).stdout)
            assert a['yield']['total'] == 2
            assert a['yield']['denominator'] == 2
            assert a['yield']['yield'] == .5
            b = json.loads(run('analyze',ROOT/'fixtures/lot-a-be.stdf').stdout)
            assert a == b, 'LE/BE semantic reports differ'
            html = p/'report.html'
            run('analyze',fixture,'--format','html','--output',html)
            assert '<svg' in html.read_text(encoding='utf-8')
            csv = run('analyze',fixture,'--format','csv').stdout
            assert 'source_offset' in csv and len(csv.splitlines()) == 3
            comparison=json.loads(run('compare',fixture,ROOT/'fixtures/lot-b-le.stdf').stdout)
            ptr=next(t for t in comparison['tests'] if t['context']['test_number']==100)
            assert ptr['mean_delta']==1.0 and ptr['failure_rate_delta']==0.0
            recovery=json.loads(run('retest',fixture,ROOT/'fixtures/retest-le.stdf','--identity','coordinates').stdout)
            assert recovery['matched']==2 and recovery['recovered']==1
            run('analyze',fixture,'--format','xml',ok=False)
            selected=json.loads(run('analyze',fixture,'--policy','last','--identity','coordinates').stdout)
            assert selected['yield']['total']==2
    print('CLI integration checks passed')

if __name__ == '__main__':
    main()
