# STDF V4 support matrix

Scope: base STDF V4, CPU_TYPE 1 (big endian) and 2 (little endian).
This is a typed projection and analysis library, not a complete validator.

| Records / layer | Implemented | Boundary |
|---|---|---|
| Framing | REC_LEN/REC_TYP/REC_SUB, FAR detection, offsets, incremental feeds, truncated EOF and budgets | Uncompressed input only; no V4-2007 extensions |
| FAR | CPU, version, length and order consistency | Must be first; CPU 0 unsupported |
| MIR/MRR | Lot identity subset and lot termination | Other fields structurally consumed, not all exposed |
| SDR/WIR/WRR | Head/site-group membership, wafer identity, lifecycle | Missing membership may use sole same-head wafer with a diagnostic; ambiguity stays unresolved |
| WCR | Dimensions, center and orientation fields | Analyzer does not apply physical coordinate transformations |
| PIR/PRR | Part lifecycle, outcome/abnormal flags, coordinates, bins, ID | Missing/unfinished parts are diagnosed; no automatic supersession |
| PTR | Value, status, text, optional limits/units/display defaults | Legal omitted invalid RESULT accepted; no fabricated zero; fields beyond projection not analyzed |
| MPR | Values, packed return states/indexes, optional defaults | Sample and execution counts differ; no one-result-per-pin assumption |
| FTR | Status, text, returned indexes/states; full structural cursor checks | No numeric synthetic result; no PATG/SPIN_MAP default resolution or pin failure analysis |
| PCR/HBR/SBR/TSR | Selected counts, labels and guarded reconciliation | Not full summary semantics or proof of complete acquisition |
| Other records incl. PMR | Frame body/order/offset retained as raw unknown | No typed validation; can contain vendor-specific or sensitive payloads |
| Statistics | Explicit yield denominators, grouped yields, finite distributions and population SD | Reported outcomes and numeric limit violations remain separate |
| Retest | Explicit first/last, coordinate/part-ID identity, pair recovery/bin migration | No inferred timestamps, global serial identities or automatic disposition |
| Comparison | Exact compatible signatures, mean/fail-rate deltas | No unit conversion, normalization or significance tests |
| Exports | JSON, parts CSV, offline HTML with logical SVG maps | No round-trip writer; CSV formula-leading text escaped |

Strings use single-byte STDF character decoding, not arbitrary Unicode or a
vendor locale detector. Optional tails are accepted only at valid field
boundaries; partial fields are rejected. Some reserved bits are checked, but
not every standard semantic invariant is implemented. Unknown records are
preserved rather than certified.

Both Framer and Analyzer enforce configurable byte/record budgets. Total
memory additionally includes decoded objects, result arrays and report text;
the default 256 MiB input limit is not a memory-use guarantee. Browser analysis
currently runs on the main thread and parses once each for JSON and HTML.

Reports contain lot IDs, part IDs and raw unknown bytes. The tool performs no
network upload, but users should review report contents before sharing them.

Supported tested targets: JS, Wasm, WasmGC. The file CLI and web bridge are
JS-only packages; the library and `examples/demo` are portable. Native source
checking succeeds, but Native execution is not currently part of the support
promise. Tests use original synthetic inputs; broader vendor interoperability
remains future work.
