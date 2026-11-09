# Original synthetic STDF V4 fixtures

All files here are generated from scratch with Python `struct`; no customer,
vendor, proprietary or externally copied test data is included. They are
covered by this repository's MIT license. The generator has no third-party
dependencies and does not import MoonSTDF.

```sh
python tools/generate_fixtures.py
python tools/generate_fixtures.py --check
```

| File | Expected behavior |
|---|---|
| `lot-a-le.stdf` | Little endian, 2 completed parts, 1 pass / 1 fail, known yield 0.5; voltage values 1 and 4 V, mean 2.5 V |
| `lot-a-be.stdf` | Big endian, same semantic contents as lot A little endian |
| `lot-b-le.stdf` | Independent lot, voltage values 2 and 5 V, mean 3.5 V; same known yield 0.5 |
| `retest-le.stdf` | Same lot/wafer/part IDs and coordinates as lot A, second part recovers; voltage values 1 and 2 V, yield 1.0 |
| `optional-boundaries-le.stdf` | Legal omitted invalid PTR RESULT, omitted zero MPR counters at both boundaries; 1 part, 3 executions, no numeric samples |
| `malformed-truncated.stdf` | Lot A with the final MRR body byte removed; must fail at EOF |

The normal files contain FAR, all five required MIR identity strings, SDR
group 7 mapping head 1 sites 1 and 2, WIR, WCR geometry, default-only PTR
limits 1..3 V, interleaved multisite PIR/test records, an MPR with three
low-nibble-first states and two results, a minimal seven-byte FTR, PRRs at
(0,0) and (1,0), PCR/HBR/SBR/TSR summaries, WRR, and MRR. The default-only
PTR is not an execution. Three original PMRs identify the MPR's three input
states; the MPR supplies their indexes and has two output samples, 2.0 and
2.5 V (mean 2.25 V). This is not a one-result-per-pin measurement. Normal lot
files have 27 records; the recovery file has 25 because empty fail-bin
summaries are omitted. PMRs remain raw unknown records in MoonSTDF's current
typed projection (three unknown records is expected).

PRR file order is site 2 then site 1 to exercise parallel association.
The retest file sets PRR coordinate-supersession bit 1; selecting or comparing
retests remains an explicit consumer operation. Base values are already in
volts, and display scaling never changes arithmetic values.

`expected.json` records independently inspected record counts, raw values,
part outcomes, and SHA-256 checksums. Its `records` keys are decimal
`REC_TYP/REC_SUB`. It is a compact expectation sidecar, not a complete
MoonSTDF report schema.

External decoder checks and product CLI comparisons are recorded separately
in the development workspace's `docs/moonstdf-differential.md`; the external
decoder is not a product/runtime dependency and is not bundled here.
