///|
fn ancillary_frame(typ : Int32, sub : Int32, body : Bytes) -> Frame {
  { offset: 0, typ, sub, order: Little, body, }
}

///|
test "ATR decodes modification time and command line" {
  assert_true(
    decode_ancillary(ancillary_frame(0, 20, b"\x01\x00\x00\x00\x01x"))
    is Some(Atr(_, "x")),
  )
}

///|
test "PMR decodes channel type, names and site" {
  assert_true(
    decode_ancillary(
      ancillary_frame(1, 60, b"\x01\x00\x02\x00\x01c\x01p\x01l\x01\x02"),
    )
    is Some(Pmr(1U, 2, "c", "p", "l", 1, 2)),
  )
}

///|
test "PGR decodes pin index array" {
  assert_true(
    decode_ancillary(ancillary_frame(1, 62, b"\x01\x00\x01g\x01\x00\x02\x00"))
    is Some(Pgr(1U, "g", [2])),
  )
}

///|
test "PLR mode is U2 and vendor mode high byte is retained" {
  assert_true(
    decode_ancillary(
      ancillary_frame(1, 63, b"\x01\x00\x01\x00\x01\x80\x10\x00\x00\x00\x00"),
    )
    is Some(Plr([1], [32769], [16], [[""], [""], [""], [""]])),
  )
}

///|
test "PMR and PLR accept omitted optional suffixes" {
  assert_true(
    decode_ancillary(ancillary_frame(1, 60, b"\x01\x00"))
    is Some(Pmr(1U, 0, "", "", "", 1, 1)),
  )
  assert_true(
    decode_ancillary(ancillary_frame(1, 63, b"\x01\x00\x01\x00"))
    is Some(Plr([1], [0], [0], [[""], [""], [""], [""]])),
  )
}

///|
test "RDR decodes retest bin list" {
  assert_true(
    decode_ancillary(ancillary_frame(1, 70, b"\x01\x00\x09\x00"))
    is Some(Rdr([9])),
  )
}

///|
test "BPS and EPS decode program boundaries" {
  assert_true(
    decode_ancillary(ancillary_frame(20, 10, b"\x01s")) is Some(Bps("s")),
  )
  assert_true(decode_ancillary(ancillary_frame(20, 20, b"")) is Some(Eps))
}

///|
test "DTR decodes text" {
  assert_true(
    decode_ancillary(ancillary_frame(50, 30, b"\x01x")) is Some(Dtr("x")),
  )
}

///|
test "GDR decodes generic data" {
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x01\x07"))
    is Some(Gdr([U1(7)])),
  )
}

///|
test "GDR checks variable values and required word alignment" {
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x0a\x02hi"))
    is Some(Gdr([Text("hi")])),
  )
  assert_true(
    try {
      ignore(
        decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x01\x02\x01\x00")),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x01\x0a\x04x")),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "GDR decodes each base V4 data type and byte order" {
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x00"))
    is Some(Gdr([Padding])),
  )
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x02\x00\x00\x02\x34\x12"))
    is Some(Gdr([Padding, U2(0x1234)])),
  )
  assert_true(
    decode_ancillary(
      ancillary_frame(50, 10, b"\x02\x00\x00\x03\x78\x56\x34\x12"),
    )
    is Some(Gdr([Padding, U4(0x12345678U)])),
  )
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x04\xff"))
    is Some(Gdr([I1(-1)])),
  )
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x02\x00\x00\x05\x00\x80"))
    is Some(Gdr([Padding, I2(-32768)])),
  )
  assert_true(
    decode_ancillary(
      ancillary_frame(50, 10, b"\x02\x00\x00\x06\x00\x00\x00\x80"),
    )
    is Some(Gdr([Padding, I4(-2147483648)])),
  )
  assert_true(
    decode_ancillary(
      ancillary_frame(50, 10, b"\x02\x00\x00\x07\x00\x00\x80\x3f"),
    )
    is Some(Gdr([Padding, R4(1.0)])),
  )
  assert_true(
    decode_ancillary(
      ancillary_frame(
        50, 10, b"\x02\x00\x00\x08\x00\x00\x00\x00\x00\x00\xf0\x3f",
      ),
    )
    is Some(Gdr([Padding, R8(_)])),
  )
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x0b\x02ab"))
    is Some(Gdr([Binary(b"ab")])),
  )
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x0c\x09\x00\xff\x01"))
    is Some(Gdr([Bits(9, b"\xff\x01")])),
  )
  assert_true(
    decode_ancillary(ancillary_frame(50, 10, b"\x01\x00\x0d\x0f"))
    is Some(Gdr([Nibble(15)])),
  )
  assert_true(
    decode_ancillary({
      offset: 0,
      typ: 50,
      sub: 10,
      order: Big,
      body: b"\x00\x02\x00\x02\x12\x34",
    })
    is Some(Gdr([Padding, U2(0x1234)])),
  )
}

///|
test "ancillary variable counts reject partial arrays and trailing bytes" {
  assert_true(
    try {
      ignore(
        decode_ancillary(
          ancillary_frame(1, 62, b"\x01\x00\x01g\x02\x00\x01\x00"),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_ancillary(ancillary_frame(1, 63, b"\x00\x00")))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_ancillary(ancillary_frame(1, 70, b"\x02\x00\x09\x00")))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_ancillary(ancillary_frame(20, 20, b"\x00")))
      false
    } catch {
      _ => true
    },
  )
}
