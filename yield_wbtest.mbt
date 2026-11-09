///|
fn yield_part(
  outcome : Outcome,
  abnormal~ : Bool = false,
  lot~ : String = "L",
  wafer~ : String? = Some("W"),
  head~ : Int32 = 1,
  site~ : Int32 = 1,
  hard_bin~ : Int32 = 1,
  soft_bin~ : Int32? = Some(1),
  tests~ : Array[Measurement] = [],
) -> Part {
  {
    lot,
    wafer,
    tests,
    offset: 10,
    result: {
      head,
      site,
      flags: 0,
      num_tests: tests.length(),
      hard_bin,
      soft_bin,
      x: None,
      y: None,
      test_ms: 0U,
      part_id: "",
      part_text: "",
      outcome,
      abnormal,
    },
  }
}

///|
fn yield_analysis(parts : Array[Part], summaries : Array[Summary]) -> Analysis {
  { parts, summaries, diagnostics: [], unknown: [], record_count: 0, }
}

///|
fn yield_reported(
  kind : String,
  head~ : Int32 = 255,
  site~ : Int32 = 255,
  number~ : UInt32? = None,
  count~ : UInt32? = None,
  good~ : UInt32? = None,
  fails~ : UInt32? = None,
) -> Summary {
  { kind, head, site, number, count, good, fails, label: "", }
}

///|
test "yield excludes unknown and abnormal from the known outcome denominator" {
  let y = yield_summary([
    yield_part(Pass),
    yield_part(Fail),
    yield_part(Unknown),
    yield_part(Pass, abnormal=true),
  ])
  assert_eq(y.total, 4)
  assert_eq(y.passed, 1)
  assert_eq(y.failed, 1)
  assert_eq(y.unknown, 1)
  assert_eq(y.abnormal, 1)
  assert_eq(y.denominator, 2)
  assert_eq(y.yield_rate, Some(0.5))
  assert_eq(yield_summary([]).yield_rate, None)
  assert_eq(yield_summary([yield_part(Unknown)]).yield_rate, None)
}

///|
test "yield grouping keeps scope tuple identities distinct and explicit missing groups" {
  let parts = [
    yield_part(Pass, lot="a/b", wafer=Some("c")),
    yield_part(Fail, lot="a", wafer=Some("b/c")),
    yield_part(Pass, lot="a", wafer=None, soft_bin=None),
    yield_part(Pass, lot="a", wafer=Some("<missing>")),
    yield_part(Pass, lot="a", wafer=Some("b/c"), head=2),
  ]
  let groups = grouped_yield(parts)
  assert_eq(groups.filter(fn(g) { g.dimension == "lot" }).length(), 2)
  assert_eq(groups.filter(fn(g) { g.dimension == "wafer" }).length(), 4)
  assert_eq(groups.filter(fn(g) { g.dimension == "site" }).length(), 5)
  assert_eq(groups.filter(fn(g) { g.dimension == "hard_bin" }).length(), 5)
  assert_eq(groups.filter(fn(g) { g.dimension == "soft_bin" }).length(), 5)
  let missing = groups.filter(fn(g) {
    g.dimension == "soft_bin" && g.key.has_suffix("soft_bin=<missing>")
  })
  assert_eq(missing.length(), 1)
  assert_eq(missing[0].summary.passed, 1)
  assert_eq(groups[0].dimension, "lot")
  assert_eq(groups[1].dimension, "lot")
  assert_eq(groups[2].dimension, "wafer")
  assert_eq(grouped_yield([]).length(), 0)
  assert_eq(
    groups.map(fn(g) { g.key }),
    grouped_yield(parts).map(fn(g) { g.key }),
  )
}

///|
test "PCR discrepancies compare raw part counts and honor head site aggregates" {
  let a = yield_analysis([yield_part(Pass), yield_part(Fail, head=2, site=3)], [
    yield_reported("PCR", count=Some(3U), good=Some(1U)),
    yield_reported("PCR", head=1, count=Some(1U), good=Some(1U)),
    yield_reported("PCR", head=2, site=3, count=Some(1U), good=Some(0U)),
  ])
  let diagnostics = summary_diagnostics(a)
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].code, "summary-count-mismatch")
  assert_true(diagnostics[0].message.contains("PCR"))
}

///|
test "PCR good comparison is skipped for abnormal parts and unknown indications" {
  let a = yield_analysis(
    [yield_part(Pass, abnormal=true), yield_part(Unknown)],
    [yield_reported("PCR", count=Some(2U), good=Some(0U))],
  )
  assert_eq(summary_diagnostics(a).length(), 0)
}

///|
test "bin summaries compare raw membership without converting bins to outcomes" {
  let a = yield_analysis(
    [
      yield_part(Fail, hard_bin=7, soft_bin=None),
      yield_part(Pass, hard_bin=7, soft_bin=Some(4)),
    ],
    [
      yield_reported("HBR", number=Some(7U), count=Some(2U)),
      yield_reported("SBR", number=Some(4U), count=Some(2U)),
    ],
  )
  let d = summary_diagnostics(a)
  assert_eq(d.length(), 1)
  assert_true(d[0].message.contains("SBR"))
}

///|
test "TSR counts executions not returned values and skips unknown denominator" {
  let observation : Measurement = {
    kind: "MPR",
    number: 7U,
    text: "",
    values: [1.0, 2.0, 3.0],
    units: None,
    low: None,
    high: None,
    low_equal: false,
    high_equal: false,
    flags: 128,
    param_flags: 0,
    offset: 42,
  }
  let a = yield_analysis([yield_part(Pass, tests=[observation])], [
    yield_reported("TSR", number=Some(7U), count=Some(1U), fails=Some(1U)),
    yield_reported("TSR", number=Some(7U), count=Some(3U)),
    yield_reported("TSR", number=Some(99U), count=Some(5U)),
  ])
  let d = summary_diagnostics(a)
  assert_eq(d.length(), 1)
  assert_true(d[0].message.contains("TSR"))
}

///|
test "TSR ambiguous record kinds are not a supported comparison denominator" {
  let ptr : Measurement = {
    kind: "PTR",
    number: 7U,
    text: "",
    values: [1.0],
    units: None,
    low: None,
    high: None,
    low_equal: false,
    high_equal: false,
    flags: 0,
    param_flags: 0,
    offset: 1,
  }
  let ftr : Measurement = {
    kind: "FTR",
    number: 7U,
    text: "",
    values: [],
    units: None,
    low: None,
    high: None,
    low_equal: false,
    high_equal: false,
    flags: 128,
    param_flags: 0,
    offset: 2,
  }
  let a = yield_analysis([yield_part(Pass, tests=[ptr, ftr])], [
    yield_reported("TSR", number=Some(7U), count=Some(1U), fails=Some(0U)),
  ])
  // Summary currently omits TEST_TYP, so this TSR could describe either kind.
  assert_eq(summary_diagnostics(a).length(), 0)
}

///|
test "abnormal yield classification overrides fail and unknown outcomes too" {
  let y = yield_summary([
    yield_part(Fail, abnormal=true),
    yield_part(Unknown, abnormal=true),
  ])
  assert_eq(y.abnormal, 2)
  assert_eq(y.failed, 0)
  assert_eq(y.unknown, 0)
  assert_eq(y.denominator, 0)
  assert_eq(y.yield_rate, None)
}
