#!/usr/bin/env python3
"""Generate original, deterministic STDF V4 fixtures using Python's stdlib.

No MoonSTDF implementation or third-party writer is imported. Layouts follow
Teradyne STDF V4: FAR16, MIR18, SDR33, WIR35, WCR38, PRR41, TSR43,
PTR45, MPR51, FTR55 (printed specification pages).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "fixtures"
EPOCH = 1_700_000_000
MISSING_COUNT = 0xFFFFFFFF


class Writer:
    def __init__(self, endian: str):
        assert endian in ("<", ">")
        self.endian = endian
        self.records: list[bytes] = []

    def pack(self, layout: str, *values: object) -> bytes:
        return struct.pack(self.endian + layout, *values)

    @staticmethod
    def cn(text: str) -> bytes:
        value = text.encode("ascii")
        assert len(value) <= 255
        return bytes([len(value)]) + value

    def record(self, typ: int, sub: int, body: bytes) -> None:
        assert len(body) <= 0xFFFF
        self.records.append(self.pack("HBB", len(body), typ, sub) + body)

    def metadata(self, lot: str = "LOT-A", wafer: str = "WAFER-A") -> None:
        self.record(0, 10, bytes([2 if self.endian == "<" else 1, 4]))
        # All five required identity C*n fields are physically present. Six
        # fixed bytes after STAT_NUM include the U*2 BURN_TIM sentinel.
        mir = self.pack("IIBcccHc", EPOCH, EPOCH + 1, 1, b"P", b" ", b" ",
                        0xFFFF, b" ")
        mir += b"".join(self.cn(x) for x in [lot, "SYNTHETIC-DUT", "NODE-1", "PY-STRUCT", "FIXTURE"])
        self.record(1, 10, mir)
        self.record(1, 80, bytes([1, 7, 2, 1, 2]))  # SDR group 7, sites 1 and 2.
        self.record(2, 10, self.pack("BBI", 1, 7, EPOCH + 2) + self.cn(wafer))
        self.record(2, 30, self.pack("fffBchhcc", 200.0, 5.0, 5.0, 3, b"D", 0, 0, b"R", b"U"))

    def ptr_default(self) -> None:
        # Not executed, PARM_FLG=0. RESULT is present so optional metadata may
        # follow. Scaling=0: stored and displayed values are both volts.
        prefix = self.pack("IBBBBf", 100, 1, 1, 0x10, 0, 0.0)
        tail = self.cn("Voltage") + self.cn("") + self.pack("Bbbbff", 0x02, 0, 0, 0, 1.0, 3.0)
        self.record(15, 10, prefix + tail + self.cn("V"))

    def ptr(self, site: int, value: float, failed: bool) -> None:
        # Equality at both bounds passes; all per-test metadata is inherited.
        self.record(15, 10, self.pack("IBBBBf", 100, 1, site, 0x80 if failed else 0, 0xC0, value))

    def prr(self, site: int, failed: bool, tests: int, retest: bool = False) -> None:
        flags = (0x08 if failed else 0) | (0x02 if retest else 0)
        hard, soft = (2, 20) if failed else (1, 10)
        body = self.pack("BBBHHHhhI", 1, site, flags, tests, hard, soft, site - 1, 0, 25)
        body += self.cn(f"PART-{site}")
        self.record(5, 20, body)

    def summaries(self, good: int, retested: bool = False) -> None:
        self.record(1, 30, self.pack("BBIIIII", 255, 255, 2, 2 if retested else 0,
                                    0, good, MISSING_COUNT))
        for bin_number, count, passed in [(1, good, True), (2, 2 - good, False)]:
            if not count:
                continue
            self.record(1, 40, self.pack("BBHIc", 255, 255, bin_number, count, b"P" if passed else b"F") + self.cn("PASS" if passed else "FAIL"))
            self.record(1, 50, self.pack("BBHIc", 255, 255, bin_number * 10, count, b"P" if passed else b"F") + self.cn("PASS" if passed else "FAIL"))
        for number, kind, count, failed in [(100, b"P", 2, 2 - good), (200, b"P", 1, 0), (300, b"F", 1, 0)]:
            # No OPT_FLAG or statistics are supplied; the entire optional tail
            # stops after three named C*n strings, so no reserved flag issue.
            body = self.pack("BBcIIII", 255, 255, kind, number, count, failed, 0)
            self.record(10, 30, body + self.cn(f"TEST-{number}") + self.cn("") + self.cn(""))

    def finish(self, total: int, good: int, wafer: str = "WAFER-A", retested: bool = False) -> bytes:
        body = self.pack("BBIIIIII", 1, 7, EPOCH + 100, total,
                         total if retested else 0, 0, good, MISSING_COUNT)
        self.record(2, 20, body + self.cn(wafer))
        self.record(1, 20, self.pack("I", EPOCH + 101))
        return b"".join(self.records)


def lot_fixture(endian: str, shifted: bool = False, recovery: bool = False) -> bytes:
    writer = Writer(endian)
    writer.metadata(lot="LOT-B" if shifted else "LOT-A")
    for index in [1, 2, 3]:
        pmr = writer.pack("HH", index, 0)
        pmr += writer.cn(f"CH{index}") + writer.cn(f"P{index}") + writer.cn(f"D{index}")
        writer.record(1, 60, pmr + bytes([1, 1]))
    writer.ptr_default()
    writer.record(5, 10, bytes([1, 1]))
    writer.record(5, 10, bytes([1, 2]))
    writer.ptr(2, 2.0 if recovery else 5.0 if shifted else 4.0, not recovery)
    writer.ptr(1, 2.0 if shifted else 1.0, False)
    # Three returned input pin states and two parametric output samples are
    # independent array counts, not a one-result-per-pin measurement. Supply
    # referenced PMR indexes explicitly on this first MPR. Input conditions,
    # test/spec limits are invalid/absent (OPT_FLAG=0xCE); trailing formatting
    # strings and specification values are omitted. Low nibble is first.
    mpr = writer.pack("IBBBBHH", 200, 1, 1, 0, 0xC0, 3, 2)
    mpr += bytes([0x21, 0x03]) + writer.pack("ff", 2.0, 2.5)
    mpr += writer.cn("Input states and output samples") + writer.cn("")
    mpr += writer.pack("BbbbffffHHH", 0xCE, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 1, 2, 3)
    writer.record(15, 15, mpr + writer.cn("V"))
    # A minimal legal FTR ends immediately after TEST_FLG (7-byte body).
    writer.record(15, 20, writer.pack("IBBB", 300, 1, 2, 0))
    writer.prr(2, not recovery, 2, retest=recovery)
    writer.prr(1, False, 2, retest=recovery)
    writer.summaries(2 if recovery else 1, retested=recovery)
    return writer.finish(2, 2 if recovery else 1, retested=recovery)


def optional_fixture() -> bytes:
    writer = Writer("<")
    writer.metadata(lot="BOUNDARY", wafer="BOUNDARY")
    writer.record(5, 10, bytes([1, 1]))
    # RESULT invalid, so this PTR may end before the absent R*4.
    writer.record(15, 10, writer.pack("IBBBB", 400, 1, 1, 0x02, 0))
    # Both zero MPR counts and all subsequent optional fields are omitted.
    writer.record(15, 15, writer.pack("IBBBB", 401, 1, 1, 0, 0))
    # Explicit RTN_ICNT=0, omitted zero RSLT_CNT tests the next boundary too.
    writer.record(15, 15, writer.pack("IBBBBH", 402, 1, 1, 0, 0, 0))
    writer.prr(1, False, 3)
    writer.record(1, 30, writer.pack("BBIIIII", 255, 255, 1, 0, 0, 1, MISSING_COUNT))
    return writer.finish(1, 1, wafer="BOUNDARY")


def walk_records(data: bytes) -> list[tuple[int, int, bytes]]:
    """Independent record-length oracle; no MoonSTDF/native parser needed."""
    if len(data) < 6 or data[2:4] != bytes([0, 10]) or data[5] != 4:
        raise ValueError("missing V4 FAR")
    endian = {1: ">", 2: "<"}[data[4]]
    out = []
    offset = 0
    while offset < len(data):
        if len(data) - offset < 4:
            raise ValueError(f"partial header at {offset}")
        length, typ, sub = struct.unpack_from(endian + "HBB", data, offset)
        end = offset + 4 + length
        if end > len(data):
            raise ValueError(f"partial body at {offset}")
        out.append((typ, sub, data[offset + 4:end]))
        offset = end
    return out


def inspect_fixture(data: bytes) -> dict:
    """Decode raw scalar values separately from Writer and check file invariants."""
    endian = "<" if data[4] == 2 else ">"
    records = walk_records(data)
    assert records[0] == (0, 10, bytes([data[4], 4]))
    assert records[1][:2] == (1, 10)
    assert records[-1][:2] == (1, 20)
    counts: dict[str, int] = {}
    parts = []
    ptr_values = []
    mpr_values = []
    mpr_states = []
    for typ, sub, body in records:
        key = f"{typ}/{sub}"
        counts[key] = counts.get(key, 0) + 1
        if (typ, sub) == (5, 20):
            head, site, flags, tests, hard, soft, x, y = struct.unpack_from(endian + "BBBHHHhh", body)
            parts.append({"head": head, "site": site, "x": x, "y": y,
                          "outcome": "unknown" if flags & 0x10 else "fail" if flags & 8 else "pass",
                          "hard_bin": hard, "soft_bin": soft, "test_count": tests})
        if (typ, sub) == (15, 10) and not body[6] & 0x10:
            if body[6] & 0x02 and len(body) == 8:
                continue
            ptr_values.append(struct.unpack_from(endian + "f", body, 8)[0])
        if (typ, sub) == (15, 15) and len(body) >= 12:
            states, values = struct.unpack_from(endian + "HH", body, 8)
            width = (states + 1) // 2
            mpr_states.extend((body[12 + i // 2] >> (4 * (i % 2))) & 15 for i in range(states))
            mpr_values.extend(struct.unpack_from(endian + "f" * values, body, 12 + width))
    passed = sum(p["outcome"] == "pass" for p in parts)
    failed = sum(p["outcome"] == "fail" for p in parts)
    return {"record_count": len(records), "records": counts, "parts": parts,
            "yield": {"total": len(parts), "passed": passed, "failed": failed,
                      "unknown": len(parts) - passed - failed, "abnormal": 0,
                      "denominator": passed + failed,
                      "yield": passed / (passed + failed) if passed + failed else None},
            "ptr_100_values_in_file_order": ptr_values,
            "mpr_200_states": mpr_states, "mpr_200_values": mpr_values}


def generate() -> tuple[dict[str, bytes], dict]:
    fixtures = {
        "lot-a-le.stdf": lot_fixture("<"),
        "lot-a-be.stdf": lot_fixture(">"),
        "lot-b-le.stdf": lot_fixture("<", shifted=True),
        "retest-le.stdf": lot_fixture("<", recovery=True),
        "optional-boundaries-le.stdf": optional_fixture(),
    }
    expected = {}
    for name, data in fixtures.items():
        result = inspect_fixture(data)
        result["sha256"] = hashlib.sha256(data).hexdigest()
        result["size_bytes"] = len(data)
        expected[name] = result
    assert expected["lot-a-le.stdf"]["yield"]["yield"] == 0.5
    assert expected["lot-a-be.stdf"]["yield"]["yield"] == 0.5
    assert expected["retest-le.stdf"]["yield"]["yield"] == 1.0
    for name, mean in [("lot-a-le.stdf", 2.5), ("lot-a-be.stdf", 2.5),
                       ("lot-b-le.stdf", 3.5), ("retest-le.stdf", 1.5)]:
        assert len(expected[name]["parts"]) == 2
        values = expected[name]["ptr_100_values_in_file_order"]
        assert sum(values) / len(values) == mean
        expected[name]["ptr_100_mean"] = mean
        expected[name]["mpr_200_mean"] = 2.25
    # MRR declares a four-byte body but its final byte is missing.
    fixtures["malformed-truncated.stdf"] = fixtures["lot-a-le.stdf"][:-1]
    try:
        walk_records(fixtures["malformed-truncated.stdf"])
    except ValueError:
        pass
    else:
        raise AssertionError("truncated fixture unexpectedly accepted")
    expected["malformed-truncated.stdf"] = {"expected_error": "truncated final MRR body"}
    return fixtures, expected


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify committed files without rewriting")
    args = parser.parse_args()
    fixtures, expected = generate()
    files = {name: data for name, data in fixtures.items()}
    files["expected.json"] = (json.dumps(expected, ensure_ascii=True, indent=2) + "\n").encode("utf-8")
    if args.check:
        for name, data in files.items():
            path = DESTINATION / name
            if not path.is_file() or path.read_bytes() != data:
                raise SystemExit(f"fixture differs: {path}")
        print(f"Checked {len(fixtures)} fixtures and expected.json")
    else:
        DESTINATION.mkdir(parents=True, exist_ok=True)
        for name, data in files.items():
            (DESTINATION / name).write_bytes(data)
        print(f"Generated {len(fixtures)} fixtures and expected.json")


if __name__ == "__main__":
    main()
