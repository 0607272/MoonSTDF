///|
fn retest_part(
  lot : String,
  wafer : String?,
  id : String,
  x : Int32?,
  outcome : Outcome,
  offset : Int32,
) -> Part {
  {
    lot,
    wafer,
    offset,
    tests: [],
    result: {
      head: 1,
      site: 1,
      flags: 0,
      num_tests: 0,
      hard_bin: if outcome == Pass {
        1
      } else {
        2
      },
      soft_bin: None,
      x,
      y: Some(0),
      test_ms: 0U,
      part_id: id,
      part_text: "",
      outcome,
      abnormal: false,
    },
  }
}

///|
test "first and last policies never merge coordinates across wafers or lots" {
  let parts = [
    retest_part("L", Some("W"), "A", Some(1), Fail, 1),
    retest_part("L", Some("W"), "A", Some(1), Pass, 2),
    retest_part("L", Some("W2"), "B", Some(1), Pass, 3),
    retest_part("L2", Some("W"), "C", Some(1), Pass, 4),
  ]
  let first = select_retests(parts, First, WaferCoordinates)
  let last = select_retests(parts, Last, WaferCoordinates)
  assert_eq(first.parts.length(), 3)
  assert_eq(first.parts[0].offset, 1)
  assert_eq(last.parts[0].offset, 2)
  assert_eq(last.duplicates, 1)
}

///|
test "missing and conflicting identities remain visible instead of being dropped" {
  let missing = retest_part("L", None, "", None, Fail, 1)
  let a = retest_part("L", Some("W"), "A", Some(1), Fail, 2)
  let b = retest_part("L", Some("W"), "B", Some(1), Pass, 3)
  let r = select_retests([missing, a, b], Last, WaferCoordinates)
  assert_eq(r.parts.length(), 3)
  assert_true(r.diagnostics.any(fn(d) { d.code == "missing-retest-identity" }))
  assert_true(
    r.diagnostics.any(fn(d) { d.code == "ambiguous-retest-identity" }),
  )
}

///|
test "cross-file retest pairing reports recovery bin migration and duplicate ambiguity" {
  let fail = retest_part("L", Some("W"), "A", Some(1), Fail, 1)
  let pass = retest_part("L", Some("W"), "A", Some(1), Pass, 2)
  let r = compare_retests([fail], [pass], WaferCoordinates)
  assert_eq(r.matched, 1)
  assert_eq(r.recovered, 1)
  assert_eq(r.transitions[0].before_bin, 2)
  assert_eq(r.transitions[0].after_bin, 1)
  let ambiguous = compare_retests([fail, fail], [pass], PartId)
  assert_eq(ambiguous.matched, 0)
  assert_eq(ambiguous.ambiguous, 1)
}
