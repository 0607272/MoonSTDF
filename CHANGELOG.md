# Changelog

## Unreleased — 2026-11-18

- Put the general-purpose MoonBit STDF V4 scope, record inventory and explicit
  read/decode/validate/JSON pipeline at the top of the README.
- Add root SUPPORT.md with all 25 base V4 record statuses and field counts.
- Publish original sample input with real CLI JSON/JSONL outputs and a browser
  screenshot, plus a stdlib-only reproduction script checked by CI.

## Unreleased — 2026-11-16

- Complete named-field decoding for all 25 active base STDF V4 record types,
  preserving omitted suffixes, source frames and raw bytes separately from
  the application analysis projections.
- Add nine ancillary record decoders, all GDR types, U*2 PLR modes and
  CPU_TYPE 0 VAX F/D numeric representation (including single-rounding D conversion).
- Add streaming `dump` JSONL and `validate` CLI commands. Guard input files
  against output aliasing and preserve meaningful failure exit codes.
- Check initial record sequence, required/final records, pin references,
  program sections, part/wafer lifecycles and reserved test flags.
- Add original all-field fixtures for IEEE LE/BE/VAX, independent numeric
  expectations, all-record minimal-prefix/truncation tests and CI integration.
- Clarify full base V4 parsing scope, reusable data-platform/audit scenarios,
  analysis boundaries and reference provenance.
