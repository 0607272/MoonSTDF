///|
fn metadata_frame(typ : Int32, sub : Int32, body : Bytes) -> Frame {
  { typ, sub, body, offset: 100, order: Little, }
}

///|
test "MIR decodes required identity and rejects missing required job field" {
  let prefix = b"\x01\x00\x00\x00\x02\x00\x00\x00\x01P  \xff\xff "
  let record = decode_metadata(
    metadata_frame(1, 10, prefix + b"\x03LOT\x03DUT\x01N\x01T\x03JOB"),
  )
  guard record is Some(Mir(lot)) else { abort("expected MIR") }
  assert_eq(lot.lot, "LOT")
  assert_eq(lot.job, "JOB")
  assert_eq(lot.start, 2U)
  assert_true(
    try {
      ignore(decode_metadata(metadata_frame(1, 10, prefix + b"\x03LOT")))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "SDR maps group membership and wafer records retain group not site" {
  assert_true(
    decode_metadata(metadata_frame(1, 80, b"\x01\x07\x02\x01\x02"))
    is Some(Sdr(1, 7, [1, 2])),
  )
  assert_true(
    decode_metadata(metadata_frame(2, 10, b"\x01\x07\x00\x00\x00\x00\x02W1"))
    is Some(Wir(1, 7, 0U, "W1")),
  )
  assert_true(
    try {
      ignore(decode_metadata(metadata_frame(1, 80, b"\x01\x07\x03\x01\x02")))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "optional wafer geometry is missing not numeric zero and partial fields fail" {
  guard decode_metadata(metadata_frame(2, 30, b"")) is Some(Wcr(g)) else {
    abort("expected WCR")
  }
  assert_eq(g.diameter, None)
  assert_eq(g.center_x, None)
  assert_true(
    try {
      ignore(decode_metadata(metadata_frame(2, 30, b"\x00\x00")))
      false
    } catch {
      _ => true
    },
  )
  assert_true(decode_metadata(metadata_frame(200, 1, b"abc")) is None)
}
