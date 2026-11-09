///|
fn assembly_frame(
  typ : Int32,
  sub : Int32,
  body : Bytes,
  offset~ : Int32 = 0,
) -> Frame {
  { typ, sub, body, offset, order: Little, }
}

///|
fn assembly_lot(a : Analyzer) -> Unit raise StdfError {
  a.accept(assembly_frame(0, 10, b"\x02\x04"))
  a.accept(
    assembly_frame(
      1, 10, b"\x00\x00\x00\x00\x00\x00\x00\x00\x01P  \xff\xff \x01L\x01D\x01N\x01T\x01J",
    ),
  )
}

///|
test "interleaved sites retain own tests and resolve SDR wafer group" {
  let a = Analyzer::new()
  assembly_lot(a)
  a.accept(assembly_frame(1, 80, b"\x01\x07\x02\x01\x02"))
  a.accept(assembly_frame(2, 10, b"\x01\x07\x00\x00\x00\x00\x02W1"))
  a.accept(assembly_frame(5, 10, b"\x01\x01"))
  a.accept(assembly_frame(5, 10, b"\x01\x02"))
  a.accept(
    assembly_frame(
      15,
      10,
      b"\x07\x00\x00\x00\x01\x02\x00\x00\x00\x00\x00\x40",
      offset=70,
    ),
  )
  a.accept(
    assembly_frame(
      15,
      10,
      b"\x07\x00\x00\x00\x01\x01\x80\x00\x00\x00\x80\x3f",
      offset=86,
    ),
  )
  a.accept(assembly_frame(5, 20, b"\x01\x01\x08\x01\x00\x02\x00", offset=100))
  a.accept(assembly_frame(5, 20, b"\x01\x02\x00\x01\x00\x01\x00", offset=111))
  let report = a.finish()
  assert_eq(report.parts.length(), 2)
  assert_eq(report.parts[0].wafer, Some("W1"))
  assert_eq(report.parts[0].tests[0].values, [1.0])
  assert_eq(report.parts[0].tests[0].offset, 86)
  assert_eq(report.parts[1].tests[0].values, [2.0])
}

///|
test "PTR first defaults remain baseline across sites and overrides are local" {
  let a = Analyzer::new()
  assembly_lot(a)
  // default-only: raw low1 high3 UNITS V, display exponents 6,-3,2.
  let base = b"\x07\x00\x00\x00\x01\x01\x10\x00\x00\x00\x00\x00\x00\x00\x02\x06\xfd\x02\x00\x00\x80\x3f\x00\x00\x40\x40\x01V"
  a.accept(assembly_frame(15, 10, base))
  a.accept(assembly_frame(5, 10, b"\x01\x02"))
  a.accept(
    assembly_frame(
      15, 10, b"\x07\x00\x00\x00\x01\x02\x00\x00\x00\x00\x00\x40\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80\x40\x01A",
    ),
  )
  a.accept(
    assembly_frame(15, 10, b"\x07\x00\x00\x00\x01\x02\x00\x00\x00\x00\x00\x40"),
  )
  a.accept(assembly_frame(5, 20, b"\x01\x02\x00\x02\x00\x01\x00"))
  let p = a.finish().parts[0]
  assert_eq(p.tests.length(), 2)
  assert_eq(p.tests[0].units, Some("A"))
  assert_eq(p.tests[1].units, Some("V"))
  assert_eq(p.tests[1].low, Some(1.0))
  assert_eq(p.tests[1].values, [2.0]) // display scale never changes base values
}

///|
test "unmatched test and unfinished part produce diagnostics" {
  let a = Analyzer::new()
  assembly_lot(a)
  a.accept(
    assembly_frame(15, 10, b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\x80\x3f"),
  )
  a.accept(assembly_frame(5, 10, b"\x01\x01"))
  a.accept(assembly_frame(200, 1, b"opaque"))
  let r = a.finish()
  assert_eq(r.parts.length(), 0)
  assert_eq(r.unknown.length(), 1)
  assert_true(r.diagnostics.any(fn(d) { d.code == "orphan-test" }))
  assert_true(r.diagnostics.any(fn(d) { d.code == "unfinished-part" }))
}

///|
test "no-limit flag removes inherited bound and NUL units clears baseline" {
  let a = Analyzer::new()
  assembly_lot(a)
  a.accept(
    assembly_frame(
      15, 10, b"\x07\x00\x00\x00\x01\x01\x10\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x80\x3f\x00\x00\x40\x40\x01V",
    ),
  )
  a.accept(assembly_frame(5, 10, b"\x01\x01"))
  a.accept(
    assembly_frame(
      15, 10, b"\x07\x00\x00\x00\x01\x01\x00\x00\x00\x00\x00\x40\x00\x00\x42\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80\x40\x01\x00",
    ),
  )
  a.accept(assembly_frame(5, 20, b"\x01\x01\x00\x01\x00\x01\x00"))
  let m = a.finish().parts[0].tests[0]
  assert_eq(m.low, None)
  assert_eq(m.units, None)
  assert_eq(m.high, Some(4.0))
}

///|
test "concurrent wafer groups with no SDR never silently match" {
  let a = Analyzer::new()
  assembly_lot(a)
  a.accept(assembly_frame(2, 10, b"\x01\x07\x00\x00\x00\x00\x02W1"))
  a.accept(assembly_frame(2, 10, b"\x01\x08\x00\x00\x00\x00\x02W2"))
  a.accept(assembly_frame(5, 10, b"\x01\x01"))
  a.accept(assembly_frame(5, 20, b"\x01\x01\x00\x00\x00\x01\x00"))
  let r = a.finish()
  assert_eq(r.parts[0].wafer, None)
  assert_true(r.diagnostics.any(fn(d) { d.code == "ambiguous-wafer" }))
  assert_true(
    try {
      ignore(a.finish())
      false
    } catch {
      _ => true
    },
  )
}
