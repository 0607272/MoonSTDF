///|
#derive(Debug)
pub(all) struct ValidationReport {
  valid : Bool
  record_count : Int32
  record_counts : Map[String, Int32]
  diagnostics : Array[Diagnostic]
}

///|
/// Streaming structural and file-level checks; retains indexes, not payloads.
pub struct V4Validator {
  mut closed : Bool
  mut count : Int32
  mut received : Int32
  mut phase : Int32
  mut previous : String
  mut order : ByteOrder?
  max_records : Int32
  max_bytes : Int32
  counts : Map[String, Int32]
  diagnostics : Array[Diagnostic]
  pins : Map[Int32, Bool]
  pin_groups : Map[Int32, Bool]
  sections : Array[Int32]
  parts : Map[String, Int32]
  wafers : Map[String, String]
}

///|
pub fn V4Validator::new(
  max_records~ : Int32 = 1000000,
  max_bytes~ : Int32 = 268435456,
) -> V4Validator {
  {
    closed: false,
    count: 0,
    received: 0,
    phase: 0,
    previous: "",
    order: None,
    max_records,
    max_bytes,
    counts: Map([]),
    diagnostics: [],
    pins: Map([]),
    pin_groups: Map([]),
    sections: [],
    parts: Map([]),
    wafers: Map([]),
  }
}

///|
fn V4Validator::issue(
  self : V4Validator,
  offset : Int32,
  code : String,
  message : String,
) -> Unit {
  self.diagnostics.push({ offset, code, message, })
}

///|
fn v4_uint(record : V4Record, field : String) -> Int32? {
  match record.field(field) {
    Some(UnsignedField(n)) if n <= 2147483647U => Some(n.reinterpret_as_int())
    _ => None
  }
}

///|
fn v4_indexes(record : V4Record, field : String) -> Array[Int32] {
  let result = []
  if record.field(field) is Some(ArrayField(values)) {
    for value in values {
      if value is UnsignedField(n) && n <= 65535U {
        result.push(n.reinterpret_as_int())
      }
    }
  }
  result
}

///|
pub fn V4Validator::accept(
  self : V4Validator,
  frame : Frame,
) -> Unit raise StdfError {
  if self.closed {
    raise StdfError(frame.offset, "validator closed")
  }
  errdefer {
    self.closed = true
  }
  validate_frame(frame)
  if self.count >= self.max_records ||
    frame.body.length() + 4 > self.max_bytes - self.received {
    raise StdfError(frame.offset, "validation input budget exceeded")
  }
  let decoded = decode_v4_record(frame)
  // Existing projection decoders add value/flag invariants to named fields.
  let metadata = decode_metadata(frame)
  ignore(decode_part(frame))
  ignore(decode_summary(frame))
  ignore(decode_parametric(frame))
  ignore(decode_functional(frame))
  ignore(decode_ancillary(frame))
  let name = match decoded {
    Some(record) => record.name
    None => "unknown"
  }
  if self.count == 0 && name != "FAR" {
    raise StdfError(frame.offset, "first record must be FAR")
  }
  if self.order is Some(order) && order != frame.order {
    raise StdfError(frame.offset, "record byte order differs from FAR")
  }
  self.order = Some(frame.order)
  if self.counts.get("MRR").unwrap_or(0) > 0 {
    self.issue(frame.offset, "after-mrr", "MRR must be the final record")
  }
  self.count += 1
  self.received += frame.body.length() + 4
  self.counts[name] = self.counts.get(name).unwrap_or(0) + 1
  match metadata {
    Some(Wir(head, group, _, wafer)) => {
      let key = pair_key(head, group)
      if self.wafers.contains(key) {
        self.issue(
          frame.offset,
          "replaced-wafer",
          "WIR replaced an unclosed wafer",
        )
      }
      self.wafers[key] = wafer
    }
    Some(Wrr(head, group, _, _, _, wafer)) => {
      let key = pair_key(head, group)
      if self.wafers.get(key) is Some(old) {
        if wafer != "" && old != "" && wafer != old {
          self.issue(frame.offset, "wafer-id-mismatch", "WRR differs from WIR")
        }
      } else {
        self.issue(
          frame.offset,
          "orphan-wafer-end",
          "WRR has no matching head/group WIR",
        )
      }
      self.wafers.remove(key)
    }
    _ => ()
  }
  match name {
    "FAR" =>
      if self.count != 1 {
        self.issue(frame.offset, "duplicate-far", "exactly one FAR is required")
      }
    "ATR" =>
      if self.phase != 0 {
        self.issue(
          frame.offset,
          "atr-order",
          "ATRs must immediately follow FAR",
        )
      }
    "MIR" => {
      if self.phase != 0 || self.counts[name] > 1 {
        self.issue(
          frame.offset,
          "mir-order",
          "one MIR must follow FAR and optional ATRs",
        )
      }
      self.phase = 1
    }
    "RDR" => {
      if self.previous != "MIR" || self.counts[name] > 1 {
        self.issue(
          frame.offset,
          "rdr-order",
          "one optional RDR must immediately follow MIR",
        )
      }
      if self.phase == 1 {
        self.phase = 2
      }
    }
    "SDR" => {
      if self.phase < 1 || self.phase > 2 {
        self.issue(
          frame.offset,
          "sdr-order",
          "SDRs must immediately follow MIR or RDR",
        )
      }
      self.phase = 2
    }
    _ => {
      if self.phase == 0 {
        self.issue(
          frame.offset,
          "before-mir",
          "record appears before required MIR",
        )
      }
      self.phase = 3
    }
  }
  if decoded is Some(record) {
    match name {
      "PIR" => {
        let key = pair_key(
          v4_uint(record, "HEAD_NUM").unwrap_or(0),
          v4_uint(record, "SITE_NUM").unwrap_or(0),
        )
        if self.parts.contains(key) {
          self.issue(
            frame.offset,
            "replaced-part",
            "PIR replaced unfinished same-head/site part",
          )
        }
        self.parts[key] = frame.offset
      }
      "PMR" => {
        let index = v4_uint(record, "PMR_INDX").unwrap_or(0)
        if index < 1 || index > 32767 {
          self.issue(
            frame.offset,
            "pin-index-range",
            "PMR index must be 1..32767",
          )
        }
        if self.pins.contains(index) {
          self.issue(
            frame.offset,
            "duplicate-pin",
            "PMR indexes must not be reused",
          )
        }
        self.pins[index] = true
      }
      "PGR" => {
        let index = v4_uint(record, "GRP_INDX").unwrap_or(0)
        if index < 32768 {
          self.issue(
            frame.offset,
            "group-index-range",
            "PGR index must be 32768..65535",
          )
        }
        if self.pin_groups.contains(index) {
          self.issue(
            frame.offset,
            "duplicate-pin-group",
            "PGR index must be unique",
          )
        }
        for pin in v4_indexes(record, "PMR_INDX") {
          if !self.pins.contains(pin) {
            self.issue(
              frame.offset,
              "undefined-pin",
              "PGR references a PMR not yet defined",
            )
          }
        }
        self.pin_groups[index] = true
      }
      "PLR" =>
        for index in v4_indexes(record, "GRP_INDX") {
          if !self.pins.contains(index) && !self.pin_groups.contains(index) {
            self.issue(
              frame.offset,
              "undefined-pin-group",
              "PLR references an undefined pin or group",
            )
          }
        }
      "PTR" | "MPR" | "FTR" => {
        let flags = v4_uint(record, "TEST_FLG").unwrap_or(0)
        if name == "PTR" {
          if v4_uint(record, "OPT_FLAG") is Some(opt) && (opt & 2) == 0 {
            self.issue(
              frame.offset,
              "ptr-opt-flag",
              "PTR OPT_FLAG bit 1 must be one",
            )
          }
        } else if (flags & 2) != 0 {
          self.issue(
            frame.offset,
            "test-flag-reserved",
            "MPR/FTR TEST_FLG bit 1 must be zero",
          )
        }
        let key = pair_key(
          v4_uint(record, "HEAD_NUM").unwrap_or(0),
          v4_uint(record, "SITE_NUM").unwrap_or(0),
        )
        if (v4_uint(record, "TEST_FLG").unwrap_or(0) & 16) == 0 &&
          !self.parts.contains(key) {
          self.issue(
            frame.offset,
            "orphan-test",
            "executed test has no matching head/site PIR",
          )
        }
        for field in ["RTN_INDX", "PGM_INDX"] {
          for pin in v4_indexes(record, field) {
            if !self.pins.contains(pin) {
              self.issue(
                frame.offset,
                "undefined-pin",
                "test references a PMR not yet defined",
              )
            }
          }
        }
      }
      "BPS" => {
        if self.parts.is_empty() {
          self.issue(
            frame.offset,
            "section-outside-part",
            "BPS must occur within a PIR/PRR sequence",
          )
        }
        self.sections.push(frame.offset)
      }
      "EPS" =>
        if self.sections.pop() is None {
          self.issue(frame.offset, "orphan-eps", "EPS has no matching BPS")
        }
      "PRR" => {
        let key = pair_key(
          v4_uint(record, "HEAD_NUM").unwrap_or(0),
          v4_uint(record, "SITE_NUM").unwrap_or(0),
        )
        if !self.parts.contains(key) {
          self.issue(frame.offset, "orphan-part-end", "PRR has no matching PIR")
        }
        self.parts.remove(key)
        if !self.sections.is_empty() {
          self.issue(
            frame.offset,
            "section-after-prr",
            "program section must end before PRR",
          )
        }
      }
      "unknown" => ()
      _ => ()
    }
  } else {
    self.issue(
      frame.offset,
      "unknown-record",
      "record is not defined in base STDF V4",
    )
  }
  self.previous = name
}

///|
pub fn V4Validator::finish(
  self : V4Validator,
) -> ValidationReport raise StdfError {
  if self.closed {
    raise StdfError(0, "validator closed")
  }
  self.closed = true
  for
    (name, code) in [
      ("FAR", "missing-far"),
      ("MIR", "missing-mir"),
      ("PCR", "missing-pcr"),
      ("MRR", "missing-mrr"),
    ] {
    if self.counts.get(name).unwrap_or(0) == 0 {
      self.issue(0, code, "required " + name + " is absent")
    }
  }
  for offset in self.sections {
    self.issue(offset, "unfinished-section", "BPS has no matching EPS")
  }
  for _, offset in self.parts {
    self.issue(offset, "unfinished-part", "PIR has no PRR at EOF")
  }
  if self.wafers.length() > 0 {
    self.issue(0, "unfinished-wafer", "WIR has no WRR at EOF")
  }
  {
    valid: self.diagnostics.is_empty(),
    record_count: self.count,
    record_counts: self.counts,
    diagnostics: self.diagnostics,
  }
}

///|
pub fn validate_v4(data : Bytes) -> ValidationReport raise StdfError {
  let validator = V4Validator::new()
  for frame in decode_frames(data) {
    validator.accept(frame)
  }
  validator.finish()
}

///|
pub extend ValidationReport with @debug.Debug::{to_repr}
