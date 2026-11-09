///|
#derive(Debug)
pub(all) struct TestComparison {
  signature : TestSignature
  before : TestStatistics
  after : TestStatistics
  mean_delta : Double?
  failure_rate_delta : Double?
}

///|
#derive(Debug)
pub(all) struct BatchComparison {
  before_yield : YieldSummary
  after_yield : YieldSummary
  tests : Array[TestComparison]
  diagnostics : Array[Diagnostic]
}

///|
fn comparison_identity(signature : TestSignature) -> String {
  "\{signature.kind}/\{signature.number}"
}

///|
fn comparison_unresolved(signature : TestSignature) -> Bool {
  (signature.kind == "PTR" || signature.kind == "MPR") &&
  signature.units is None
}

///|
fn comparison_delta(before : Double?, after : Double?) -> Double? {
  match (before, after) {
    (Some(a), Some(b)) => {
      let delta = b - a
      if a.is_finite() && b.is_finite() && delta.is_finite() {
        Some(delta)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn comparison_warn(
  diagnostics : Array[Diagnostic],
  signature : TestSignature,
  side : String,
  code : String,
) -> Unit {
  diagnostics.push({
    offset: 0,
    code,
    message: "\{side} batch \{signature.kind} test \{signature.number}: \{code}; exact units, limits, and equality policy required",
  })
}

///|
/// Compare raw batch statistics in left first-seen context order. Exact
/// signatures are required, independently of text. PTR/MPR with missing units
/// are unresolved, even if both sides have the same missing context. FTR can
/// match without units because it supplies execution status, not numeric data.
/// Every unmatched signature on either side produces a diagnostic; matched
/// variants do not hide additional changed variants. Diagnostics use offset 0
/// because a signature can aggregate observations at multiple source offsets.
/// Deltas are after minus before, absent if either metric or the delta is
/// nonfinite. No significance or causal claim is inferred from a difference.
pub fn compare_batches(
  left : Array[Part],
  right : Array[Part],
) -> BatchComparison {
  let before = test_statistics(left)
  let after = test_statistics(right)
  let before_identities : Map[String, Bool] = Map([])
  let after_identities : Map[String, Bool] = Map([])
  let after_indexes : Map[TestSignature, Int32] = Map([])
  for item in before {
    before_identities[comparison_identity(item.signature)] = true
  }
  for i in 0..<after.length() {
    after_identities[comparison_identity(after[i].signature)] = true
    after_indexes[after[i].signature] = i
  }
  let matched = after.map(fn(_) { false })
  let tests = []
  let diagnostics = []
  for item in before {
    let signature = item.signature
    if comparison_unresolved(signature) {
      comparison_warn(
        diagnostics, signature, "before", "unresolved-test-context",
      )
      continue
    }
    if after_indexes.get(signature) is Some(index) {
      let other = after[index]
      matched[index] = true
      tests.push({
        signature,
        before: item,
        after: other,
        mean_delta: comparison_delta(item.mean, other.mean),
        failure_rate_delta: comparison_delta(
          item.failure_rate,
          other.failure_rate,
        ),
      })
    } else {
      let code = if after_identities.contains(comparison_identity(signature)) {
        "incompatible-test-context"
      } else {
        "missing-right-test"
      }
      comparison_warn(diagnostics, signature, "before", code)
    }
  }
  for i in 0..<after.length() {
    if matched[i] {
      continue
    }
    let signature = after[i].signature
    let code = if comparison_unresolved(signature) {
      "unresolved-test-context"
    } else if before_identities.contains(comparison_identity(signature)) {
      "incompatible-test-context"
    } else {
      "missing-left-test"
    }
    comparison_warn(diagnostics, signature, "after", code)
  }
  {
    before_yield: yield_summary(left),
    after_yield: yield_summary(right),
    tests,
    diagnostics,
  }
}

///|
pub extend TestComparison with @debug.Debug::{to_repr}

///|
pub extend BatchComparison with @debug.Debug::{to_repr}
