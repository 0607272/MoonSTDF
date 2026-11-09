///|
fn part_frame(sub : Int32, body : Bytes, order : ByteOrder) -> Frame {
  { offset: 100, typ: 5, sub, body, order, }
}

///|
fn part_result(body : Bytes, order : ByteOrder) -> PartResult raise StdfError {
  match decode_part(part_frame(20, body, order)) {
    Some(Prr(result)) => result
    _ => abort("expected PRR")
  }
}

///|
fn part_rejected(body : Bytes) -> Bool {
  try {
    ignore(part_result(body, Little))
    false
  } catch {
    _ => true
  }
}

///|
test "PIR identifies head and site and requires exactly two bytes" {
  assert_eq(decode_part(part_frame(10, b"\x02\x07", Big)), Some(Pir(2, 7)))
  for body in [b"", b"\x01", b"\x01\x02\x03"] {
    assert_true(
      try {
        ignore(decode_part(part_frame(10, body, Little)))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(decode_part(part_frame(99, b"", Little)), None)
  let unknown = { offset: 0, typ: 99, sub: 20, body: b"", order: Little, }
  assert_eq(decode_part(unknown), None)
}

///|
test "PRR literal little endian fields retain identifiers and opaque repair bytes" {
  let frame = part_frame(
    20,
    b"\x02\x07\x08\x34\x12\x78\x56\x09\x00\xfe\xff\x03\x00\x04\x03\x02\x01\x02AB\x03CDE\x02\xaa\xbb",
    Little,
  )
  let before = frame.body
  let p = match decode_part(frame) {
    Some(Prr(p)) => p
    _ => abort("expected PRR")
  }
  assert_eq(p.head, 2)
  assert_eq(p.site, 7)
  assert_eq(p.flags, 8)
  assert_eq(p.num_tests, 4660)
  assert_eq(p.hard_bin, 22136)
  assert_eq(p.soft_bin, Some(9))
  assert_eq(p.x, Some(-2))
  assert_eq(p.y, Some(3))
  assert_eq(p.test_ms, 16909060U)
  assert_eq(p.part_id, "AB")
  assert_eq(p.part_text, "CDE")
  assert_eq(p.outcome, Fail)
  assert_eq(p.abnormal, false)
  assert_eq(frame.body, before)
}

///|
test "PRR literal big endian fields and uint32 test time" {
  let p = part_result(
    b"\x03\x04\x00\x12\x34\x56\x78\x00\x09\xff\xfe\x00\x03\xff\xff\xff\xff\x01Z",
    Big,
  )
  assert_eq(p.num_tests, 4660)
  assert_eq(p.hard_bin, 22136)
  assert_eq(p.soft_bin, Some(9))
  assert_eq(p.x, Some(-2))
  assert_eq(p.y, Some(3))
  assert_eq(p.test_ms, 4294967295U)
  assert_eq(p.part_id, "Z")
  assert_eq(p.part_text, "")
  assert_eq(p.outcome, Pass)
}

///|
test "PRR missing suffix and explicit sentinels remain missing" {
  let minimal = part_result(b"\x01\x02\x00\x00\x00\x00\x00", Little)
  assert_eq(minimal.soft_bin, None)
  assert_eq(minimal.x, None)
  assert_eq(minimal.y, None)
  assert_eq(minimal.test_ms, 0U)
  assert_eq(minimal.part_id, "")
  assert_eq(minimal.part_text, "")
  let sentinel = part_result(
    b"\x01\x02\x00\x00\x00\x00\x00\xff\xff\x00\x80\x00\x80\x00\x00\x00\x00\x00\x00\x00",
    Little,
  )
  assert_eq(sentinel, minimal)
  let zero = part_result(
    b"\x01\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    Little,
  )
  assert_eq(zero.soft_bin, Some(0))
  assert_eq(zero.x, Some(0))
  assert_eq(zero.y, Some(0))
}

///|
test "PRR accepts only whole optional scalar string and repair fields" {
  let body = b"\x02\x07\x08\x34\x12\x78\x56\x09\x00\xfe\xff\x03\x00\x04\x03\x02\x01\x02AB\x03CDE\x02\xaa\xbb"
  for n in 0..<=body.length() {
    let whole = [7, 9, 11, 13, 17, 20, 24, 27].contains(n)
    assert_eq(part_rejected(body[:n].to_owned()), !whole)
  }
  assert_true(part_rejected(body + b"\x00"))
}

///|
test "PRR outcome follows validity and failure while abnormal stays independent" {
  for
    (flag, expected, abnormal) in [
      (b"\x00", Pass, false),
      (b"\x01", Pass, false),
      (b"\x02", Pass, false),
      (b"\x08", Fail, false),
      (b"\x10", Unknown, false),
      (b"\x18", Unknown, false),
      (b"\x04", Pass, true),
      (b"\x0c", Fail, true),
      (b"\x14", Unknown, true),
    ] {
    let p = part_result(b"\x01\x02" + flag + b"\x00\x00\x00\x00", Little)
    assert_eq(p.outcome, expected)
    assert_eq(p.abnormal, abnormal)
  }
}

///|
test "PRR rejects conflicting supersession and reserved flags at absolute offset" {
  for flag in [b"\x03", b"\x20", b"\x40", b"\x80"] {
    let offset = try {
      ignore(part_result(b"\x01\x02" + flag + b"\x00\x00\x00\x00", Little))
      -1
    } catch {
      StdfError(offset, _) => offset
    }
    assert_eq(offset, 106)
  }
}
