///|
test "public frame analyzer enforces budgets without relying on file framer" {
  let a = Analyzer::new(max_records=1)
  a.accept({ offset: 0, typ: 0, sub: 10, order: Little, body: b"\x02\x04", })
  assert_true(
    try {
      a.accept({ offset: 6, typ: 200, sub: 1, order: Little, body: b"", })
      false
    } catch {
      _ => true
    },
  )
  let b = Analyzer::new(max_bytes=5)
  assert_true(
    try {
      b.accept({ offset: 0, typ: 0, sub: 10, order: Little, body: b"\x02\x04", })
      false
    } catch {
      _ => true
    },
  )
  let c = Analyzer::new()
  assert_true(
    try {
      c.accept({
        offset: 0,
        typ: 1,
        sub: 20,
        order: Little,
        body: b"\x00\x00\x00\x00",
      })
      false
    } catch {
      _ => true
    },
  )
}

///|
test "public projections reject invalid FAR and oversized record bodies" {
  assert_true(
    try {
      ignore(
        decode_metadata({
          offset: 0,
          typ: 0,
          sub: 10,
          order: Little,
          body: b"\x02\x03",
        }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        decode_metadata({
          offset: 0,
          typ: 0,
          sub: 10,
          order: Big,
          body: b"\x02\x04",
        }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        decode_functional({
          offset: 0,
          typ: 15,
          sub: 20,
          order: Little,
          body: Bytes::new(65536),
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "JSON option fields are scalar or null not constructor arrays" {
  let a : Analysis = {
    parts: [report_part("A")],
    diagnostics: [],
    summaries: [],
    unknown: [],
    record_count: 1,
  }
  let parsed = @json.parse(report_json(a))
  guard parsed is { "parts": Json::Array(parts), .. } else { abort("parts") }
  assert_true(
    parts[0]
    is {
      "wafer": Json::String("W"),
      "x": Json::Number(-1.0, ..),
      "soft_bin": Json::Null,
      ..
    },
  )
}
