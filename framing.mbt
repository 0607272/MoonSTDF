///|
/// Byte order established by the first FAR. CPU_TYPE 0 (VAX) is unsupported.
#derive(Debug, Eq)
pub(all) enum ByteOrder {
  Little
  Big
}

///|
/// Errors always identify the absolute byte offset of the failed input.
#derive(Debug)
pub suberror StdfError {
  StdfError(Int32, String)
}

///|
/// Raw record body is retained even for unrecognized record types.
#derive(Debug, Eq)
pub(all) struct Frame {
  offset : Int32
  typ : Int32
  sub : Int32
  order : ByteOrder
  body : Bytes
}

///|
/// Stateful, single-use bounded incremental decoder. Errors poison the decoder.
pub struct Framer {
  mut pending : Bytes
  mut offset : Int32
  mut received : Int32
  mut count : Int32
  mut order : ByteOrder?
  mut closed : Bool
  max_bytes : Int32
  max_records : Int32
}

///|
pub fn Framer::new(
  max_bytes~ : Int32 = 268435456,
  max_records~ : Int32 = 1000000,
) -> Framer {
  {
    pending: b"",
    offset: 0,
    received: 0,
    count: 0,
    order: None,
    closed: false,
    max_bytes,
    max_records,
  }
}

///|
pub fn Framer::feed(
  self : Framer,
  chunk : Bytes,
) -> Array[Frame] raise StdfError {
  if self.closed {
    raise StdfError(self.offset, "decoder closed after finish or error")
  }
  errdefer {
    self.closed = true
  }
  if chunk.length() > self.max_bytes - self.received {
    raise StdfError(self.offset, "input byte budget exceeded")
  }
  self.received += chunk.length()
  let data = self.pending + chunk
  let mut p = 0
  let out : Array[Frame] = []
  if self.order is None && data.length() >= 6 {
    if data[2] != 0 || data[3] != 10 || data[5] != 4 {
      raise StdfError(0, "expected STDF V4 FAR")
    }
    let order = match data[4].to_int() {
      1 => Big
      2 => Little
      _ =>
        raise StdfError(4, "unsupported CPU_TYPE (only IEEE big/little endian)")
    }
    let r = Reader::new(data, order, 0)
    if r.u2() != 2 {
      raise StdfError(0, "FAR length must be two")
    }
    self.order = Some(order)
  }
  if self.order is Some(order) {
    while data.length() - p >= 4 {
      let r = Reader::new(data[p:p + 2].to_owned(), order, self.offset + p)
      let length = r.u2()
      if data.length() - p - 4 < length {
        break
      }
      if self.count >= self.max_records {
        raise StdfError(self.offset + p, "record budget exceeded")
      }
      let typ = data[p + 2].to_int()
      let sub = data[p + 3].to_int()
      if self.count > 0 && typ == 0 && sub == 10 {
        raise StdfError(self.offset + p, "unexpected second FAR")
      }
      out.push({
        offset: self.offset + p,
        typ,
        sub,
        order,
        body: data[p + 4:p + 4 + length].to_owned(),
      })
      p += length + 4
      self.count += 1
    }
  }
  self.pending = data[p:].to_owned()
  self.offset += p
  out
}

///|
/// Call at EOF: a truncated final record is an error, not a successful prefix.
pub fn Framer::finish(self : Framer) -> Unit raise StdfError {
  if self.closed {
    raise StdfError(self.offset, "decoder closed")
  }
  self.closed = true
  if self.order is None || self.pending.length() != 0 {
    raise StdfError(self.offset, "truncated FAR, record header or payload")
  }
}

///|
pub fn decode_frames(data : Bytes) -> Array[Frame] raise StdfError {
  let framer = Framer::new()
  let records = framer.feed(data)
  framer.finish()
  records
}

///|
pub extend ByteOrder with @debug.Debug::{to_repr}

///|
pub extend ByteOrder with Eq::{equal, not_equal}

///|
pub extend Frame with @debug.Debug::{to_repr}

///|
pub extend Frame with Eq::{equal, not_equal}

///|
pub extend StdfError with @debug.Debug::{to_repr}
