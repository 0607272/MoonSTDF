///|
fn statistics_measurement(
  values : Array[Double],
  kind~ : String = "PTR",
  number~ : UInt32 = 1U,
  text~ : String = "Voltage",
  units~ : String? = Some("V"),
  low~ : Double? = Some(0.0),
  high~ : Double? = Some(4.0),
  low_equal~ : Bool = true,
  high_equal~ : Bool = true,
  flags~ : Int32 = 0,
  param_flags~ : Int32 = 0,
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
    param_flags,
    offset: 0,
  }
}

///|
fn statistics_part(tests : Array[Measurement]) -> Part {
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
      outcome: Pass,
      abnormal: false,
    },
  }
}

///|
test "statistics uses population Welford variance on base-unit values" {
  let stats = test_statistics([
    statistics_part([
      statistics_measurement([1.0]),
      statistics_measurement([2.0]),
      statistics_measurement([3.0]),
    ]),
  ])
  assert_eq(stats.length(), 1)
  let s = stats[0]
  assert_eq(s.executions, 3)
  assert_eq(s.passed, 3)
  assert_eq(s.failed, 0)
  assert_eq(s.unknown, 0)
  assert_eq(s.usable_samples, 3)
  assert_eq(s.mean, Some(2.0))
  assert_true((s.stddev.unwrap() - 0.816496580927726).abs() < 1.0e-12)
  assert_eq(s.minimum, Some(1.0))
  assert_eq(s.maximum, Some(3.0))
  assert_eq(s.failure_rate, Some(0.0))
}

///|
test "failed finite samples remain useful while unreliable and invalid values are excluded" {
  let inf = Reader::new(b"\x00\x00\x80\x7f", Little, 0).r4()
  let nan = Reader::new(b"\x00\x00\xc0\x7f", Little, 0).r4()
  let s = test_statistics([
      statistics_part([
        statistics_measurement([2.0], flags=128),
        statistics_measurement([10.0], flags=4),
        statistics_measurement([11.0], flags=1),
        statistics_measurement([12.0], param_flags=1),
        statistics_measurement([13.0], param_flags=2),
        statistics_measurement([14.0], param_flags=4),
        statistics_measurement([inf, nan]),
      ]),
    ])[0]
  assert_eq(s.executions, 7)
  assert_eq(s.failed, 1)
  assert_eq(s.passed, 6)
  assert_eq(s.usable_samples, 1)
  assert_eq(s.excluded_samples, 7)
  assert_eq(s.mean, Some(2.0))
  assert_eq(s.stddev, Some(0.0))
  assert_true((s.failure_rate.unwrap() - 1.0 / 7.0).abs() < 1.0e-12)
}

///|
test "unknown aborted and unexecuted outcomes do not enter known denominator" {
  let s = test_statistics([
      statistics_part([
        statistics_measurement([1.0], flags=128),
        statistics_measurement([2.0]),
        statistics_measurement([3.0], flags=64),
        statistics_measurement([4.0], flags=16 | 128),
        statistics_measurement([5.0], flags=32 | 128),
      ]),
    ])[0]
  assert_eq(s.executions, 5)
  assert_eq(s.passed, 1)
  assert_eq(s.failed, 1)
  assert_eq(s.unknown, 3)
  assert_eq(s.failure_rate, Some(0.5))
  assert_eq(s.usable_samples, 3)
  assert_eq(s.excluded_samples, 2)
}

///|
test "MPR counts one execution with several samples and FTR has no synthetic value" {
  let stats = test_statistics([
    statistics_part([
      statistics_measurement([1.0, 2.0, 3.0], kind="MPR", flags=128),
      statistics_measurement([4.0, 5.0], kind="MPR"),
      statistics_measurement(
        [],
        kind="FTR",
        units=None,
        low=None,
        high=None,
        flags=128,
      ),
    ]),
  ])
  assert_eq(stats.length(), 2)
  let s = stats[0]
  assert_eq(s.executions, 2)
  assert_eq(s.usable_samples, 5)
  assert_eq(s.failed, 1)
  assert_eq(s.failure_rate, Some(0.5))
  let f = stats[1]
  assert_eq(f.executions, 1)
  assert_eq(f.failed, 1)
  assert_eq(f.usable_samples, 0)
  assert_eq(f.excluded_samples, 0)
  assert_eq(f.mean, None)
  assert_eq(f.stddev, None)
  assert_eq(f.minimum, None)
  assert_eq(f.maximum, None)
}

///|
test "signatures include exact context and equality policy but exclude descriptive text" {
  let base = statistics_measurement([1.0])
  assert_eq(
    test_signature(base),
    test_signature(statistics_measurement([2.0], text="renamed", flags=128)),
  )
  let stats = test_statistics([
    statistics_part([
      base,
      statistics_measurement([2.0], text="renamed"),
      statistics_measurement([1.0], units=Some("A")),
      statistics_measurement([1.0], units=None),
      statistics_measurement([1.0], units=Some("")),
      statistics_measurement([1.0], low=None),
      statistics_measurement([1.0], low=Some(0.1)),
      statistics_measurement([1.0], high=None),
      statistics_measurement([1.0], high=Some(4.1)),
      statistics_measurement([1.0], low_equal=false),
      statistics_measurement([1.0], high_equal=false),
      statistics_measurement([1.0], kind="MPR"),
      statistics_measurement([1.0], number=2U),
    ]),
  ])
  assert_eq(stats.length(), 12)
  assert_eq(stats[0].executions, 2)
  assert_eq(stats[0].text, "Voltage")
  assert_eq(stats[1].signature.units, Some("A"))
  assert_eq(stats[2].signature.units, None)
  assert_eq(stats[3].signature.units, Some(""))
  assert_eq(stats[11].signature.number, 2U)
}

///|
test "limit geometry respects equality and alternate pass does not change reported outcome" {
  let stats = test_statistics([
    statistics_part([
      statistics_measurement([0.0, 4.0, -1.0, 5.0], param_flags=32),
      statistics_measurement([0.0, 4.0], low_equal=false, high_equal=false),
    ]),
  ])
  assert_eq(stats[0].below_limit, 1)
  assert_eq(stats[0].above_limit, 1)
  assert_eq(stats[0].passed, 1)
  assert_eq(stats[0].failed, 0)
  assert_eq(stats[1].below_limit, 1)
  assert_eq(stats[1].above_limit, 1)
}

///|
test "empty samples and all unknown status retain absent metrics" {
  assert_eq(test_statistics([]).length(), 0)
  let s = test_statistics([
      statistics_part([statistics_measurement([], flags=64)]),
    ])[0]
  assert_eq(s.executions, 1)
  assert_eq(s.unknown, 1)
  assert_eq(s.mean, None)
  assert_eq(s.stddev, None)
  assert_eq(s.failure_rate, None)
}
