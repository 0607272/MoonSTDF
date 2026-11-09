///|
/// Counts reported by the file, kept separate from recomputed analysis counts.
/// Label is a bin name or TSR TEST_NAM. Unprojected counters remain in Frame.
#derive(Debug, Eq)
pub(all) struct Summary {
  kind : String
  head : Int32
  site : Int32
  number : UInt32?
  count : UInt32?
  good : UInt32?
  fails : UInt32?
  label : String
}

///|
/// PCR/HBR/SBR/TSR analysis projections. All present fields are checked even
/// when not projected; legal omitted suffixes do not invent zero counts.
pub fn decode_summary(frame : Frame) -> Summary? raise StdfError {
  validate_frame(frame)
  let kind = match (frame.typ, frame.sub) {
    (1, 30) => "PCR"
    (1, 40) => "HBR"
    (1, 50) => "SBR"
    (10, 30) => "TSR"
    _ => return None
  }
  let r = Reader::new(frame.body, frame.order, frame.offset + 4)
  let head = r.u1()
  let site = r.u1()
  let mut number = None
  let mut count = None
  let mut good = None
  let mut fails = None
  let mut label = ""
  if kind == "PCR" {
    count = Some(r.u4())
    ignore(r.optional(Reader::u4)) // RTST_CNT
    ignore(r.optional(Reader::u4)) // ABRT_CNT
    good = counter(r.optional(Reader::u4))
    ignore(r.optional(Reader::u4)) // FUNC_CNT
  } else if kind == "TSR" {
    ignore(r.u1()) // TEST_TYP remains in Frame.
    number = Some(r.u4())
    count = counter(r.optional(Reader::u4))
    fails = counter(r.optional(Reader::u4))
    ignore(r.optional(Reader::u4)) // ALRM_CNT
    label = r.optional(Reader::cn).unwrap_or("")
    ignore(r.strings(2)) // SEQ_NAME, TEST_LBL
    if r.optional(Reader::u1) is Some(flags) {
      if (flags & 200) != 200 {
        raise StdfError(
          r.base + r.pos - 1,
          "TSR OPT_FLAG reserved bits 3,6,7 must be one",
        )
      }
    }
    for _ in 0..<5 {
      ignore(r.optional(Reader::r4))
    }
  } else {
    number = Some(r.u2().reinterpret_as_uint())
    count = Some(r.u4())
    let pf = r.optional(Reader::u1).unwrap_or(32)
    if pf == 80 {
      good = count
    }
    if pf == 70 {
      fails = count
    }
    label = r.optional(Reader::cn).unwrap_or("")
  }
  r.end()
  Some({ kind, head, site, number, count, good, fails, label, })
}

///|
fn functional_nibbles(
  r : Reader,
  count : Int32,
) -> Array[Int32] raise StdfError {
  let packed = r.take((count + 1) / 2)
  let states = []
  for i in 0..<count {
    let byte = packed[i / 2].to_int()
    states.push(if i % 2 == 0 { byte & 15 } else { byte >> 4 })
  }
  if count % 2 == 1 && packed[packed.length() - 1].to_int() >> 4 != 0 {
    raise StdfError(r.base + r.pos - 1, "FTR nonzero nibble padding")
  }
  states
}

///|
fn functional_bitmap(r : Reader) -> Unit raise StdfError {
  if r.remaining() == 0 {
    return
  }
  let bits = r.u2()
  let packed = r.take((bits + 7) / 8)
  if bits % 8 != 0 && packed[packed.length() - 1].to_int() >> (bits % 8) != 0 {
    raise StdfError(r.base + r.pos - 1, "FTR nonzero bitmap padding")
  }
}

///|
/// FTR projects identity, TEST_FLG, returned RTN_INDX/RTN_STAT and TEST_TXT.
/// Values are empty: cycle/address data, programmed pin arrays, bitmaps, other
/// strings and PATG_NUM remain in the original Frame after structural checks.
/// PATG_NUM/SPIN_MAP defaults are not resolved because neither is analyzed or
/// projected here. All TestDefaults fields are absent; TEST_TXT never inherits.
pub fn decode_functional(frame : Frame) -> TestRecord? raise StdfError {
  validate_frame(frame)
  if frame.typ != 15 || frame.sub != 20 {
    return None
  }
  let r = Reader::new(frame.body, frame.order, frame.offset + 4)
  let number = r.u4()
  let head = r.u1()
  let site = r.u1()
  let flags = r.u1()
  if (flags & 2) != 0 {
    raise StdfError(r.base + 6, "FTR TEST_FLG reserved bit 1 must be zero")
  }
  if r.optional(Reader::u1) is Some(opt) {
    if (opt & 192) != 192 {
      raise StdfError(
        r.base + r.pos - 1,
        "FTR OPT_FLAG reserved bits 6,7 must be one",
      )
    }
  }
  // Six 4-byte fields: CYCL_CNT, REL_VADR, REPT_CNT, NUM_FAIL, XFAIL_AD, YFAIL_AD.
  for _ in 0..<6 {
    ignore(r.optional(Reader::u4))
  }
  ignore(r.optional(Reader::i2)) // VECT_OFF
  let returned = r.optional(Reader::u2).unwrap_or(0)
  let programmed = r.optional(Reader::u2).unwrap_or(0)
  let required = returned * 2 +
    (returned + 1) / 2 +
    programmed * 2 +
    (programmed + 1) / 2
  if required > r.remaining() {
    raise StdfError(
      r.base + r.pos,
      "partial FTR returned or programmed pin arrays",
    )
  }
  let indexes = []
  for _ in 0..<returned {
    indexes.push(r.u2())
  }
  let states = functional_nibbles(r, returned)
  for _ in 0..<programmed {
    ignore(r.u2())
  }
  ignore(functional_nibbles(r, programmed))
  functional_bitmap(r) // FAIL_PIN
  let strings = r.strings(7)
  ignore(r.optional(Reader::u1)) // PATG_NUM
  functional_bitmap(r) // SPIN_MAP
  r.end()
  Some({
    kind: "FTR",
    number,
    head,
    site,
    flags,
    param_flags: 0,
    values: [],
    states,
    indexes,
    text: strings[3],
    defaults: {
      flags: None,
      res_scale: None,
      low_scale: None,
      high_scale: None,
      low: None,
      high: None,
      units: None,
    },
  })
}

///|
pub extend Summary with @debug.Debug::{to_repr}

///|
pub extend Summary with Eq::{equal, not_equal}
