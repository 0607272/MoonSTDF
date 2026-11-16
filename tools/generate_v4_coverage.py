#!/usr/bin/env python3
"""Original full-field base V4 fixtures and independent field expectations."""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path
from generate_fixtures import Writer, EPOCH, walk_records

ROOT = Path(__file__).resolve().parents[1]
IDS = [(0,10),(0,20),(1,10),(1,20),(1,30),(1,40),(1,50),(1,60),
       (1,62),(1,63),(1,70),(1,80),(2,10),(2,20),(2,30),(5,10),
       (5,20),(10,30),(15,10),(15,15),(15,20),(20,10),(20,20),(50,10),(50,30)]
FIELD_COUNTS = dict(zip(
    ['FAR','ATR','MIR','MRR','PCR','HBR','SBR','PMR','PGR','PLR','RDR','SDR',
     'WIR','WRR','WCR','PIR','PRR','TSR','PTR','MPR','FTR','BPS','EPS','GDR','DTR'],
    [2,2,38,4,7,6,6,7,4,8,2,20,4,14,9,2,12,16,20,27,28,1,0,2,1]))


class VaxWriter(Writer):
    """Independent VAX F/D encoder; integer words remain little endian."""
    def __init__(self):
        super().__init__('<')

    def pack(self, layout, *values):
        result = bytearray()
        assert len(layout) == len(values)
        for kind, value in zip(layout, values):
            if kind not in 'fd':
                result.extend(struct.pack('<' + kind, value))
                continue
            words = 2 if kind == 'f' else 4
            if value == 0:
                result.extend(bytes(words * 2))
                continue
            mantissa, exponent = math.frexp(abs(value))
            width = words * 16 - 9
            fraction = round((mantissa * 2 - 1) * 2**width)
            if fraction == 2**width:
                fraction = 0
                exponent += 1
            biased = exponent + 128
            assert 0 < biased < 256
            first = ((value < 0) << 15) | (biased << 7) | (fraction >> (width - 7))
            result.extend(struct.pack('<H', first))
            for shift in range(width - 23, -1, -16):
                result.extend(struct.pack('<H', (fraction >> shift) & 65535))
        return bytes(result)


def coverage(endian, vax=False):
    w = VaxWriter() if vax else Writer(endian)
    p, cn, rec = w.pack, w.cn, w.record
    strings = lambda values: b''.join(cn(v) for v in values)
    rec(0,10,bytes([0 if vax else (2 if endian=='<' else 1),4]))
    rec(0,20,p('I',EPOCH)+cn('synthetic coverage'))
    names=['LOT-COVER','DUT','NODE','TESTER','JOB']+[f'MIR-{i}' for i in range(25)]
    rec(1,10,p('IIBcccHc',EPOCH,EPOCH+1,1,b'P',b'Y',b' ',65535,b' ')+strings(names))
    rec(1,70,p('HHH',2,1,2))
    rec(1,80,bytes([1,7,1,1])+strings([f'SDR-{i}' for i in range(16)]))
    for index in [1,2,3]:
        rec(1,60,p('HH',index,7)+strings([f'C{index}',f'P{index}',f'L{index}'])+bytes([1,1]))
    rec(1,62,p('H',32768)+cn('BUS')+p('HHHH',3,1,2,3))
    rec(1,63,p('HHHB',1,32768,32769,16)+strings(['01','LH','01','LH']))
    rec(2,10,p('BBI',1,7,EPOCH+2)+cn('WAFER-COVER'))
    rec(2,30,p('fffBchhcc',200.0,5.0,4.0,3,b'D',-2,3,b'R',b'U'))
    rec(50,30,cn('Original fixture: every active base V4 record'))
    generic=bytearray()
    types=[]
    def value(code, data):
        if code in (2,3,5,6,7,8) and (2+len(generic)+1)%2:
            generic.append(0)
            types.append(0)
        generic.append(code)
        generic.extend(data)
        types.append(code)
    for code,data in [(1,p('B',255)),(2,p('H',500)),(3,p('I',4000000000)),
                      (4,p('b',-12)),(5,p('h',-1234)),(6,p('i',-123456)),
                      (7,p('f',1.5)),(8,p('d',-2.5)),(10,cn('hello')),
                      (11,bytes([2,0,255])),(12,p('H',9)+bytes([255,1])),(13,bytes([15]))]:
        value(code,data)
    rec(50,10,p('H',len(types))+generic)
    rec(5,10,bytes([1,1]))
    rec(20,10,cn('MAIN'))
    rec(15,10,p('IBBBBf',100,1,1,0,192,1.5)+strings(['voltage','alarm'])+
        p('Bbbbff',2,6,-3,3,1.0,3.0)+strings(['V','%f','%f','%f'])+p('ff',0.5,3.5))
    rec(15,15,p('IBBBBHH',200,1,1,0,192,3,2)+bytes([0x21,3])+p('ff',2.0,2.5)+
        strings(['multi',''])+p('BbbbffffHHH',206,0,0,0,0.0,0.0,10.0,0.5,1,2,3)+
        strings(['V','s','%f','%f','%f'])+p('ff',0.0,5.0))
    ftr=p('IBBBB',300,1,1,0,192)+p('IIIIiihHH',100,200,2,0,-3,4,-2,2,1)
    ftr+=p('HH',1,2)+bytes([0x21])+p('H',3)+bytes([3])+p('H',3)+bytes([7])
    ftr+=strings(['vector','time','op','functional','alarm','program','result'])
    rec(15,20,ftr+bytes([2])+p('H',3)+bytes([5]))
    rec(20,20,b'')
    rec(5,20,p('BBBHHHhhI',1,1,0,3,1,10,-1,2,25)+strings(['PART-COVER','note'])+bytes([2,0,255]))
    rec(10,30,p('BBcIIII',255,255,b'P',100,1,0,0)+strings(['TEST-100','MAIN','label'])+
        bytes([200])+p('fffff',0.1,1.5,1.5,1.5,2.25))
    rec(1,40,p('BBHIc',255,255,1,1,b'P')+cn('PASS'))
    rec(1,50,p('BBHIc',255,255,10,1,b'P')+cn('PASS'))
    rec(1,30,p('BBIIIII',255,255,1,0,0,1,1))
    rec(2,20,p('BBIIIIII',1,7,EPOCH+100,1,0,0,1,1)+strings(['WAFER-COVER','FAB','FRAME','MASK','user','exec']))
    rec(1,20,p('Ic',EPOCH+101,b'P')+strings(['user end','exec end']))
    data=b''.join(w.records)
    records=walk_records(data)
    assert set((t,s) for t,s,_ in records)==set(IDS)
    return data, types


def generate(check=False):
    manifest={'scope':'25 active base STDF V4 records, all fields populated',
              'record_ids':IDS,'field_counts':FIELD_COUNTS,'files':{}}
    files={}
    for endian,suffix in [('<','le'),('>','be'),('<','vax')]:
        data,codes=coverage(endian, vax=suffix=='vax')
        name=f'v4-all-records-{suffix}.stdf'
        files[name]=data
        manifest['files'][name]={'sha256':hashlib.sha256(data).hexdigest(),
                                'record_count':len(walk_records(data)), 'gdr_codes':codes}
    files['v4-coverage.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    for name,data in files.items():
        path=ROOT/'fixtures'/name
        if check:
            assert path.read_bytes()==data, f'fixture differs: {path}'
        else:
            path.write_bytes(data)
    print(('Checked' if check else 'Generated')+' full-field V4 coverage fixtures')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    generate(parser.parse_args().check)
