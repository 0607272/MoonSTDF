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
  pending : Array[Byte]
  mut target : Int32
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
    pending: [],
    target: 6,
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
  if self.max_bytes < 0 || self.max_records < 0 {
    raise StdfError(self.offset, "negative decoder budget")
  }
  if chunk.length() > self.max_bytes - self.received {
    raise StdfError(self.offset, "input byte budget exceeded")
  }
  self.received += chunk.length()
  let out : Array[Frame] = []
  // Append each input byte once. The growable current-record buffer avoids
  // recopying an ever-growing partial payload for every fragmented feed.
  for byte in chunk {
    if self.pending.length() == 0 && self.count >= self.max_records {
      raise StdfError(self.offset, "record budget exceeded")
    }
    self.pending.push(byte)
    if self.pending.length() != self.target {
      continue
    }
    let data = self.pending
    if self.order is None {
      if data[2] != 0 || data[3] != 10 || data[5] != 4 {
        raise StdfError(0, "expected STDF V4 FAR")
      }
      let order = match data[4].to_int() {
        1 => Big
        2 => Little
        _ =>
          raise StdfError(
            4, "unsupported CPU_TYPE (only IEEE big/little endian)",
          )
      }
      let length = if order == Little {
        data[0].to_int() | (data[1].to_int() << 8)
      } else {
        (data[0].to_int() << 8) | data[1].to_int()
      }
      if length != 2 {
        raise StdfError(0, "FAR length must be two")
      }
      self.order = Some(order)
    }
    let order = self.order.unwrap()
    if data.length() == 4 {
      let length = if order == Little {
        data[0].to_int() | (data[1].to_int() << 8)
      } else {
        (data[0].to_int() << 8) | data[1].to_int()
      }
      self.target = length + 4
      if self.target != 4 {
        continue
      }
    }
    let typ = data[2].to_int()
    let sub = data[3].to_int()
    if self.count > 0 && typ == 0 && sub == 10 {
      raise StdfError(self.offset, "unexpected second FAR")
    }
    // Materialize only a complete body; clearing the mutable buffer cannot
    // change any already emitted immutable Bytes.
    out.push({
      offset: self.offset,
      typ,
      sub,
      order,
      body: Bytes::from_array(data[4:]),
    })
    self.offset += self.target
    self.count += 1
    self.pending.clear()
    self.target = 4
  }
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
