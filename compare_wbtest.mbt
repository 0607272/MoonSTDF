///|
fn comparison_measurement(
  values : Array[Double],
  kind~ : String = "PTR",
  number~ : UInt32 = 1U,
  units~ : String? = Some("V"),
  low~ : Double? = Some(0.0),
  high~ : Double? = Some(5.0),
  low_equal~ : Bool = true,
  high_equal~ : Bool = true,
  flags~ : Int32 = 0,
  text~ : String = "test",
) -> Measurement {
  {
    kind,
    number,
    text,
    values,
    units,
    low,
    high,
    low_equal,
    high_equal,
    flags,
    param_flags: 0,
    offset: 0,
  }
}

///|
fn comparison_part(
  tests : Array[Measurement],
  outcome~ : Outcome = Pass,
) -> Part {
  {
    lot: "L",
    wafer: None,
    offset: 0,
    tests,
    result: {
      head: 1,
      site: 1,
      flags: 0,
      num_tests: tests.length(),
      hard_bin: 0,
      soft_bin: None,
      x: None,
      y: None,
      test_ms: 0U,
      part_id: "P",
      part_text: "",
      outcome,
      abnormal: false,
    },
  }
}

///|
test "compatible batches compare means and execution failure rates without changing counts" {
  let c = compare_batches(
    [
      comparison_part([comparison_measurement([1.0])]),
      comparison_part([comparison_measurement([3.0])]),
    ],
    [
      comparison_part([comparison_measurement([2.0])]),
      comparison_part(
        [comparison_measurement([4.0], flags=128, text="renamed")],
        outcome=Fail,
      ),
    ],
  )
  assert_eq(c.before_yield.yield_rate, Some(1.0))
  assert_eq(c.after_yield.yield_rate, Some(0.5))
  assert_eq(c.tests.length(), 1)
  let t = c.tests[0]
  assert_eq(t.mean_delta, Some(1.0))
  assert_eq(t.failure_rate_delta, Some(0.5))
  assert_eq(t.before.executions, 2)
  assert_eq(t.after.executions, 2)
  assert_eq(t.before.mean, Some(2.0))
  assert_eq(t.after.mean, Some(3.0))
  assert_eq(t.before.usable_samples, 2)
  assert_eq(t.after.usable_samples, 2)
  assert_eq(c.diagnostics.length(), 0)
}

///|
test "different units limits and equality rules cannot be compared" {
  let left = [comparison_part([comparison_measurement([1.0])])]
  for
    changed in [
      comparison_measurement([2.0], units=Some("A")),
      comparison_measurement([2.0], low=Some(0.1)),
      comparison_measurement([2.0], low=None),
      comparison_measurement([2.0], high=Some(6.0)),
      comparison_measurement([2.0], high=None),
      comparison_measurement([2.0], low_equal=false),
      comparison_measurement([2.0], high_equal=false),
    ] {
    let c = compare_batches(left, [comparison_part([changed])])
    assert_eq(c.tests.length(), 0)
    assert_true(
      c.diagnostics.any(fn(d) { d.code == "incompatible-test-context" }),
    )
  }
}

///|
test "unresolved units are refused for PTR and MPR even when both sides lack units" {
  for kind in ["PTR", "MPR"] {
    let missing = comparison_part([
      comparison_measurement([1.0], kind~, units=None),
    ])
    let resolved = comparison_part([comparison_measurement([2.0], kind~)])
    for
      c in [
        compare_batches([missing], [missing]),
        compare_batches([missing], [resolved]),
        compare_batches([resolved], [missing]),
      ] {
      assert_eq(c.tests.length(), 0)
      assert_true(
        c.diagnostics.any(fn(d) { d.code == "unresolved-test-context" }),
      )
    }
  }
}

///|
test "matched and incompatible variants on either side all remain accounted for" {
  let ordinary = comparison_measurement([1.0])
  let changed = comparison_measurement([2.0], units=Some("A"))
  for
    c in [
      compare_batches([comparison_part([ordinary])], [
        comparison_part([ordinary, changed]),
      ]),
      compare_batches([comparison_part([ordinary, changed])], [
        comparison_part([ordinary]),
      ]),
    ] {
    assert_eq(c.tests.length(), 1)
    assert_eq(c.tests[0].signature.units, Some("V"))
    assert_eq(c.diagnostics.length(), 1)
    assert_eq(c.diagnostics[0].code, "incompatible-test-context")
  }
}

///|
test "missing tests are diagnosed by side and kind remains part of identity" {
  let c = compare_batches(
    [comparison_part([comparison_measurement([1.0], number=1U)])],
    [
      comparison_part([
        comparison_measurement([2.0], number=2U),
        comparison_measurement([2.0], kind="MPR", number=1U),
      ]),
    ],
  )
  assert_eq(c.tests.length(), 0)
  assert_eq(c.diagnostics.length(), 3)
  assert_eq(c.diagnostics[0].code, "missing-right-test")
  assert_eq(c.diagnostics[1].code, "missing-left-test")
  assert_eq(c.diagnostics[2].code, "missing-left-test")
}

///|
test "comparison matches in left first-seen order independent of right order and text" {
  let c = compare_batches(
    [
      comparison_part([
        comparison_measurement([2.0], number=2U),
        comparison_measurement([1.0], number=1U),
      ]),
    ],
    [
      comparison_part([
        comparison_measurement([3.0], number=1U, text="other"),
        comparison_measurement([4.0], number=2U),
      ]),
    ],
  )
  assert_eq(c.tests.length(), 2)
  assert_eq(c.tests[0].signature.number, 2U)
  assert_eq(c.tests[1].signature.number, 1U)
  assert_eq(c.tests[0].mean_delta, Some(2.0))
  assert_eq(c.tests[1].mean_delta, Some(2.0))
}

///|
test "FTR matches without units and keeps absent means and unknown rates absent" {
  let c = compare_batches(
    [
      comparison_part([
        comparison_measurement(
          [],
          kind="FTR",
          units=None,
          low=None,
          high=None,
          flags=64,
        ),
      ]),
    ],
    [
      comparison_part([
        comparison_measurement(
          [],
          kind="FTR",
          units=None,
          low=None,
          high=None,
          flags=128,
        ),
      ]),
    ],
  )
  assert_eq(c.tests.length(), 1)
  assert_eq(c.tests[0].mean_delta, None)
  assert_eq(c.tests[0].failure_rate_delta, None)
  assert_eq(c.tests[0].before.unknown, 1)
  assert_eq(c.tests[0].after.failed, 1)
  assert_eq(c.diagnostics.length(), 0)
}

///|
test "empty and nonfinite numeric comparisons never manufacture deltas" {
  assert_eq(compare_batches([], []).tests.length(), 0)
  let c = compare_batches(
    [comparison_part([comparison_measurement([-1.0e308], low=None, high=None)])],
    [comparison_part([comparison_measurement([1.0e308], low=None, high=None)])],
  )
  assert_eq(c.tests[0].mean_delta, None)
  let c = compare_batches([comparison_part([comparison_measurement([])])], [
    comparison_part([comparison_measurement([1.0])]),
  ])
  assert_eq(c.tests[0].mean_delta, None)
}
