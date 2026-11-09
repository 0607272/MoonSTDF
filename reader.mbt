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
  if self.order == Little {
    a | (b << 8)
  } else {
    (a << 8) | b
  }
}

///|
pub fn Reader::u4(self : Reader) -> UInt32 raise StdfError {
  let a = self.u2().reinterpret_as_uint()
  let b = self.u2().reinterpret_as_uint()
  if self.order == Little {
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
  Float::reinterpret_from_uint(self.u4()).to_double()
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
