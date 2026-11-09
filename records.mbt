///|
/// Relevant identity fields from MIR. Remaining optional text is validated.
#derive(Debug)
pub(all) struct LotInfo {
  setup : UInt32
  start : UInt32
  station : Int32
  lot : String
  product : String
  node : String
  tester : String
  job : String
}

///|
/// Missing WCR fields remain absent; coordinates use the STDF sentinel.
#derive(Debug)
pub(all) struct WaferGeometry {
  diameter : Double?
  die_height : Double?
  die_width : Double?
  units : Int32
  flat : Int32
  center_x : Int32?
  center_y : Int32?
  positive_x : Int32
  positive_y : Int32
}

///|
/// Typed analysis projections, not a lossless replacement for Frame.
#derive(Debug)
pub(all) enum Metadata {
  Far(Int32, Int32)
  Mir(LotInfo)
  Mrr(UInt32)
  Sdr(Int32, Int32, Array[Int32])
  Wir(Int32, Int32, UInt32, String)
  Wrr(Int32, Int32, UInt32, UInt32, UInt32?, String)
  Wcr(WaferGeometry)
}

///|
fn coord(x : Int32?) -> Int32? {
  x.filter(fn(v) { v != -32768 })
}

///|
fn counter(x : UInt32?) -> UInt32? {
  x.filter(fn(v) { v != 4294967295U })
}

///|
fn Reader::strings(
  self : Reader,
  count : Int32,
) -> Array[String] raise StdfError {
  let out = []
  for _ in 0..<count {
    out.push(self.optional(Reader::cn).unwrap_or(""))
  }
  out
}

///|
/// V4 metadata projections. Unknown record types are left to the caller.
pub fn decode_metadata(frame : Frame) -> Metadata? raise StdfError {
  let r = Reader::new(frame.body, frame.order, frame.offset + 4)
  let result = match (frame.typ, frame.sub) {
    (0, 10) => Some(Far(r.u1(), r.u1()))
    (1, 10) => {
      let setup = r.u4()
      let start = r.u4()
      let station = r.u1()
      ignore(r.take(6))
      let lot = r.cn()
      let product = r.cn()
      let node = r.cn()
      let tester = r.cn()
      let job = r.cn()
      ignore(r.strings(25))
      Some(Mir({ setup, start, station, lot, product, node, tester, job, }))
    }
    (1, 20) => {
      let finish = r.u4()
      ignore(r.optional(Reader::u1))
      ignore(r.strings(2))
      Some(Mrr(finish))
    }
    (1, 80) => {
      let head = r.u1()
      let group = r.u1()
      let count = r.u1()
      let sites = []
      for _ in 0..<count {
        sites.push(r.u1())
      }
      ignore(r.strings(16))
      Some(Sdr(head, group, sites))
    }
    (2, 10) => {
      let head = r.u1()
      let group = r.u1()
      let start = r.u4()
      Some(Wir(head, group, start, r.optional(Reader::cn).unwrap_or("")))
    }
    (2, 20) => {
      let head = r.u1()
      let group = r.u1()
      let finish = r.u4()
      let count = r.u4()
      ignore(r.optional(Reader::u4))
      ignore(r.optional(Reader::u4))
      let good = counter(r.optional(Reader::u4))
      ignore(r.optional(Reader::u4))
      let wafer = r.optional(Reader::cn).unwrap_or("")
      ignore(r.strings(5))
      Some(Wrr(head, group, finish, count, good, wafer))
    }
    (2, 30) => {
      let diameter = r
        .optional(Reader::r4)
        .filter(fn(v) { v > 0 && v.is_finite() })
      let die_height = r
        .optional(Reader::r4)
        .filter(fn(v) { v > 0 && v.is_finite() })
      let die_width = r
        .optional(Reader::r4)
        .filter(fn(v) { v > 0 && v.is_finite() })
      let units = r.optional(Reader::u1).unwrap_or(0)
      let flat = r.optional(Reader::u1).unwrap_or(32)
      let center_x = coord(r.optional(Reader::i2))
      let center_y = coord(r.optional(Reader::i2))
      let positive_x = r.optional(Reader::u1).unwrap_or(32)
      let positive_y = r.optional(Reader::u1).unwrap_or(32)
      Some(
        Wcr({
          diameter,
          die_height,
          die_width,
          units,
          flat,
          center_x,
          center_y,
          positive_x,
          positive_y,
        }),
      )
    }
    _ => None
  }
  if result is Some(_) {
    r.end()
  }
  result
}

///|
pub extend LotInfo with @debug.Debug::{to_repr}

///|
pub extend WaferGeometry with @debug.Debug::{to_repr}

///|
pub extend Metadata with @debug.Debug::{to_repr}
