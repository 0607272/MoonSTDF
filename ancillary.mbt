///|
/// Variable-length generic value in a V4 GDR. Bytes stay binary; D*n retains
/// both its declared bit count and packed representation.
#derive(Debug)
pub(all) enum GenericValue {
  Padding
  U1(Int32)
  U2(Int32)
  U4(UInt32)
  I1(Int32)
  I2(Int32)
  I4(Int32)
  R4(Double)
  R8(Double)
  Text(String)
  Binary(Bytes)
  Bits(Int32, Bytes)
  Nibble(Int32)
}

///|
/// Typed records not consumed by current yield/statistics projections.
#derive(Debug)
pub(all) enum AncillaryRecord {
  Atr(UInt32, String)
  Pmr(UInt32, Int32, String, String, String, Int32, Int32)
  Pgr(UInt32, String, Array[Int32])
  Plr(Array[Int32], Array[Int32], Array[Int32], Array[Array[String]])
  Rdr(Array[Int32])
  Bps(String)
  Eps
  Gdr(Array[GenericValue])
  Dtr(String)
}

///|
fn ancillary_u2_array(
  r : Reader,
  count : Int32,
) -> Array[Int32] raise StdfError {
  if count < 0 || count > r.remaining() / 2 {
    raise StdfError(r.base + r.pos, "array count exceeds record body")
  }
  let values = []
  for _ in 0..<count {
    values.push(r.u2())
  }
  values
}

///|
fn gdr_value(r : Reader) -> GenericValue raise StdfError {
  let code = r.u1()
  match code {
    0 => Padding
    1 => U1(r.u1())
    2 => {
      if r.pos % 2 != 0 {
        raise StdfError(
          r.base + r.pos,
          "GDR U*2 requires an even-byte boundary",
        )
      }
      U2(r.u2())
    }
    3 => {
      if r.pos % 2 != 0 {
        raise StdfError(
          r.base + r.pos,
          "GDR U*4 requires an even-byte boundary",
        )
      }
      U4(r.u4())
    }
    4 => I1(r.i1())
    5 => {
      if r.pos % 2 != 0 {
        raise StdfError(
          r.base + r.pos,
          "GDR I*2 requires an even-byte boundary",
        )
      }
      I2(r.i2())
    }
    6 => {
      if r.pos % 2 != 0 {
        raise StdfError(
          r.base + r.pos,
          "GDR I*4 requires an even-byte boundary",
        )
      }
      I4(r.u4().reinterpret_as_int())
    }
    7 => {
      if r.pos % 2 != 0 {
        raise StdfError(
          r.base + r.pos,
          "GDR R*4 requires an even-byte boundary",
        )
      }
      R4(r.r4())
    }
    8 => {
      if r.pos % 2 != 0 {
        raise StdfError(
          r.base + r.pos,
          "GDR R*8 requires an even-byte boundary",
        )
      }
      R8(r.r8())
    }
    10 => Text(r.cn())
    11 => {
      let count = r.u1()
      Binary(r.take(count))
    }
    12 => {
      let bits = r.u2()
      let packed = r.take((bits + 7) / 8)
      if bits % 8 != 0 &&
        packed[packed.length() - 1].to_int() >> (bits % 8) != 0 {
        raise StdfError(r.base + r.pos - 1, "GDR D*n nonzero padding bits")
      }
      Bits(bits, packed)
    }
    13 => {
      let value = r.u1()
      if value > 15 {
        raise StdfError(r.base + r.pos - 1, "GDR N*1 high nibble must be zero")
      }
      Nibble(value)
    }
    _ => raise StdfError(r.base + r.pos - 1, "unknown GDR data type code")
  }
}

///|
/// Decode and validate the nine base-V4 record types not used by yield analysis.
pub fn decode_ancillary(frame : Frame) -> AncillaryRecord? raise StdfError {
  validate_frame(frame)
  let r = Reader::new(frame.body, frame.order, frame.offset + 4)
  let record = match (frame.typ, frame.sub) {
    (0, 20) => Some(Atr(r.u4(), r.cn()))
    (1, 60) =>
      Some(
        Pmr(
          r.u2().reinterpret_as_uint(),
          r.optional(Reader::u2).unwrap_or(0),
          r.optional(Reader::cn).unwrap_or(""),
          r.optional(Reader::cn).unwrap_or(""),
          r.optional(Reader::cn).unwrap_or(""),
          r.optional(Reader::u1).unwrap_or(1),
          r.optional(Reader::u1).unwrap_or(1),
        ),
      )
    (1, 62) => {
      let index = r.u2().reinterpret_as_uint()
      let name = r.cn()
      let count = r.u2()
      Some(Pgr(index, name, ancillary_u2_array(r, count)))
    }
    (1, 63) => {
      let count = r.u2()
      if count == 0 {
        raise StdfError(r.base, "PLR GRP_CNT must be greater than zero")
      }
      Some(
        Plr(
          ancillary_u2_array(r, count),
          ancillary_optional_modes(r, count),
          ancillary_optional_radixes(r, count),
          [
            ancillary_optional_strings(r, count),
            ancillary_optional_strings(r, count),
            ancillary_optional_strings(r, count),
            ancillary_optional_strings(r, count),
          ],
        ),
      )
    }
    (1, 70) => {
      let count = r.u2()
      Some(Rdr(ancillary_u2_array(r, count)))
    }
    (20, 10) => Some(Bps(r.optional(Reader::cn).unwrap_or("")))
    (20, 20) => Some(Eps)
    (50, 10) => {
      let count = r.u2()
      let values = []
      for _ in 0..<count {
        values.push(gdr_value(r))
      }
      Some(Gdr(values))
    }
    (50, 30) => Some(Dtr(r.cn()))
    _ => None
  }
  if record is Some(_) {
    r.end()
  }
  record
}

///|
fn ancillary_optional_modes(
  r : Reader,
  count : Int32,
) -> Array[Int32] raise StdfError {
  let out = []
  for _ in 0..<count {
    out.push(r.optional(Reader::u2).unwrap_or(0))
  }
  out
}

///|
fn ancillary_optional_radixes(
  r : Reader,
  count : Int32,
) -> Array[Int32] raise StdfError {
  let out = []
  for _ in 0..<count {
    out.push(r.optional(Reader::u1).unwrap_or(0))
  }
  out
}

///|
fn ancillary_optional_strings(
  r : Reader,
  count : Int32,
) -> Array[String] raise StdfError {
  let out = []
  for _ in 0..<count {
    out.push(r.optional(Reader::cn).unwrap_or(""))
  }
  out
}

///|
pub extend GenericValue with @debug.Debug::{to_repr}

///|
pub extend AncillaryRecord with @debug.Debug::{to_repr}
