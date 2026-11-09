///|
/// Exact base-unit context. Text is descriptive, not a grouping key. None
/// units stays distinct from an empty or explicit unit; comparisons must
/// treat such a context as unresolved. Analyzer resolves finite limits.
#derive(Debug, Eq, Hash)
pub(all) struct TestSignature {
  kind : String
  number : UInt32
  units : String?
  low : Double?
  high : Double?
  low_equal : Bool
  high_equal : Bool
}

///|
pub fn test_signature(m : Measurement) -> TestSignature {
  {
    kind: m.kind,
    number: m.number,
    units: m.units,
    low: m.low,
    high: m.high,
    low_equal: m.low_equal,
    high_equal: m.high_equal,
  }
}

///|
/// Execution outcomes and numeric sample quality are independent. Standard
/// deviation uses population variance. Failure rate uses known outcomes only.
#derive(Debug)
pub(all) struct TestStatistics {
  signature : TestSignature
  text : String
  executions : Int32
  passed : Int32
  failed : Int32
  unknown : Int32
  usable_samples : Int32
  excluded_samples : Int32
  mean : Double?
  stddev : Double?
  minimum : Double?
  maximum : Double?
  below_limit : Int32
  above_limit : Int32
  failure_rate : Double?
}

///|
priv struct StatisticsAccumulator {
  signature : TestSignature
  text : String
  mut executions : Int32
  mut passed : Int32
  mut failed : Int32
  mut unknown : Int32
  mut usable : Int32
  mut excluded : Int32
  mut scale : Double
  // Mean and M2 are accumulated after division by the largest absolute value.
  mut mean : Double
  mut m2 : Double
  mut minimum : Double?
  mut maximum : Double?
  mut below : Int32
  mut above : Int32
}

///|
/// Deterministic first-seen signature order; each observation record is one
/// execution, including MPR records with multiple values. Useful numeric
/// samples require clear TEST_FLG bits 0..5, clear PARM_FLG bits 0..2, and a
/// finite value. A finite failed sample still contributes. Geometric limit
/// counts honor equality policy and never replace reported pass/fail, including
/// alternate-limit passes. FTR contributes status only, without numeric data.
/// Welford accumulation is normalized by a running magnitude scale so finite
/// opposite-sign Doubles cannot overflow the difference or squared deviation.
pub fn test_statistics(parts : Array[Part]) -> Array[TestStatistics] {
  let indexes : Map[TestSignature, Int32] = Map([])
  let groups : Array[StatisticsAccumulator] = []
  for part in parts {
    for m in part.tests {
      let signature = test_signature(m)
      let index = match indexes.get(signature) {
        Some(i) => i
        None => {
          let i = groups.length()
          indexes[signature] = i
          groups.push({
            signature,
            text: m.text,
            executions: 0,
            passed: 0,
            failed: 0,
            unknown: 0,
            usable: 0,
            excluded: 0,
            scale: 0.0,
            mean: 0.0,
            m2: 0.0,
            minimum: None,
            maximum: None,
            below: 0,
            above: 0,
          })
          i
        }
      }
      let g = groups[index]
      g.executions += 1
      if (m.flags & 112) != 0 {
        g.unknown += 1
      } else if (m.flags & 128) != 0 {
        g.failed += 1
      } else {
        g.passed += 1
      }
      if m.kind == "FTR" {
        continue
      }
      let useful = (m.flags & 63) == 0 && (m.param_flags & 7) == 0
      for value in m.values {
        if !useful || !value.is_finite() {
          g.excluded += 1
          continue
        }
        g.usable += 1
        let magnitude = value.abs()
        if magnitude > g.scale {
          let ratio = g.scale / magnitude
          g.mean *= ratio
          g.m2 *= ratio * ratio
          g.scale = magnitude
        }
        let normalized = if g.scale == 0.0 { 0.0 } else { value / g.scale }
        let delta = normalized - g.mean
        g.mean += delta / g.usable.to_double()
        g.m2 += delta * (normalized - g.mean)
        g.minimum = Some(
          match g.minimum {
            Some(old) => if value < old { value } else { old }
            None => value
          },
        )
        g.maximum = Some(
          match g.maximum {
            Some(old) => if value > old { value } else { old }
            None => value
          },
        )
        if signature.low is Some(low) {
          if value < low || (value == low && !signature.low_equal) {
            g.below += 1
          }
        }
        if signature.high is Some(high) {
          if value > high || (value == high && !signature.high_equal) {
            g.above += 1
          }
        }
      }
    }
  }
  groups.map(fn(g) {
    let known = g.passed + g.failed
    let variance = if g.usable == 0 { 0.0 } else { g.m2 / g.usable.to_double() }
    let mean = g.mean * g.scale
    // Only finite rounding error can be clamped; nonfinite intermediates must
    // stay absent rather than turning an overflow into a fabricated zero SD.
    let sd = if variance.is_finite() {
      Some((if variance < 0.0 { 0.0 } else { variance }).sqrt() * g.scale)
    } else {
      None
    }
    {
      signature: g.signature,
      text: g.text,
      executions: g.executions,
      passed: g.passed,
      failed: g.failed,
      unknown: g.unknown,
      usable_samples: g.usable,
      excluded_samples: g.excluded,
      mean: if g.usable == 0 || !mean.is_finite() {
        None
      } else {
        Some(mean)
      },
      stddev: if g.usable == 0 {
        None
      } else {
        sd.filter(fn(v) { v.is_finite() })
      },
      minimum: g.minimum,
      maximum: g.maximum,
      below_limit: g.below,
      above_limit: g.above,
      failure_rate: if known == 0 {
        None
      } else {
        Some(g.failed.to_double() / known.to_double())
      },
    }
  })
}

///|
pub extend TestSignature with @debug.Debug::{to_repr}

///|
pub extend TestSignature with Eq::{equal, not_equal}

///|
pub extend TestSignature with Hash::{hash, hash_combine}

///|
pub extend TestStatistics with @debug.Debug::{to_repr}
