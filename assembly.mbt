///|
/// A diagnostic describes incomplete context without inventing a measurement.
#derive(Debug)
pub(all) struct Diagnostic {
  offset : Int32
  code : String
  message : String
}

///|
/// Resolved base-unit numeric observations or a functional execution.
#derive(Debug)
pub(all) struct Measurement {
  kind : String
  number : UInt32
  text : String
  values : Array[Double]
  units : String?
  low : Double?
  high : Double?
  low_equal : Bool
  high_equal : Bool
  flags : Int32
  param_flags : Int32
  offset : Int32
}

///|
/// Completed part; source offset and all reported flags remain available.
#derive(Debug)
pub(all) struct Part {
  lot : String
  wafer : String?
  result : PartResult
  tests : Array[Measurement]
  offset : Int32
}

///|
#derive(Debug)
pub(all) struct Analysis {
  parts : Array[Part]
  diagnostics : Array[Diagnostic]
  summaries : Array[Summary]
  unknown : Array[Frame]
  record_count : Int32
}

///|
pub struct PendingPart {
  lot : String
  wafer : String?
  tests : Array[Measurement]
  offset : Int32
}

///| Stateful analyzer accepts raw frames one at a time. Retains observations,

///|
/// but does not retain raw bytes for recognized records. Single use after EOF.
pub struct Analyzer {
  mut lot : String
  mut have_mir : Bool
  mut have_mrr : Bool
  mut count : Int32
  mut received : Int32
  mut order : ByteOrder?
  max_records : Int32
  max_bytes : Int32
  mut closed : Bool
  parts : Array[Part]
  diagnostics : Array[Diagnostic]
  summaries : Array[Summary]
  unknown : Array[Frame]
  groups : Map[String, Int32]
  wafers : Map[String, String]
  pending : Map[String, PendingPart]
  defaults : Map[String, TestDefaults]
}

///|
pub fn Analyzer::new(
  max_records~ : Int32 = 1000000,
  max_bytes~ : Int32 = 268435456,
) -> Analyzer {
  {
    lot: "",
    have_mir: false,
    have_mrr: false,
    count: 0,
    received: 0,
    order: None,
    max_records,
    max_bytes,
    closed: false,
    parts: [],
    diagnostics: [],
    summaries: [],
    unknown: [],
    groups: {},
    wafers: {},
    pending: {},
    defaults: {},
  }
}

///|
fn pair_key(head : Int32, site : Int32) -> String {
  "\{head}/\{site}"
}

///|
fn Analyzer::warn(
  self : Analyzer,
  offset : Int32,
  code : String,
  message : String,
) -> Unit {
  self.diagnostics.push({ offset, code, message, })
}

///|
fn Analyzer::wafer(
  self : Analyzer,
  head : Int32,
  site : Int32,
  offset : Int32,
) -> String? {
  if self.groups.get(pair_key(head, site)) is Some(group) {
    return self.wafers.get(pair_key(head, group))
  }
  let prefix = "\{head}/"
  let found = self.wafers
    .iter()
    .filter(fn(kv) { kv.0.has_prefix(prefix) })
    .map(fn(kv) { kv.1 })
    .collect()
  if found.length() == 1 {
    self.warn(
      offset, "wafer-fallback", "no SDR membership; used sole same-head wafer context",
    )
    Some(found[0])
  } else {
    if found.length() > 1 {
      self.warn(
        offset, "ambiguous-wafer", "multiple same-head wafer contexts; SDR membership missing",
      )
    }
    None
  }
}

///|
/// Immutable first-record defaults; validity bits control reuse versus absence.
fn resolve_defaults(
  current : TestDefaults,
  baseline : TestDefaults?,
) -> TestDefaults {
  let b = baseline.unwrap_or({
    flags: None,
    res_scale: None,
    low_scale: None,
    high_scale: None,
    low: None,
    high: None,
    units: None,
  })
  let flags = current.flags.unwrap_or(0)
  let no_low = (flags & 64) != 0
  let no_high = (flags & 128) != 0
  let reuse_low = (flags & 16) != 0
  let reuse_high = (flags & 32) != 0
  let units = match current.units {
    Some("\u0000") => None
    Some("") | None => b.units
    value => value
  }
  {
    flags: current.flags,
    res_scale: if (flags & 1) != 0 {
      b.res_scale
    } else {
      choose(current.res_scale, b.res_scale)
    },
    low_scale: if no_low {
      None
    } else if reuse_low {
      b.low_scale
    } else {
      choose(current.low_scale, b.low_scale)
    },
    high_scale: if no_high {
      None
    } else if reuse_high {
      b.high_scale
    } else {
      choose(current.high_scale, b.high_scale)
    },
    low: if no_low {
      None
    } else if reuse_low {
      b.low
    } else {
      choose(current.low, b.low)
    },
    high: if no_high {
      None
    } else if reuse_high {
      b.high
    } else {
      choose(current.high, b.high)
    },
    units,
  }
}

///|
fn Analyzer::test_record(
  self : Analyzer,
  observation : TestRecord,
  offset : Int32,
) -> Unit raise StdfError {
  if observation.kind == "PTR" &&
    observation.defaults.flags is Some(flags) &&
    (flags & 2) == 0 {
    raise StdfError(offset, "PTR OPT_FLAG reserved bit1 must be one")
  }
  if observation.kind != "PTR" && (observation.flags & 2) != 0 {
    raise StdfError(offset, "MPR/FTR TEST_FLG bit1 reserved")
  }
  let key = "\{observation.kind}/\{observation.number}"
  let d = resolve_defaults(observation.defaults, self.defaults.get(key))
  if !self.defaults.contains(key) {
    self.defaults[key] = d
  }
  if (d.low is Some(v) && !v.is_finite()) ||
    (d.high is Some(v) && !v.is_finite()) {
    self.warn(offset, "invalid-limit", "nonfinite observation limit excluded")
  }
  if (observation.flags & 16) != 0 {
    return
  } // includes default-only records outside PIR
  let measurement = {
    kind: observation.kind,
    number: observation.number,
    text: observation.text,
    values: observation.values,
    units: d.units,
    low: d.low.filter(fn(v) { v.is_finite() }),
    high: d.high.filter(fn(v) { v.is_finite() }),
    low_equal: (observation.param_flags & 64) != 0,
    high_equal: (observation.param_flags & 128) != 0,
    flags: observation.flags,
    param_flags: observation.param_flags,
    offset,
  }
  if self.pending.get(pair_key(observation.head, observation.site))
    is Some(part) {
    part.tests.push(measurement)
  } else {
    self.warn(
      offset, "orphan-test", "observation has no matching head/site PIR",
    )
  }
}

///|
pub fn Analyzer::accept(self : Analyzer, frame : Frame) -> Unit raise StdfError {
  if self.closed {
    raise StdfError(frame.offset, "analyzer closed")
  }
  errdefer {
    self.closed = true
  }
  validate_frame(frame)
  if self.count >= self.max_records {
    raise StdfError(frame.offset, "record budget exceeded")
  }
  if frame.body.length() + 4 > self.max_bytes - self.received {
    raise StdfError(frame.offset, "input byte budget exceeded")
  }
  if self.count == 0 && (frame.typ != 0 || frame.sub != 10) {
    raise StdfError(frame.offset, "first record must be FAR")
  }
  if self.order is Some(order) && order != frame.order {
    raise StdfError(frame.offset, "record byte order differs from FAR")
  }
  self.order = Some(frame.order)
  self.received += frame.body.length() + 4
  self.count += 1
  if self.have_mrr {
    raise StdfError(frame.offset, "record after MRR")
  }
  if decode_metadata(frame) is Some(meta) {
    match meta {
      Far(cpu, ver) =>
        if self.count != 1 || ver != 4 || (cpu != 1 && cpu != 2) {
          raise StdfError(frame.offset, "invalid FAR position/version/CPU")
        }
      Mir(info) => {
        if self.have_mir {
          raise StdfError(frame.offset, "multiple MIR records in one file")
        }
        self.have_mir = true
        self.lot = info.lot
      }
      Mrr(_) => self.have_mrr = true
      Sdr(head, group, sites) =>
        for site in sites {
          self.groups[pair_key(head, site)] = group
        }
      Wir(head, group, _, wafer) => {
        let key = pair_key(head, group)
        if self.wafers.contains(key) {
          self.warn(
            frame.offset,
            "replaced-wafer",
            "WIR replaced an unclosed wafer",
          )
        }
        self.wafers[key] = wafer
      }
      Wrr(head, group, _, _, _, wafer) => {
        let key = pair_key(head, group)
        if self.wafers.get(key) is Some(old) {
          if wafer != "" && wafer != old {
            self.warn(frame.offset, "wafer-id-mismatch", "WRR differs from WIR")
          }
        } else {
          self.warn(frame.offset, "orphan-wafer-end", "WRR has no WIR")
        }
        self.wafers.remove(key)
      }
      Wcr(_) => ()
    }
    return
  }
  if decode_part(frame) is Some(record) {
    match record {
      Pir(head, site) => {
        let key = pair_key(head, site)
        if self.pending.contains(key) {
          self.warn(
            frame.offset,
            "replaced-part",
            "PIR replaced unfinished same-head/site part",
          )
        }
        let wafer = self.wafer(head, site, frame.offset)
        self.pending[key] = {
          lot: self.lot,
          wafer,
          tests: [],
          offset: frame.offset,
        }
      }
      Prr(result) => {
        let key = pair_key(result.head, result.site)
        if self.pending.get(key) is Some(p) {
          if p.tests.length() != result.num_tests {
            self.warn(
              frame.offset,
              "observation-count-difference",
              "PRR NUM_TEST differs from retained observation-record count (not-executed tests excluded)",
            )
          }
          self.parts.push({
            lot: p.lot,
            wafer: p.wafer,
            result,
            tests: p.tests,
            offset: frame.offset,
          })
          self.pending.remove(key)
        } else {
          self.warn(frame.offset, "orphan-part-end", "PRR has no matching PIR")
        }
      }
    }
    return
  }
  if decode_parametric(frame) is Some(observation) {
    self.test_record(observation, frame.offset)
    return
  }
  if decode_functional(frame) is Some(observation) {
    self.test_record(observation, frame.offset)
    return
  }
  if decode_summary(frame) is Some(summary) {
    self.summaries.push(summary)
    return
  }
  self.unknown.push(frame)
}

///|
/// EOF closes the analyzer and reports unfinished structures.
pub fn Analyzer::finish(self : Analyzer) -> Analysis raise StdfError {
  if self.closed {
    raise StdfError(0, "analyzer closed")
  }
  self.closed = true
  if self.count == 0 {
    raise StdfError(0, "empty input; FAR required")
  }
  for _, part in self.pending {
    self.warn(part.offset, "unfinished-part", "PIR has no PRR at EOF")
  }
  if !self.have_mir {
    self.warn(0, "missing-mir", "no MIR lot identity")
  }
  if !self.have_mrr {
    self.warn(0, "missing-mrr", "no MRR lot terminator")
  }
  if self.wafers.length() > 0 {
    self.warn(0, "unfinished-wafer", "WIR has no WRR at EOF")
  }
  {
    parts: self.parts,
    diagnostics: self.diagnostics,
    summaries: self.summaries,
    unknown: self.unknown,
    record_count: self.count,
  }
}

///|
pub fn analyze(data : Bytes) -> Analysis raise StdfError {
  let a = Analyzer::new()
  for frame in decode_frames(data) {
    a.accept(frame)
  }
  a.finish()
}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Measurement with @debug.Debug::{to_repr}

///|
pub extend Part with @debug.Debug::{to_repr}

///|
pub extend Analysis with @debug.Debug::{to_repr}

///|
fn[T] choose(value : T?, fallback : T?) -> T? {
  match value {
    Some(_) => value
    None => fallback
  }
}
