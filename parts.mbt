///|
/// Reported pass/fail indication; abnormal completion is a separate flag.
#derive(Debug, Eq)
pub(all) enum Outcome {
  Pass
  Fail
  Unknown
}

///|
#derive(Debug, Eq)
pub(all) struct PartResult {
  head : Int32
  site : Int32
  flags : Int32
  num_tests : Int32
  hard_bin : Int32
  soft_bin : Int32?
  x : Int32?
  y : Int32?
  test_ms : UInt32
  part_id : String
  part_text : String
  outcome : Outcome
  abnormal : Bool
}

///|
#derive(Debug, Eq)
pub(all) enum PartRecord {
  Pir(Int32, Int32)
  Prr(PartResult)
}

///|
/// Decode PIR/PRR without changing the source frame. Omitted suffixes use the
/// specification's missing values; present fields must be complete. PART_FIX
/// is checked as B*n; its application-specific bytes remain in Frame.body.
/// Conflicting supersession flags and nonzero reserved bits are fatal errors.
/// PART_FLG bit 2 is independent of outcome: yield policy must explicitly
/// exclude abnormal parts when counting successful completions.
pub fn decode_part(frame : Frame) -> PartRecord? raise StdfError {
  validate_frame(frame)
  if frame.typ != 5 || (frame.sub != 10 && frame.sub != 20) {
    return None
  }
  let r = Reader::new(frame.body, frame.order, frame.offset + 4)
  let head = r.u1()
  let site = r.u1()
  if frame.sub == 10 {
    if r.pos != r.data.length() {
      raise StdfError(
        r.base + r.pos,
        "PIR requires exactly HEAD_NUM and SITE_NUM",
      )
    }
    return Some(Pir(head, site))
  }
  let flags = r.u1()
  if (flags & 3) == 3 || (flags & 224) != 0 {
    raise StdfError(
      r.base + 2,
      "invalid PRR PART_FLG: conflicting supersession or reserved bits",
    )
  }
  let num_tests = r.u2()
  let hard_bin = r.u2()
  let soft_bin = if r.pos == r.data.length() {
    None
  } else {
    let value = r.u2()
    if value == 65535 {
      None
    } else {
      Some(value)
    }
  }
  let x = if r.pos == r.data.length() {
    None
  } else {
    let value = r.i2()
    if value == -32768 {
      None
    } else {
      Some(value)
    }
  }
  let y = if r.pos == r.data.length() {
    None
  } else {
    let value = r.i2()
    if value == -32768 {
      None
    } else {
      Some(value)
    }
  }
  let test_ms = if r.pos == r.data.length() { 0U } else { r.u4() }
  let part_id = if r.pos == r.data.length() { "" } else { r.cn() }
  let part_text = if r.pos == r.data.length() { "" } else { r.cn() }
  if r.pos != r.data.length() {
    ignore(r.take(r.u1()))
  }
  if r.pos != r.data.length() {
    raise StdfError(r.base + r.pos, "unexpected bytes after PRR PART_FIX")
  }
  let outcome = if (flags & 16) != 0 {
    Unknown
  } else if (flags & 8) != 0 {
    Fail
  } else {
    Pass
  }
  Some(
    Prr({
      head,
      site,
      flags,
      num_tests,
      hard_bin,
      soft_bin,
      x,
      y,
      test_ms,
      part_id,
      part_text,
      outcome,
      abnormal: (flags & 4) != 0,
    }),
  )
}

///|
pub extend Outcome with @debug.Debug::{to_repr}

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend PartResult with @debug.Debug::{to_repr}

///|
pub extend PartResult with Eq::{equal, not_equal}

///|
pub extend PartRecord with @debug.Debug::{to_repr}

///|
pub extend PartRecord with Eq::{equal, not_equal}
