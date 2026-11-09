///|
fn summary_frame(
  typ : Int32,
  sub : Int32,
  body : Bytes,
  order : ByteOrder,
) -> Frame {
  { offset: 50, typ, sub, body, order, }
}

///|
fn summary_record(
  typ : Int32,
  sub : Int32,
  body : Bytes,
  order : ByteOrder,
) -> Summary raise StdfError {
  decode_summary(summary_frame(typ, sub, body, order)).unwrap()
}

///|
fn functional_record(
  body : Bytes,
  order : ByteOrder,
) -> TestRecord raise StdfError {
  decode_functional(summary_frame(15, 20, body, order)).unwrap()
}

///|
fn functional_rejected(body : Bytes) -> Bool {
  try {
    ignore(functional_record(body, Little))
    false
  } catch {
    _ => true
  }
}

///|
test "PCR required total and optional good count preserve sentinel absence" {
  let p = summary_record(1, 30, b"\xff\x01\x04\x03\x02\x01", Little)
  assert_eq(p.kind, "PCR")
  assert_eq(p.head, 255)
  assert_eq(p.site, 1)
  assert_eq(p.count, Some(16909060U))
  assert_eq(p.good, None)
  assert_eq(p.fails, None)
  assert_eq(p.number, None)
  let p = summary_record(
    1,
    30,
    b"\x01\x02\x00\x00\x00\x05\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff\xff\xff\xff\xff\xff",
    Big,
  )
  assert_eq(p.count, Some(5U))
  assert_eq(p.good, None)
  let p = summary_record(
    1,
    30,
    b"\x01\x02\x05\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    Little,
  )
  assert_eq(p.good, Some(0U))
}

///|
test "HBR and SBR project explicit bin pass fail and names" {
  let p = summary_record(
    1,
    40,
    b"\x01\x02\x34\x12\x04\x03\x02\x01P\x04GOOD",
    Little,
  )
  assert_eq(p.kind, "HBR")
  assert_eq(p.number, Some(4660U))
  assert_eq(p.count, Some(16909060U))
  assert_eq(p.good, p.count)
  assert_eq(p.fails, None)
  assert_eq(p.label, "GOOD")
  let f = summary_record(
    1,
    50,
    b"\x03\x04\x12\x34\x01\x02\x03\x04F\x03BAD",
    Big,
  )
  assert_eq(f.kind, "SBR")
  assert_eq(f.number, Some(4660U))
  assert_eq(f.fails, Some(16909060U))
  assert_eq(f.good, None)
  let unknown = summary_record(
    1,
    40,
    b"\x01\x02\x00\x00\x00\x00\x00\x00",
    Little,
  )
  assert_eq(unknown.good, None)
  assert_eq(unknown.fails, None)
  assert_eq(unknown.label, "")
}

///|
test "TSR required identity optional counts and name label projection" {
  let p = summary_record(10, 30, b"\x01\x02P\x78\x56\x34\x12", Little)
  assert_eq(p.kind, "TSR")
  assert_eq(p.number, Some(305419896U))
  assert_eq(p.count, None)
  let p = summary_record(
    10,
    30,
    b"\x01\x02F\x12\x34\x56\x78\x00\x00\x00\x09\x00\x00\x00\x02\xff\xff\xff\xff\x04NAME\x03SEQ\x03LBL\xc8\x3f\x80\x00\x00\x00\x00\x00\x00\x3f\x80\x00\x00\x40\x00\x00\x00\x40\x40\x00\x00",
    Big,
  )
  assert_eq(p.count, Some(9U))
  assert_eq(p.fails, Some(2U))
  assert_eq(p.label, "NAME")
  assert_eq(p.good, None)
}

///|
test "TSR sentinels and all optional real boundaries retain missing counters" {
  let full = b"\x01\x02P\x01\x00\x00\x00" +
    b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" +
    b"\x00\x00\x00\xc8" +
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let p = summary_record(10, 30, full, Little)
  assert_eq(p.count, None)
  assert_eq(p.fails, None)
  for n in 0..<=full.length() {
    let rejected = try {
      ignore(summary_record(10, 30, full[:n].to_owned(), Little))
      false
    } catch {
      _ => true
    }
    assert_eq(
      rejected,
      ![7, 11, 15, 19, 20, 21, 22, 23, 27, 31, 35, 39, 43].contains(n),
    )
  }
  for flag in [b"\x88", b"\x48", b"\xc0"] {
    assert_true(
      try {
        ignore(summary_record(10, 30, full[:22].to_owned() + flag, Little))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(summary_record(10, 30, full + b"\x00", Little))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "summary records reject partial scalar string real and extra payloads" {
  let pcr = b"\x01\x02\x05\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  for n in 0..<=pcr.length() {
    let rejected = try {
      ignore(summary_record(1, 30, pcr[:n].to_owned(), Little))
      false
    } catch {
      _ => true
    }
    assert_eq(rejected, ![6, 10, 14, 18, 22].contains(n))
  }
  for
    (typ, sub, body) in [
      (1, 40, b"\x01\x02\x00\x00\x00\x00\x00\x00P\x03A"),
      (1, 50, b"\x01\x02\x00\x00\x00\x00\x00"),
      (10, 30, b"\x01\x02P\x01\x00\x00"),
      (10, 30, b"\x01\x02P\x01\x00\x00\x00\x00"),
      (
        10, 30, b"\x01\x02P\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xc8\x00",
      ),
    ] {
    assert_true(
      try {
        ignore(summary_record(typ, sub, body, Little))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(decode_summary(summary_frame(99, 30, b"", Little)), None)
}

///|
test "minimal FTR is seven bytes and has no invented measurement or defaults" {
  let p = functional_record(b"\x78\x56\x34\x12\x01\x02\x80", Little)
  assert_eq(p.kind, "FTR")
  assert_eq(p.number, 305419896U)
  assert_eq(p.head, 1)
  assert_eq(p.site, 2)
  assert_eq(p.flags, 128)
  assert_eq(p.param_flags, 0)
  assert_eq(p.values, [])
  assert_eq(p.states, [])
  assert_eq(p.indexes, [])
  assert_eq(p.text, "")
  assert_eq(p.defaults.flags, None)
  assert_eq(p.defaults.low, None)
  assert_true(functional_rejected(b"\x78\x56\x34\x12\x01\x02"))
  let big = functional_record(b"\x12\x34\x56\x78\x03\x04\x00", Big)
  assert_eq(big.number, 305419896U)
  assert_true(decode_functional(summary_frame(15, 10, b"", Little)) is None)
}

///|
fn functional_full() -> Bytes {
  b"\x78\x56\x34\x12\x01\x02\x80\xc0" +
  b"\x01\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff\xff\xff\x05\x00\x00\x00\xfe\xff" +
  b"\x03\x00\x01\x00\x01\x00\x02\x00\x03\x00\x21\x03\x04\x00\x05\x09\x00\x01\x01" +
  b"\x01V\x01T\x01O\x03TXT\x01A\x01P\x01R\x02\x09\x00\x01\x01"
}

///|
test "full FTR validates nibbles bit-count arrays and projects returned pins and test text" {
  let frame = summary_frame(15, 20, functional_full(), Little)
  let p = decode_functional(frame).unwrap()
  assert_eq(p.states, [1, 2, 3])
  assert_eq(p.indexes, [1, 2, 3])
  assert_eq(p.text, "TXT")
  assert_eq(p.values, [])
  assert_eq(frame.body, functional_full())
}

///|
test "FTR validates every optional boundary instead of consuming partial tails" {
  let full = functional_full()
  for n in 0..<=full.length() {
    let whole = [
      7, 8, 12, 16, 20, 24, 28, 32, 34, 49, 53, 55, 57, 59, 63, 65, 67, 69, 70, 74,
    ].contains(n)
    assert_eq(functional_rejected(full[:n].to_owned()), !whole)
  }
  assert_true(functional_rejected(full + b"\x00"))
  assert_true(functional_rejected(b"\x01\x00\x00\x00\x01\x02\x02"))
  assert_true(functional_rejected(b"\x01\x00\x00\x00\x01\x02\x00\x80"))
}

///|
test "FTR rejects nonzero padding nibbles and bitmap bits" {
  let full = functional_full()
  for
    (pos, value) in [(45, b"\x13"), (48, b"\x15"), (52, b"\x81"), (73, b"\x81")] {
    let bad = full[:pos].to_owned() + value + full[pos + 1:].to_owned()
    assert_true(functional_rejected(bad))
  }
}
