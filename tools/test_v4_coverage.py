"""Full-field oracle checks, both endians, invalid counts and file ordering."""
import json
import subprocess
import tempfile
from pathlib import Path
from generate_fixtures import walk_records

ROOT=Path(__file__).resolve().parents[1]
CLI=ROOT/'_build/js/debug/build/cmd/main/main.js'


def run(command,path,valid=True):
    p=subprocess.run(['node',str(CLI),command,str(path)],cwd=ROOT,
                     text=True,encoding='utf8',capture_output=True)
    assert p.returncode==(0 if valid else 2),(command,path,p.stderr,p.stdout)
    return p.stdout


def main():
    manifest=json.loads((ROOT/'fixtures/v4-coverage.json').read_text())
    normalized=[]
    for filename,expected in manifest['files'].items():
        path=ROOT/'fixtures'/filename
        records=[json.loads(s) for s in run('dump',path).splitlines() if s]
        validation=json.loads(run('validate',path))
        assert validation['valid'] and not validation['diagnostics']
        assert validation['record_count']==len(records)==expected['record_count']
        assert len(validation['record_counts'])==25
        raw=walk_records(path.read_bytes())
        for record, (_,_,body) in zip(records,raw):
            assert bytes(record['raw_body'])==body
            assert len(record['fields'])==manifest['field_counts'][record['name']],record['name']
            assert all(field['decoded']['present'] for field in record['fields']),record['name']
        by_name={r['name']:{f['name']:f['decoded'] for f in r['fields']} for r in records}
        def scalar(name,field):return by_name[name][field]['value']
        assert scalar('PLR','GRP_MODE')[0]['value']==32769
        assert scalar('MIR','SUPR_NAM')=='MIR-24'
        assert scalar('SDR','EXTR_ID')=='SDR-15'
        assert scalar('FTR','XFAIL_AD')==-3 and scalar('FTR','VECT_OFF')==-2
        assert scalar('FTR','PGM_INDX')[0]['value']==3
        assert scalar('FTR','SPIN_MAP')==[5]
        assert scalar('PRR','PART_FIX')==[0,255]
        assert scalar('WRR','EXC_DESC')=='exec'
        assert scalar('TSR','TST_SQRS')==2.25
        assert scalar('PTR','LO_SPEC')==0.5
        generic=scalar('GDR','GEN_DATA')
        values={v['type']:v.get('value') for v in generic}
        assert values['U*4']==4000000000 and values['I*4']==-123456
        assert values['R*8']==-2.5 and values['B*n']==[0,255]
        semantic=[{k:v for k,v in r.items() if k not in ('representation','raw_body')} for r in records]
        semantic[0]['fields'][0]['decoded']['value']=2  # FAR declares its source CPU.
        normalized.append(semantic)
    assert normalized[0]==normalized[1]==normalized[2],'LE/BE/VAX fields differ'
    with tempfile.TemporaryDirectory() as directory:
        directory=Path(directory)
        data=(ROOT/'fixtures/v4-all-records-le.stdf').read_bytes()
        incomplete=directory/'incomplete.stdf'
        incomplete.write_bytes(bytes([2,0,0,10,2,4]))
        report=json.loads(run('validate',incomplete,False))
        assert {d['code'] for d in report['diagnostics']}=={'missing-mir','missing-mrr','missing-pcr'}
        bad=directory/'post-mrr.stdf'
        bad.write_bytes(data+bytes([1,0,50,30,0]))
        report=json.loads(run('validate',bad,False))
        assert any(d['code']=='after-mrr' for d in report['diagnostics'])
        # A PMR optional U2 cannot be cut after one byte.
        bad.write_bytes(bytes([2,0,0,10,2,4,3,0,1,60,1,0,5]))
        p=subprocess.run(['node',str(CLI),'dump',str(bad)],cwd=ROOT,capture_output=True,text=True)
        assert p.returncode==2 and 'partial' in p.stderr
    print('25-record full-field LE/BE/VAX, raw bytes, missing fields and validation checks passed')


if __name__=='__main__':main()
