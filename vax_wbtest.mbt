///|
test "VAX FAR and integer representation are supported" {
  let frames = decode_frames(b"\x02\x00\x00\x0a\x00\x04")
  assert_eq(frames[0].order, Vax)
  assert_true(decode_metadata(frames[0]) is Some(Far(0, 4)))
  assert_eq(Reader::new(b"\x78\x56\x34\x12", Vax, 0).u4(), 0x12345678U)
}

///|
test "VAX D mantissa rounds once to nearest binary64" {
  assert_eq(
    Reader::new(b"\x40\x40\x00\x00\x00\x00\x05\x00", Vax, 0).r8(),
    0.7500000000000001,
  )
}

///|
test "VAX F and D floats decode known positive negative and zero values" {
  assert_eq(Reader::new(b"\x80\x40\x00\x00", Vax, 0).r4(), 1.0)
  assert_eq(Reader::new(b"\x00\xc1\x00\x00", Vax, 0).r4(), -2.0)
  assert_eq(Reader::new(b"\x20\x41\x00\x00", Vax, 0).r4(), 2.5)
  assert_eq(Reader::new(b"\x00\x00\x00\x00", Vax, 0).r4(), 0.0)
  assert_eq(Reader::new(b"\x80\x40\x00\x00\x00\x00\x00\x00", Vax, 0).r8(), 1.0)
  assert_eq(Reader::new(b"\x20\x41\x00\x00\x00\x00\x00\x00", Vax, 0).r8(), 2.5)
  assert_true(
    try {
      ignore(Reader::new(b"\x00\x80\x00\x00", Vax, 0).r4())
      false
    } catch {
      _ => true
    },
  )
}
