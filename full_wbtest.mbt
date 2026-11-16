///|
test "all 25 records accept minimal prefixes and reject required byte truncation" {
  let cases : Array[(Int32, Int32, Bytes)] = [
    (0, 10, b"\x02\x04"),
    (0, 20, b"\x00\x00\x00\x00\x00"),
    (
      1, 10, b"\x00\x00\x00\x00\x00\x00\x00\x00\x01P  \xff\xff \x01L\x01D\x01N\x01T\x01J",
    ),
    (1, 20, b"\x00\x00\x00\x00"),
    (1, 30, b"\x01\x01\x00\x00\x00\x00"),
    (1, 40, b"\x01\x01\x01\x00\x00\x00\x00\x00"),
    (1, 50, b"\x01\x01\x01\x00\x00\x00\x00\x00"),
    (1, 60, b"\x01\x00"),
    (1, 62, b"\x00\x80\x00\x00\x00"),
    (1, 63, b"\x01\x00\x01\x00"),
    (1, 70, b"\x00\x00"),
    (1, 80, b"\x01\x01\x00"),
    (2, 10, b"\x01\x01\x00\x00\x00\x00"),
    (2, 20, b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00"),
    (2, 30, b""),
    (5, 10, b"\x01\x01"),
    (5, 20, b"\x01\x01\x00\x00\x00\x01\x00"),
    (10, 30, b"\x01\x01P\x01\x00\x00\x00"),
    (15, 10, b"\x01\x00\x00\x00\x01\x01\x02\x00"),
    (15, 15, b"\x01\x00\x00\x00\x01\x01\x00\x00"),
    (15, 20, b"\x01\x00\x00\x00\x01\x01\x00"),
    (20, 10, b""),
    (20, 20, b""),
    (50, 10, b"\x00\x00"),
    (50, 30, b"\x00"),
  ]
  assert_eq(cases.length(), 25)
  for (typ, sub, body) in cases {
    assert_true(decode_v4_record(ancillary_frame(typ, sub, body)) is Some(_))
    for length in 0..<body.length() {
      assert_true(
        try {
          ignore(
            decode_v4_record(
              ancillary_frame(typ, sub, body[:length].to_owned()),
            ),
          )
          false
        } catch {
          _ => true
        },
      )
    }
  }
}

///|
test "complete record API retains fields outside the analysis projection" {
  let frame = ancillary_frame(1, 60, b"\x01\x00\x02\x00\x01c\x01p\x01l\x01\x02")
  let record = decode_v4_record(frame).unwrap()
  assert_eq(record.name, "PMR")
  assert_eq(record.frame, frame)
  assert_true(record.field("CHAN_TYP") is Some(UnsignedField(2U)))
  assert_true(record.field("LOG_NAM") is Some(TextField("l")))
  assert_true(record.field("NO_SUCH_FIELD") is None)
}

///|
test "complete record API distinguishes omitted fields from explicit zero" {
  let record = decode_v4_record(ancillary_frame(1, 60, b"\x01\x00")).unwrap()
  assert_true(record.field("CHAN_TYP") is Some(MissingField))
  let explicit = decode_v4_record(ancillary_frame(1, 60, b"\x01\x00\x00\x00")).unwrap()
  assert_true(explicit.field("CHAN_TYP") is Some(UnsignedField(0U)))
}

///|
test "complete record API decodes PLR U2 modes and generic R8 values" {
  let record = decode_v4_record(
    ancillary_frame(1, 63, b"\x01\x00\x01\x00\x01\x80"),
  ).unwrap()
  assert_true(
    record.field("GRP_MODE") is Some(ArrayField([UnsignedField(32769U)])),
  )
  let generic = decode_v4_record(
    ancillary_frame(50, 10, b"\x02\x00\x00\x08\x00\x00\x00\x00\x00\x00\xf0\x3f"),
  ).unwrap()
  assert_true(
    generic.field("GEN_DATA") is Some(GenericField([Padding, R8(1.0)])),
  )
}
