///|
/// Mutually exclusive categories. Abnormal completion takes precedence over
/// reported outcome; unknown and abnormal parts never enter the denominator.
#derive(Debug)
pub(all) struct YieldSummary {
  total : Int32
  passed : Int32
  failed : Int32
  unknown : Int32
  abnormal : Int32
  denominator : Int32
  yield_rate : Double?
}

///|
pub fn yield_summary(parts : Array[Part]) -> YieldSummary {
  let mut passed = 0
  let mut failed = 0
  let mut unknown = 0
  let mut abnormal = 0
  for part in parts {
    if part.result.abnormal {
      abnormal += 1
    } else {
      match part.result.outcome {
        Pass => passed += 1
        Fail => failed += 1
        Unknown => unknown += 1
      }
    }
  }
  let denominator = passed + failed
  {
    total: parts.length(),
    passed,
    failed,
    unknown,
    abnormal,
    denominator,
    yield_rate: if denominator == 0 {
      None
    } else {
      Some(passed.to_double() / denominator.to_double())
    },
  }
}

///|
#derive(Debug)
pub(all) struct YieldGroup {
  dimension : String
  key : String
  summary : YieldSummary
}

///|
fn yield_text_key(value : String) -> String {
  "\{value.length()}:\{value}"
}

///|
fn yield_wafer_key(part : Part) -> String {
  let wafer = match part.wafer {
    None => "<missing>"
    Some(value) => "some(\{yield_text_key(value)})"
  }
  "lot=\{yield_text_key(part.lot)}|wafer=\{wafer}"
}

///|
fn yield_group_key(dimension : String, part : Part) -> String {
  if dimension == "lot" {
    return "lot=\{yield_text_key(part.lot)}"
  }
  let wafer = yield_wafer_key(part)
  if dimension == "wafer" {
    return wafer
  }
  let site = "\{wafer}|head=\{part.result.head}|site=\{part.result.site}"
  if dimension == "site" {
    return site
  }
  if dimension == "hard_bin" {
    return "\{site}|hard_bin=\{part.result.hard_bin}"
  }
  match part.result.soft_bin {
    None => "\{site}|soft_bin=<missing>"
    Some(bin) => "\{site}|soft_bin=\{bin}"
  }
}

///|
/// Dimension order is lot, wafer, site, hard_bin, soft_bin. Within a dimension,
/// groups follow first occurrence in input. Keys use length-prefixed identity
/// strings and explicit option tags, so delimiters and literal missing labels
/// cannot merge groups. Site/bin groups retain lot, wafer and head/site scope.
pub fn grouped_yield(parts : Array[Part]) -> Array[YieldGroup] {
  let out = []
  for dimension in ["lot", "wafer", "site", "hard_bin", "soft_bin"] {
    let groups : Map[String, Array[Part]] = Map([])
    let keys = []
    for part in parts {
      let key = yield_group_key(dimension, part)
      match groups.get(key) {
        Some(group) => group.push(part)
        None => {
          keys.push(key)
          groups[key] = [part]
        }
      }
    }
    for key in keys {
      out.push({ dimension, key, summary: yield_summary(groups[key]), })
    }
  }
  out
}

///|
fn yield_summary_scope(summary : Summary, part : Part) -> Bool {
  summary.head == 255 ||
  (
    summary.head == part.result.head &&
    (summary.site == 255 || summary.site == part.result.site)
  )
}

///|
fn yield_compare_counter(
  out : Array[Diagnostic],
  summary : Summary,
  field : String,
  reported : UInt32?,
  observed : Int32,
) -> Unit {
  if reported is Some(value) && value != observed.reinterpret_as_uint() {
    let number = summary.number.map(fn(n) { n.to_string() }).unwrap_or("all")
    out.push({
      offset: 0,
      code: "summary-\{field}-mismatch",
      message: "\{summary.kind} head=\{summary.head} site=\{summary.site} number=\{number}: reported \{field}=\{value}, observed=\{observed}",
    })
  }
}

///|
/// Compare reported counters with retained raw PRR/observation records, never
/// with retest-selected parts or the yield-policy denominator. The current
/// Summary projection has no source offset, so these diagnostics use offset 0.
/// PCR good counts are compared only with complete, known part outcomes.
/// TSR counts are compared only for observed supported test numbers, with no
/// unknown test record types or incomplete/orphan part/test contexts. A result
/// array is one execution; not-executed/default-only records do not count.
pub fn summary_diagnostics(analysis : Analysis) -> Array[Diagnostic] {
  let out = []
  let complete_tests = !analysis.unknown.any(fn(frame) { frame.typ == 15 }) &&
    !analysis.diagnostics.any(fn(d) {
      d.code == "orphan-test" ||
      d.code == "orphan-part-end" ||
      d.code == "unfinished-part" ||
      d.code == "replaced-part"
    })
  for summary in analysis.summaries {
    let scoped = analysis.parts.filter(fn(part) {
      yield_summary_scope(summary, part)
    })
    if summary.kind == "PCR" {
      yield_compare_counter(
        out,
        summary,
        "count",
        summary.count,
        scoped.length(),
      )
      if !scoped.any(fn(part) {
          part.result.abnormal || part.result.outcome == Unknown
        }) {
        let good = scoped
          .filter(fn(part) { part.result.outcome == Pass })
          .length()
        yield_compare_counter(out, summary, "good", summary.good, good)
      }
    } else if summary.kind == "HBR" || summary.kind == "SBR" {
      if summary.number is Some(number) {
        let count = scoped
          .filter(fn(part) {
            if summary.kind == "HBR" {
              part.result.hard_bin.reinterpret_as_uint() == number
            } else {
              match part.result.soft_bin {
                Some(bin) => bin.reinterpret_as_uint() == number
                None => false
              }
            }
          })
          .length()
        yield_compare_counter(out, summary, "count", summary.count, count)
      }
    } else if summary.kind == "TSR" && complete_tests {
      if summary.number is Some(number) {
        let mut count = 0
        let mut fails = 0
        let mut known_outcomes = true
        let mut first_kind = ""
        let mut mixed_kinds = false
        for part in scoped {
          for observation in part.tests {
            if observation.number == number &&
              (
                observation.kind == "PTR" ||
                observation.kind == "MPR" ||
                observation.kind == "FTR"
              ) &&
              (observation.flags & 16) == 0 {
              count += 1
              if first_kind == "" {
                first_kind = observation.kind
              } else if first_kind != observation.kind {
                mixed_kinds = true
              }
              if (observation.flags & 64) != 0 {
                known_outcomes = false
              } else if (observation.flags & 128) != 0 {
                fails += 1
              }
            }
          }
        }
        // A TSR for an unseen number may describe a tester feature outside the
        // retained observation projection; it cannot establish a denominator.
        if count > 0 && !mixed_kinds {
          yield_compare_counter(out, summary, "count", summary.count, count)
          if known_outcomes {
            yield_compare_counter(out, summary, "fail", summary.fails, fails)
          }
        }
      }
    }
  }
  out
}

///|
pub extend YieldSummary with @debug.Debug::{to_repr}

///|
pub extend YieldGroup with @debug.Debug::{to_repr}
