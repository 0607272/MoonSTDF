///|
fn param_frame(body : Bytes, sub : Int32, order : ByteOrder) -> Frame {
  { offset: 100, typ: 15, sub, order, body, }
}

///|
test "PTR reads raw IEEE result in both byte orders and retains absent defaults" {
  let little = decode_parametric(
    param_frame(b"\x78\x56\x34\x12\x01\x02\x80\x40\x00\x00\xc0\x3f", 10, Little),
  ).unwrap()
  assert_eq(little.number, 305419896U)
  assert_eq(little.kind, "PTR")
  assert_eq(little.head, 1)
  assert_eq(little.site, 2)
  assert_eq(little.flags, 128)
  assert_eq(little.param_flags, 64)
  assert_eq(little.values[0], 1.5)
  assert_eq(little.defaults.flags, None)
  assert_eq(little.defaults.res_scale, None)
  assert_eq(little.defaults.low, None)
  assert_eq(little.defaults.units, None)
  let big = decode_parametric(
    param_frame(b"\x12\x34\x56\x78\x01\x02\x00\x00\xbf\xc0\x00\x00", 10, Big),
  ).unwrap()
  assert_eq(big.number, 305419896U)
  assert_eq(big.values[0], -1.5)
}

///|
test "PTR display exponents do not alter raw result or limits" {
  let body = b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\xc0\x3f\x03Vdd\x00\x02\xfd\xfa\x03\x00\x00\x80\x3f\x00\x00\x00\x40\x01V\x00\x00\x00\x00\x00\x00\x3f\x00\x00\x40\x40"
  let record = decode_parametric(param_frame(body, 10, Little)).unwrap()
  assert_eq(record.text, "Vdd")
  assert_eq(record.values[0], 1.5)
  assert_eq(record.defaults.flags, Some(2))
  assert_eq(record.defaults.res_scale, Some(-3))
  assert_eq(record.defaults.low_scale, Some(-6))
  assert_eq(record.defaults.high_scale, Some(3))
  assert_eq(record.defaults.low, Some(1.0))
  assert_eq(record.defaults.high, Some(2.0))
  assert_eq(record.defaults.units, Some("V"))
}

///|
test "PTR distinguishes omitted numeric tail from partial primitive and string" {
  let prefix = b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\x80\x3f\x00\x00\x02\x00\x00\x00"
  let record = decode_parametric(param_frame(prefix, 10, Little)).unwrap()
  assert_eq(record.defaults.low, None)
  assert_true(
    try {
      ignore(decode_parametric(param_frame(prefix + b"\x00", 10, Little)))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        decode_parametric(
          param_frame(
            b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\x80\x3f\x03a",
            10,
            Little,
          ),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "PTR rejects partial specification limits even after unused formatting fields" {
  let prefix = b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\x80\x3f\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  ignore(decode_parametric(param_frame(prefix, 10, Little)))
  assert_true(
    try {
      ignore(decode_parametric(param_frame(prefix + b"\x00\x00", 10, Little)))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "MPR decodes low nibble first with odd count and separate result count" {
  let record = decode_parametric(
    param_frame(
      b"\x02\x00\x00\x00\x01\x03\x00\x00\x03\x00\x02\x00\x21\x03\x00\x00\xc0\x3f\x00\x00\x20\xc0",
      15,
      Little,
    ),
  ).unwrap()
  assert_eq(record.kind, "MPR")
  assert_eq(record.states, [1, 2, 3])
  assert_eq(record.values.length(), 2)
  assert_eq(record.values[0], 1.5)
  assert_eq(record.values[1], -2.5)
  assert_eq(record.indexes.length(), 0)
  assert_eq(record.defaults.flags, None)
}

///|
test "MPR reads big endian indexes after input conditions" {
  let body = b"\x12\x34\x56\x78\x01\x02\x00\x00\x00\x02\x00\x01\x21\x3f\xc0\x00\x00\x01T\x00\x00\xfd\x00\x00\x3f\x80\x00\x00\x40\x00\x00\x00\x00\x00\x00\x00\x3f\x80\x00\x00\x01\x02\x03\x04\x01V\x01s\x00\x00\x00\x3f\x00\x00\x00\x40\x40\x00\x00"
  let record = decode_parametric(param_frame(body, 15, Big)).unwrap()
  assert_eq(record.number, 305419896U)
  assert_eq(record.states, [1, 2])
  assert_eq(record.indexes, [258, 772])
  assert_eq(record.values[0], 1.5)
  assert_eq(record.defaults.res_scale, Some(-3))
  assert_eq(record.defaults.low, Some(1.0))
  assert_eq(record.defaults.high, Some(2.0))
  assert_eq(record.defaults.units, Some("V"))
}

///|
test "MPR rejects impossible counts partial results and partial optional index arrays" {
  for
    body in [
      b"\x01\x00\x00\x00\x01\x01\x00\x00\xff\xff\x00\x00", b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\xff\xff",
      b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\x01\x00\x00\x00\x80",
    ] {
    assert_true(
      try {
        ignore(decode_parametric(param_frame(body, 15, Little)))
        false
      } catch {
        _ => true
      },
    )
  }
  // One returned state, no results, blank text/alarm, four metadata bytes,
  // and four complete R*4 limit/input fields. The optional index needs U*2.
  let before_index = b"\x01\x00\x00\x00\x01\x01\x00\x00\x01\x00\x00\x00\x01" +
    b"\x00\x00\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  ignore(decode_parametric(param_frame(before_index, 15, Little)))
  assert_true(
    try {
      ignore(decode_parametric(param_frame(before_index + b"\x34", 15, Little)))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "parametric raw nonfinite results remain available for validity policy" {
  let record = decode_parametric(
    param_frame(b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\xc0\x7f", 10, Little),
  ).unwrap()
  assert_true(record.values[0].is_nan())
  let infinity = decode_parametric(
    param_frame(b"\x01\x00\x00\x00\x01\x01\x00\x00\x00\x00\x80\x7f", 10, Little),
  ).unwrap()
  assert_true(infinity.values[0].is_inf())
}

///|
test "parametric dispatch ignores other records and rejects missing mandatory data" {
  assert_true(decode_parametric(param_frame(b"", 20, Little)) is None)
  for sub in [10, 15] {
    assert_true(
      try {
        ignore(decode_parametric(param_frame(b"\x01", sub, Little)))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "MPR rejects nonzero padding in an odd returned state array" {
  assert_true(
    try {
      ignore(
        decode_parametric(
          param_frame(
            b"\x01\x00\x00\x00\x01\x01\x00\x00\x01\x00\x00\x00\xf1",
            15,
            Little,
          ),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}
