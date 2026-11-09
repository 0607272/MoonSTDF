///|
fn report_part(id : String) -> Part {
  {
    lot: "L",
    wafer: Some("W"),
    offset: 42,
    tests: [],
    result: {
      head: 1,
      site: 1,
      flags: 0,
      num_tests: 0,
      hard_bin: 1,
      soft_bin: None,
      x: Some(-1),
      y: Some(2),
      test_ms: 0U,
      part_id: id,
      part_text: "",
      outcome: Pass,
      abnormal: false,
    },
  }
}

///|
test "JSON is parseable versioned and preserves source provenance" {
  let a : Analysis = {
    parts: [report_part("a\"b")],
    diagnostics: [],
    summaries: [],
    unknown: [],
    record_count: 4,
  }
  let output = report_json(a)
  assert_true(@json.valid(output))
  assert_true(output.contains("moonstdf/1"))
  assert_true(output.contains("42"))
  assert_true(output.contains("a\\\"b"))
}

///|
test "CSV quotes multiline data and neutralizes spreadsheet formulas" {
  let output = parts_csv([report_part("=SUM(1,2)\n\"x\"")])
  assert_true(output.contains("\"'=SUM(1,2)\n\"\"x\"\"\""))
  assert_true(output.has_prefix("lot,wafer,head,site"))
  assert_eq(parts_csv([]).split("\n").count(), 2)
}

///|
test "HTML escapes data and gives coordinate map no executable user content" {
  let a : Analysis = {
    parts: [report_part("<script>alert(1)</script>")],
    diagnostics: [],
    summaries: [],
    unknown: [],
    record_count: 4,
  }
  let html = report_html(a)
  assert_true(html.contains("&lt;script&gt;"))
  assert_true(!html.contains("<script>alert"))
  assert_true(html.contains("<svg"))
  assert_true(html.contains("Source offset"))
}
