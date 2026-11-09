///|
test "FAR determines byte order and unknown records retain offset and bytes" {
  let frames = decode_frames(b"\x02\x00\x00\x0a\x02\x04\x03\x00\xc8\x01abc")
  assert_eq(frames.length(), 2)
  assert_eq(frames[1].offset, 6)
  assert_eq(frames[1].body, b"abc")
  assert_eq(frames[1].order, Little)
  let big = decode_frames(b"\x00\x02\x00\x0a\x01\x04\x00\x00\x05\x0a")
  assert_eq(big[1].order, Big)
}

///|
test "incremental framing is independent of every chunk boundary" {
  let data = b"\x02\x00\x00\x0a\x02\x04\x02\x00\x05\x0a\x01\x02"
  for split in 0..<=data.length() {
    let f = Framer::new()
    let a = f.feed(data[:split].to_owned())
    let b = f.feed(data[split:].to_owned())
    f.finish()
    assert_eq(a.length() + b.length(), 2)
  }
}

///|
test "framing rejects truncation invalid FAR and resource overflow" {
  assert_true(
    try {
      ignore(decode_frames(b"\x02\x00\x00\x0a\x02"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_frames(b"\x02\x00\x00\x0a\x02\x03"))
      false
    } catch {
      _ => true
    },
  )
  let f = Framer::new(max_bytes=5)
  assert_true(
    try {
      ignore(f.feed(b"\x02\x00\x00\x0a\x02\x04"))
      false
    } catch {
      _ => true
    },
  )
  let g = Framer::new(max_records=1)
  assert_true(
    try {
      ignore(g.feed(b"\x02\x00\x00\x0a\x02\x04\x00\x00\xc8\x00"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "checked primitives decode signed values floats and reject partial strings" {
  let r = Reader::new(b"\x34\x12\x00\x80\x00\x00\xc0\x3f\x03abc", Little, 40)
  assert_eq(r.u2(), 4660)
  assert_eq(r.i2(), -32768)
  assert_eq(r.r4(), 1.5)
  assert_eq(r.cn(), "abc")
  assert_true(
    try {
      ignore(r.u1())
      false
    } catch {
      _ => true
    },
  )
  let bad = Reader::new(b"\x03a", Little, 100)
  assert_true(
    try {
      ignore(bad.cn())
      false
    } catch {
      _ => true
    },
  )
  let be = Reader::new(b"\xff\xff\xff\xff\x3f\xc0\x00\x00", Big, 0)
  assert_eq(be.u4(), 4294967295U)
  assert_eq(be.r4(), 1.5)
}
