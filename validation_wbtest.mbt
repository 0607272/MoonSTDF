///|
fn validation_start(v : V4Validator) -> Unit raise StdfError {
  v.accept(assembly_frame(0, 10, b"\x02\x04"))
  v.accept(
    assembly_frame(
      1, 10, b"\x00\x00\x00\x00\x00\x00\x00\x00\x01P  \xff\xff \x01L\x01D\x01N\x01T\x01J",
    ),
  )
}

///|
fn validation_end(v : V4Validator) -> ValidationReport raise StdfError {
  v.accept(assembly_frame(1, 30, b"\xff\xff\x00\x00\x00\x00"))
  v.accept(assembly_frame(1, 20, b"\x00\x00\x00\x00"))
  v.finish()
}

///|
test "legal empty BPS and missing section name decode without invented text" {
  let frame = assembly_frame(20, 10, b"")
  assert_true(
    decode_v4_record(frame).unwrap().field("SEQ_NAME") is Some(MissingField),
  )
  assert_true(decode_ancillary(frame) is Some(Bps("")))
}

///|
test "validator detects orphan tests parts and mismatched wafer groups" {
  let v = V4Validator::new()
  validation_start(v)
  v.accept(assembly_frame(15, 20, b"\x01\x00\x00\x00\x01\x01\x00"))
  v.accept(assembly_frame(5, 20, b"\x01\x01\x00\x01\x00\x01\x00"))
  v.accept(assembly_frame(2, 10, b"\x01\x07\x00\x00\x00\x00"))
  v.accept(assembly_frame(2, 20, b"\x01\x08\x00\x00\x00\x00\x00\x00\x00\x00"))
  v.accept(assembly_frame(5, 10, b"\x01\x02"))
  let report = validation_end(v)
  for
    code in [
      "orphan-test", "orphan-part-end", "orphan-wafer-end", "unfinished-part", "unfinished-wafer",
    ] {
    assert_true(report.diagnostics.any(fn(d) { d.code == code }))
  }
}

///|
test "validator accepts required records and rejects missing PCR" {
  let valid = V4Validator::new()
  validation_start(valid)
  assert_true(validation_end(valid).valid)
  let missing = V4Validator::new()
  validation_start(missing)
  missing.accept(assembly_frame(1, 20, b"\x00\x00\x00\x00"))
  let report = missing.finish()
  assert_true(!report.valid)
  assert_true(report.diagnostics.any(fn(d) { d.code == "missing-pcr" }))
}

///|
test "validator diagnoses initial sequence and post MRR records" {
  let v = V4Validator::new()
  validation_start(v)
  v.accept(assembly_frame(0, 20, b"\x00\x00\x00\x00\x00"))
  v.accept(assembly_frame(50, 30, b"\x00"))
  v.accept(assembly_frame(1, 70, b"\x00\x00"))
  v.accept(assembly_frame(1, 80, b"\x01\x01\x00"))
  v.accept(assembly_frame(1, 30, b"\xff\xff\x00\x00\x00\x00"))
  v.accept(assembly_frame(1, 20, b"\x00\x00\x00\x00"))
  v.accept(assembly_frame(50, 30, b"\x00"))
  let report = v.finish()
  for code in ["atr-order", "rdr-order", "sdr-order", "after-mrr"] {
    assert_true(report.diagnostics.any(fn(d) { d.code == code }))
  }
}

///|
test "validator resolves pin groups and balances nested program sections" {
  let v = V4Validator::new()
  validation_start(v)
  v.accept(assembly_frame(1, 60, b"\x01\x00"))
  v.accept(assembly_frame(1, 62, b"\x00\x80\x01g\x01\x00\x01\x00"))
  v.accept(assembly_frame(1, 63, b"\x01\x00\x00\x80"))
  v.accept(assembly_frame(5, 10, b"\x01\x01"))
  v.accept(assembly_frame(20, 10, b"\x01a"))
  v.accept(assembly_frame(20, 10, b"\x01b"))
  v.accept(assembly_frame(20, 20, b""))
  v.accept(assembly_frame(20, 20, b""))
  v.accept(assembly_frame(5, 20, b"\x01\x01\x00\x00\x00\x01\x00"))
  assert_true(validation_end(v).valid)
  let bad = V4Validator::new()
  validation_start(bad)
  bad.accept(assembly_frame(1, 62, b"\x00\x80\x01g\x01\x00\x09\x00"))
  bad.accept(assembly_frame(20, 20, b""))
  bad.accept(assembly_frame(20, 10, b"\x01a"))
  let report = validation_end(bad)
  for code in ["undefined-pin", "orphan-eps", "unfinished-section"] {
    assert_true(report.diagnostics.any(fn(d) { d.code == code }))
  }
}

///|
test "validator checks reserved parametric flags and section part context" {
  let v = V4Validator::new()
  validation_start(v)
  v.accept(
    assembly_frame(
      15, 10, b"\x01\x00\x00\x00\x01\x01\x10\x00\x00\x00\x00\x00\x00\x00\x00",
    ),
  )
  v.accept(assembly_frame(15, 15, b"\x01\x00\x00\x00\x01\x01\x12\x00"))
  v.accept(assembly_frame(20, 10, b""))
  v.accept(assembly_frame(20, 20, b""))
  let report = validation_end(v)
  for code in ["ptr-opt-flag", "test-flag-reserved", "section-outside-part"] {
    assert_true(report.diagnostics.any(fn(d) { d.code == code }))
  }
}
