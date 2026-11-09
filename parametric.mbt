///|
/// Physically present optional metadata. Omitted fields remain absent so that
/// the file assembler can apply the first record's immutable test defaults.
#derive(Debug)
pub(all) struct TestDefaults {
  flags : Int32?
  res_scale : Int32?
  low_scale : Int32?
  high_scale : Int32?
  low : Double?
  high : Double?
  units : String?
}

///|
/// Values and limits are already expressed in base UNITS. STDF scale fields
/// affect display only; they must never change statistical input values.
#derive(Debug)
pub(all) struct TestRecord {
  kind : String
  number : UInt32
  head : Int32
  site : Int32
  flags : Int32
  param_flags : Int32
  values : Array[Double]
  states : Array[Int32]
  indexes : Array[Int32]
  text : String
  defaults : TestDefaults
}

///|
fn param_optional_u1(r : Reader) -> Int32? raise StdfError {
  if r.pos == r.data.length() {
    None
  } else {
    Some(r.u1())
  }
}

///|
fn param_optional_i1(r : Reader) -> Int32? raise StdfError {
  if r.pos == r.data.length() {
    None
  } else {
    Some(r.i1())
  }
}

///|
fn param_optional_r4(r : Reader) -> Double? raise StdfError {
  if r.pos == r.data.length() {
    None
  } else {
    Some(r.r4())
  }
}

///|
fn param_optional_cn(r : Reader) -> String? raise StdfError {
  if r.pos == r.data.length() {
    None
  } else {
    Some(r.cn())
  }
}

///|
/// Decode STDF V4 PTR and MPR, retaining flags without deciding result validity.
/// Optional fields may stop at any field boundary, but may not be partial.
pub fn decode_parametric(frame : Frame) -> TestRecord? raise StdfError {
  if frame.typ != 15 || (frame.sub != 10 && frame.sub != 15) {
    return None
  }
  if frame.body.length() > 65535 {
    raise StdfError(frame.offset, "parametric record exceeds U*2 body length")
  }
  let r = Reader::new(frame.body, frame.order, frame.offset + 4)
  let number = r.u4()
  let head = r.u1()
  let site = r.u1()
  let flags = r.u1()
  let param_flags = r.u1()
  let values : Array[Double] = []
  let states : Array[Int32] = []
  let indexes : Array[Int32] = []
  let mut index_count = 0
  if frame.sub == 10 {
    // An invalid RESULT may disappear only with the whole remaining suffix.
    // Any physical bytes still start a complete R*4, even if flagged invalid.
    if r.pos != r.data.length() || (flags & 2) == 0 {
      values.push(r.r4())
    }
  } else {
    // STDF permits zero counters to be omitted at the trailing boundary.
    // Reading U*2 when any byte remains still rejects a partial counter.
    index_count = if r.pos == r.data.length() { 0 } else { r.u2() }
    let result_count = if r.pos == r.data.length() { 0 } else { r.u2() }
    let state_bytes = (index_count + 1) / 2
    // Check both arrays against the bounded body before allocating by counts.
    if state_bytes + result_count * 4 > r.data.length() - r.pos {
      raise StdfError(r.base + r.pos, "partial MPR returned arrays")
    }
    let packed = r.take(state_bytes)
    for i in 0..<index_count {
      let pair = packed[i / 2].to_int()
      states.push(if i % 2 == 0 { pair & 15 } else { pair >> 4 })
    }
    if index_count % 2 == 1 && packed[state_bytes - 1].to_int() >> 4 != 0 {
      raise StdfError(r.base + r.pos - 1, "nonzero MPR returned state padding")
    }
    for _ in 0..<result_count {
      values.push(r.r4())
    }
  }
  let text = param_optional_cn(r).unwrap_or("")
  ignore(param_optional_cn(r)) // ALARM_ID
  let opt_flags = param_optional_u1(r)
  let res_scale = param_optional_i1(r)
  let low_scale = param_optional_i1(r)
  let high_scale = param_optional_i1(r)
  let low = param_optional_r4(r)
  let high = param_optional_r4(r)
  if frame.sub == 15 {
    ignore(param_optional_r4(r)) // START_IN
    ignore(param_optional_r4(r)) // INCR_IN
    if r.pos < r.data.length() {
      if index_count * 2 > r.data.length() - r.pos {
        raise StdfError(r.base + r.pos, "partial MPR returned index array")
      }
      for _ in 0..<index_count {
        indexes.push(r.u2())
      }
    }
  }
  let units = param_optional_cn(r)
  if frame.sub == 15 {
    ignore(param_optional_cn(r)) // UNITS_IN
  }
  ignore(param_optional_cn(r)) // C_RESFMT
  ignore(param_optional_cn(r)) // C_LLMFMT
  ignore(param_optional_cn(r)) // C_HLMFMT
  ignore(param_optional_r4(r)) // LO_SPEC
  ignore(param_optional_r4(r)) // HI_SPEC
  if r.pos != r.data.length() {
    raise StdfError(r.base + r.pos, "unexpected parametric trailing fields")
  }
  Some({
    kind: if frame.sub == 10 {
      "PTR"
    } else {
      "MPR"
    },
    number,
    head,
    site,
    flags,
    param_flags,
    values,
    states,
    indexes,
    text,
    defaults: {
      flags: opt_flags,
      res_scale,
      low_scale,
      high_scale,
      low,
      high,
      units,
    },
  })
}

///|
pub extend TestDefaults with @debug.Debug::{to_repr}

///|
pub extend TestRecord with @debug.Debug::{to_repr}
