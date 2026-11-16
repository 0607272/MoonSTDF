///|
/// A checked cursor; offsets refer to the original file, including its header.
pub struct Reader {
  data : Bytes
  order : ByteOrder
  base : Int32
  mut pos : Int32
}

///|
pub fn Reader::new(data : Bytes, order : ByteOrder, base : Int32) -> Reader {
  { data, order, base, pos: 0, }
}

///|
pub fn Reader::take(self : Reader, n : Int32) -> Bytes raise StdfError {
  if n < 0 || n > self.data.length() - self.pos {
    raise StdfError(self.base + self.pos, "partial or missing field")
  }
  let data = self.data[self.pos:self.pos + n].to_owned()
  self.pos += n
  data
}

///|
pub fn Reader::u1(self : Reader) -> Int32 raise StdfError {
  self.take(1)[0].to_int()
}

///|
pub fn Reader::u2(self : Reader) -> Int32 raise StdfError {
  let a = self.u1()
  let b = self.u1()
  if self.order != Big {
    a | (b << 8)
  } else {
    (a << 8) | b
  }
}

///|
pub fn Reader::u4(self : Reader) -> UInt32 raise StdfError {
  let a = self.u2().reinterpret_as_uint()
  let b = self.u2().reinterpret_as_uint()
  if self.order != Big {
    a | (b << 16)
  } else {
    (a << 16) | b
  }
}

///|
pub fn Reader::i1(self : Reader) -> Int32 raise StdfError {
  let x = self.u1()
  if x >= 128 {
    x - 256
  } else {
    x
  }
}

///|
pub fn Reader::i2(self : Reader) -> Int32 raise StdfError {
  let x = self.u2()
  if x >= 32768 {
    x - 65536
  } else {
    x
  }
}

///|
pub fn Reader::r4(self : Reader) -> Double raise StdfError {
  if self.order == Vax {
    return self.vax_real(2)
  }
  Float::reinterpret_from_uint(self.u4()).to_double()
}

///|
pub fn Reader::r8(self : Reader) -> Double raise StdfError {
  if self.order == Vax {
    return self.vax_real(4)
  }
  let a = self.u4().to_uint64()
  let b = self.u4().to_uint64()
  let bits = if self.order == Little { a | (b << 32) } else { (a << 32) | b }
  bits.reinterpret_as_double()
}

///|
/// VAX F and D store the sign/exponent word first, with little-endian bytes
/// within each 16-bit word. The implicit mantissa is 0.1 binary, bias 128.
/// D's 56 significant bits round to the host's IEEE binary64 precision.
fn Reader::vax_real(self : Reader, words : Int32) -> Double raise StdfError {
  let first = self.u2()
  let exponent = (first >> 7) & 255
  let negative = (first & 32768) != 0
  // Keep all 24/56 significant bits as an integer until the sole rounding
  // to binary64, avoiding double rounding around a binary64 midpoint.
  let mut mantissa = (128 | (first & 127)).to_uint64()
  for _ in 1..<words {
    mantissa = (mantissa << 16) | self.u2().to_uint64()
  }
  if exponent == 0 {
    if negative {
      raise StdfError(
        self.base + self.pos - words * 2,
        "VAX reserved floating operand",
      )
    }
    return 0.0
  }
  let mut value = mantissa.to_double() /
    (if words == 2 { 16777216.0 } else { 72057594037927936.0 })
  if exponent >= 128 {
    for _ in 0..<(exponent - 128) {
      value *= 2.0
    }
  } else {
    for _ in 0..<(128 - exponent) {
      value /= 2.0
    }
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
/// C*n byte strings are mapped losslessly as Latin-1, never guessed as UTF-8.
pub fn Reader::cn(self : Reader) -> String raise StdfError {
  let data = self.take(self.u1())
  let s = StringBuilder()
  for b in data {
    s.write_char(b.to_int().to_char().unwrap())
  }
  s.to_string()
}

///|
pub fn Reader::remaining(self : Reader) -> Int32 {
  self.data.length() - self.pos
}

///|
/// Absence at a legal optional suffix boundary differs from a partial field.
pub fn[T] Reader::optional(
  self : Reader,
  read : (Reader) -> T raise StdfError,
) -> T? raise StdfError {
  if self.remaining() == 0 {
    None
  } else {
    Some(read(self))
  }
}

///|
pub fn Reader::end(self : Reader) -> Unit raise StdfError {
  if self.remaining() != 0 {
    raise StdfError(
      self.base + self.pos,
      "unexpected trailing bytes in V4 record",
    )
  }
}

///|
fn validate_frame(frame : Frame) -> Unit raise StdfError {
  if frame.offset < 0 ||
    frame.offset > 2147418108 ||
    frame.typ < 0 ||
    frame.typ > 255 ||
    frame.sub < 0 ||
    frame.sub > 255 ||
    frame.body.length() > 65535 {
    raise StdfError(frame.offset, "invalid V4 record bounds")
  }
}
