# Sources, originality and licenses

MoonSTDF is an original MoonBit implementation under MIT. It is not a port of
an existing STDF decoder. No upstream implementation source or industrial
test file is bundled. The core has only MoonBit standard-library imports;
Python fixture/integration scripts use the standard library and Node hosts IO.

| Reference | Purpose | License / handling |
|---|---|---|
| [Teradyne STDF V4 specification, pinned mirror](https://github.com/Semi-ATE/Semi-ATE/blob/d2febc29c08cf65d21277628ac9bb50724a9ae46/old-docs/standards/STDF/STDF-V4-spec.pdf) | Primary record layouts, optional fields and flag semantics | Copyrighted format documentation; linked, not redistributed or relicensed |
| [rust-stdf, pinned revision](https://github.com/noonchen/rust-stdf/tree/5160dc3859ea1ed19c94f008a1a6133299715993) | Independent implementation reference for layouts | MIT; no source copied or ported |
| [Semi-ATE-STDF](https://github.com/Semi-ATE/STDF), version 0.1.28 | External differential decoder for synthetic fixtures | MIT; development-only, not bundled or required at runtime |
| [PySTDF](https://github.com/cmars/pystdf) | Corroborating format field descriptions consulted during research | GPL; no code copied, imported, translated or redistributed |
| MoonBit core | Standard types, JSON and debug interfaces | Supplied by the official MoonBit toolchain; not vendored |

`tools/generate_fixtures.py` independently encodes the documented binary
layout using Python `struct`. Every binary in `fixtures/` and its expected
sidecar is original MIT data. It contains synthetic lot/product/part names,
fixed timestamps and invented measurements, with no customer data.

On 2026-11-09, the external decoder agreed on record counts and selected
CPU/SDR/PRR/PTR/MPR raw fields in all five valid generated files. It silently
ignored the final truncated MRR in the malformed fixture; MoonSTDF rejects it
at EOF with exit code 2. This is a bounded differential check, not a full
STDF conformance or numerical-analysis certification.

No claim of worldwide originality of the application category is made.
The development topic search found no matching STDF tool in the searched
MoonBit ecosystem scope as of 2026-11-09; that search is not exhaustive.
