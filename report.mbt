///|
fn[T : @json.ToJson] j(value : T) -> Json {
  @json.to_json(value)
}

///|
fn number_json(value : Double?) -> Json {
  match value {
    Some(v) if v.is_finite() => j(v)
    _ => Json::null()
  }
}

///|
fn outcome_name(value : Outcome) -> String {
  match value {
    Pass => "pass"
    Fail => "fail"
    Unknown => "unknown"
  }
}

///|
fn yield_json(y : YieldSummary) -> Json {
  {
    "total": j(y.total),
    "passed": j(y.passed),
    "failed": j(y.failed),
    "unknown": j(y.unknown),
    "abnormal": j(y.abnormal),
    "denominator": j(y.denominator),
    "yield": number_json(y.yield_rate),
  }
}

///|
fn signature_json(s : TestSignature) -> Json {
  {
    "kind": j(s.kind),
    "test_number": j(s.number),
    "units": option_json(s.units),
    "low_limit": number_json(s.low),
    "high_limit": number_json(s.high),
    "low_equality_passes": j(s.low_equal),
    "high_equality_passes": j(s.high_equal),
  }
}

///|
fn statistic_json(s : TestStatistics) -> Json {
  {
    "context": signature_json(s.signature),
    "text": j(s.text),
    "executions": j(s.executions),
    "passed": j(s.passed),
    "failed": j(s.failed),
    "unknown": j(s.unknown),
    "usable_samples": j(s.usable_samples),
    "excluded_samples": j(s.excluded_samples),
    "mean": number_json(s.mean),
    "population_stddev": number_json(s.stddev),
    "min": number_json(s.minimum),
    "max": number_json(s.maximum),
    "below_limit": j(s.below_limit),
    "above_limit": j(s.above_limit),
    "failure_rate": number_json(s.failure_rate),
  }
}

///|
fn diagnostic_json(d : Diagnostic) -> Json {
  { "offset": j(d.offset), "code": j(d.code), "message": j(d.message) }
}

///|
fn measurement_json(m : Measurement) -> Json {
  {
    "context": signature_json(test_signature(m)),
    "text": j(m.text),
    "values": Json::array(m.values.map(fn(v) { number_json(Some(v)) })),
    "test_flags": j(m.flags),
    "param_flags": j(m.param_flags),
    "offset": j(m.offset),
  }
}

///|
fn part_json(p : Part) -> Json {
  let r = p.result
  {
    "lot": j(p.lot),
    "wafer": option_json(p.wafer),
    "head": j(r.head),
    "site": j(r.site),
    "part_id": j(r.part_id),
    "part_text": j(r.part_text),
    "x": option_json(r.x),
    "y": option_json(r.y),
    "hard_bin": j(r.hard_bin),
    "soft_bin": option_json(r.soft_bin),
    "outcome": j(outcome_name(r.outcome)),
    "abnormal": j(r.abnormal),
    "flags": j(r.flags),
    "test_ms": j(r.test_ms),
    "reported_test_count": j(r.num_tests),
    "offset": j(p.offset),
    "tests": Json::array(p.tests.map(measurement_json)),
  }
}

///|
/// Stable schema tag; null denotes missing/nonfinite, never a fabricated zero.
pub fn report_json(a : Analysis) -> String {
  let diagnostics = a.diagnostics + summary_diagnostics(a)
  let groups = grouped_yield(a.parts).map(fn(g) -> Json {
    {
      "dimension": j(g.dimension),
      "key": j(g.key),
      "summary": yield_json(g.summary),
    }
  })
  let summaries = a.summaries.map(fn(s) -> Json {
    {
      "kind": j(s.kind),
      "head": j(s.head),
      "site": j(s.site),
      "number": option_json(s.number),
      "count": option_json(s.count),
      "good": option_json(s.good),
      "fails": option_json(s.fails),
      "label": j(s.label),
    }
  })
  let unknown = a.unknown.map(fn(f) -> Json {
    {
      "offset": j(f.offset),
      "type": j(f.typ),
      "subtype": j(f.sub),
      "body_length": j(f.body.length()),
    }
  })
  let root : Json = {
    "schema": j("moonstdf/1"),
    "counting_policy": j(
      "observations; yield=normal_pass/(normal_pass+normal_fail); unknown and abnormal excluded; no implicit retest collapse",
    ),
    "units_policy": j("stored STDF base units; SCAL affects display only"),
    "record_count": j(a.record_count),
    "yield": yield_json(yield_summary(a.parts)),
    "groups": Json::array(groups),
    "tests": Json::array(test_statistics(a.parts).map(statistic_json)),
    "parts": Json::array(a.parts.map(part_json)),
    "reported_summaries": Json::array(summaries),
    "unknown_records": Json::array(unknown),
    "diagnostics": Json::array(diagnostics.map(diagnostic_json)),
  }
  root.stringify(indent=2)
}

///|
/// Formula-leading text is prefixed by an apostrophe before CSV quoting.
fn csv_text(value : String) -> String {
  let trimmed = value.trim_start().to_owned()
  let safe_text = if trimmed.has_prefix("=") ||
    trimmed.has_prefix("+") ||
    trimmed.has_prefix("-") ||
    trimmed.has_prefix("@") ||
    value.has_prefix("\t") ||
    value.has_prefix("\r") {
    "'" + value
  } else {
    value
  }
  "\"" + safe_text.replace_all(old="\"", new="\"\"") + "\""
}

///|
/// One row per completed part. Missing coordinates/bins are empty fields.
pub fn parts_csv(parts : Array[Part]) -> String {
  let out = StringBuilder()
  out.write_string(
    "lot,wafer,head,site,part_id,x,y,hard_bin,soft_bin,outcome,abnormal,source_offset\n",
  )
  for p in parts {
    let r = p.result
    let fields = [
      csv_text(p.lot),
      csv_text(p.wafer.unwrap_or("")),
      r.head.to_string(),
      r.site.to_string(),
      csv_text(r.part_id),
      r.x.map(fn(v) { v.to_string() }).unwrap_or(""),
      r.y.map(fn(v) { v.to_string() }).unwrap_or(""),
      r.hard_bin.to_string(),
      r.soft_bin.map(fn(v) { v.to_string() }).unwrap_or(""),
      outcome_name(r.outcome),
      r.abnormal.to_string(),
      p.offset.to_string(),
    ]
    out.write_string(fields.join(",") + "\n")
  }
  out.to_string()
}

///|
fn html_escape(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///| Coordinates only: WCR orientation/physical die sizes are not transformed.

///|
/// Separate wafer panels prevent same coordinates in different lots merging.
fn wafer_maps(parts : Array[Part]) -> String {
  let groups : Map[String, Array[Part]] = Map([])
  let order = []
  for p in parts {
    if p.wafer is Some(w) &&
      w != "" &&
      p.result.x is Some(_) &&
      p.result.y is Some(_) {
      let key = scoped_key([p.lot, w])
      if groups.get(key) is Some(g) {
        g.push(p)
      } else {
        groups[key] = [p]
        order.push(key)
      }
    }
  }
  let out = StringBuilder()
  for key in order {
    let group = groups[key]
    let xs = group.map(fn(p) { p.result.x.unwrap() })
    let ys = group.map(fn(p) { p.result.y.unwrap() })
    let minx = xs.fold(init=xs[0], fn(a, b) { a.min(b) })
    let miny = ys.fold(init=ys[0], fn(a, b) { a.min(b) })
    let maxx = xs.fold(init=xs[0], fn(a, b) { a.max(b) })
    let maxy = ys.fold(init=ys[0], fn(a, b) { a.max(b) })
    let span = (maxx - minx + 1).max(maxy - miny + 1).to_double()
    let size = (360.0 / span).min(24.0)
    let positions : Map[String, Int32] = Map([])
    out.write_string(
      "<h3>" +
      html_escape(group[0].lot) +
      " / " +
      html_escape(group[0].wafer.unwrap()) +
      "</h3><svg role=\"img\" aria-label=\"Wafer coordinate observations\" viewBox=\"0 0 400 400\">",
    )
    for p in group {
      let x = p.result.x.unwrap()
      let y = p.result.y.unwrap()
      let coord_key = pair_key(x, y)
      positions[coord_key] = positions.get(coord_key).unwrap_or(0) + 1
      let color = if p.result.abnormal {
        "#8b5cf6"
      } else {
        match p.result.outcome {
          Pass => "#059669"
          Fail => "#dc2626"
          Unknown => "#64748b"
        }
      }
      let px = 20.0 + (x - minx).to_double() * 360.0 / span
      let py = 380.0 - (y - miny + 1).to_double() * 360.0 / span
      out.write_string(
        "<rect x=\"\{px}\" y=\"\{py}\" width=\"\{size}\" height=\"\{size}\" fill=\"\{color}\"><title>" +
        html_escape(p.result.part_id) +
        " (\{x},\{y}) source \{p.offset}</title></rect>",
      )
    }
    let duplicates = positions.values().filter(fn(n) { n > 1 }).count()
    out.write_string(
      "</svg><p>Repeated coordinate positions: \{duplicates}. Later observations overlay earlier ones; use an explicit first/last retest policy when needed.</p>",
    )
  }
  out.to_string()
}

///|
/// Self-contained offline HTML; no scripts, external assets, or embedded raw JSON.
pub fn report_html(a : Analysis) -> String {
  let y = yield_summary(a.parts)
  let rate = y.yield_rate.map(fn(v) { "\{v*100.0}%" }).unwrap_or("unavailable")
  let out = StringBuilder()
  out.write_string(
    "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>MoonSTDF report</title><style>body{font:16px system-ui;background:#f8fafc;color:#0f172a;max-width:1100px;margin:32px auto;padding:0 20px}table{border-collapse:collapse;width:100%;background:white}td,th{padding:9px;border:1px solid #cbd5e1;text-align:left}svg{width:400px;max-width:100%;background:white;border:1px solid #cbd5e1}pre{white-space:pre-wrap}small{color:#475569}</style><h1>MoonSTDF</h1><p>Observation yield: \{rate}; known denominator \{y.denominator}, passed \{y.passed}, failed \{y.failed}, unknown \{y.unknown}, abnormal \{y.abnormal}.</p><p>Unknown and abnormal parts excluded. No automatic retest collapse. Numeric statistics use STDF base units.</p><h2>Wafer coordinate maps</h2><p>Green pass · red fail · slate unknown · purple abnormal. +X right, +Y up; physical WCR orientation is not applied.</p>",
  )
  out.write_string(wafer_maps(a.parts))
  out.write_string(
    "<h2>Test distributions</h2><table><tr><th>Test</th><th>Units</th><th>Samples</th><th>Mean</th><th>Population SD</th><th>Failures / known</th></tr>",
  )
  for s in test_statistics(a.parts) {
    let mean = s.mean.map(fn(v) { v.to_string() }).unwrap_or("missing")
    let sd = s.stddev.map(fn(v) { v.to_string() }).unwrap_or("missing")
    out.write_string(
      "<tr><td>" +
      html_escape("\{s.signature.kind} \{s.signature.number} " + s.text) +
      "</td><td>" +
      html_escape(s.signature.units.unwrap_or("missing")) +
      "</td><td>\{s.usable_samples}</td><td>\{mean}</td><td>\{sd}</td><td>\{s.failed} / \{s.passed+s.failed}</td></tr>",
    )
  }
  out.write_string(
    "</table><h2>Part observations</h2><table><tr><th>Lot / wafer</th><th>Part ID</th><th>Site</th><th>Outcome</th><th>Hard bin</th><th>Source offset</th></tr>",
  )
  for p in a.parts {
    out.write_string(
      "<tr><td>" +
      html_escape(p.lot + " / " + p.wafer.unwrap_or("missing")) +
      "</td><td>" +
      html_escape(p.result.part_id) +
      "</td><td>\{p.result.head}/\{p.result.site}</td><td>" +
      outcome_name(p.result.outcome) +
      "</td><td>\{p.result.hard_bin}</td><td>\{p.offset}</td></tr>",
    )
  }
  out.write_string("</table><h2>Diagnostics</h2><ul>")
  for d in a.diagnostics + summary_diagnostics(a) {
    out.write_string(
      "<li>\{d.offset} " + html_escape(d.code + ": " + d.message) + "</li>",
    )
  }
  out.write_string(
    "</ul><small>STDF V4 analysis subset. Complete provenance and raw test flags are available in the JSON report.</small></html>",
  )
  out.to_string()
}

///|
/// JSON for cross-file retest matching. Selection policy belongs to caller.
pub fn retest_json(r : RetestReport) -> String {
  let root : Json = {
    "schema": j("moonstdf/retest/1"),
    "matched": j(r.matched),
    "recovered": j(r.recovered),
    "still_failed": j(r.still_failed),
    "regressed": j(r.regressed),
    "unknown": j(r.unknown),
    "ambiguous_identities": j(r.ambiguous),
    "unmatched_before": j(r.unmatched_before),
    "unmatched_after": j(r.unmatched_after),
    "bin_transitions": Json::array(
      r.transitions.map(fn(t) -> Json {
        {
          "before": j(t.before_bin),
          "after": j(t.after_bin),
          "count": j(t.count),
        }
      }),
    ),
    "diagnostics": Json::array(r.diagnostics.map(diagnostic_json)),
  }
  root.stringify(indent=2)
}

///|
/// No delta is emitted for incompatible contexts or missing units.
pub fn comparison_json(c : BatchComparison) -> String {
  let root : Json = {
    "schema": j("moonstdf/comparison/1"),
    "before_yield": yield_json(c.before_yield),
    "after_yield": yield_json(c.after_yield),
    "tests": Json::array(
      c.tests.map(fn(t) -> Json {
        {
          "context": signature_json(t.signature),
          "before": statistic_json(t.before),
          "after": statistic_json(t.after),
          "mean_delta": number_json(t.mean_delta),
          "failure_rate_delta": number_json(t.failure_rate_delta),
        }
      }),
    ),
    "diagnostics": Json::array(c.diagnostics.map(diagnostic_json)),
  }
  root.stringify(indent=2)
}

///|
fn[T : @json.ToJson] option_json(value : T?) -> Json {
  match value {
    Some(v) => j(v)
    None => Json::null()
  }
}
