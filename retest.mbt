///|
/// Explicit identity policy; wafer coordinates require known lot AND wafer.
#derive(Debug, Eq)
pub(all) enum RetestIdentity {
  WaferCoordinates
  PartId
}

///|
/// First/last use source observation order, never timestamps or sorted site.
#derive(Debug, Eq)
pub(all) enum RetestPolicy {
  First
  Last
}

///|
#derive(Debug)
pub(all) struct RetestSelection {
  parts : Array[Part]
  diagnostics : Array[Diagnostic]
  duplicates : Int32
}

///|
#derive(Debug)
pub(all) struct BinTransition {
  before_bin : Int32
  after_bin : Int32
  count : Int32
}

///|
#derive(Debug)
pub(all) struct RetestReport {
  matched : Int32
  recovered : Int32
  still_failed : Int32
  regressed : Int32
  unknown : Int32
  ambiguous : Int32
  unmatched_before : Int32
  unmatched_after : Int32
  transitions : Array[BinTransition]
  diagnostics : Array[Diagnostic]
}

///|
/// Length prefixes avoid collisions when user-supplied IDs contain separators.
fn scoped_key(parts : Array[String]) -> String {
  let out = StringBuilder()
  for part in parts {
    out.write_string("\{part.length()}:\{part}")
  }
  out.to_string()
}

///|
fn retest_key(p : Part, identity : RetestIdentity) -> String? {
  if p.lot == "" {
    return None
  }
  match identity {
    WaferCoordinates =>
      match (p.wafer, p.result.x, p.result.y) {
        (Some(w), Some(x), Some(y)) if w != "" =>
          Some(scoped_key([p.lot, w, "\{x}", "\{y}"]))
        _ => None
      }
    PartId =>
      if p.result.part_id == "" {
        None
      } else {
        Some(scoped_key([p.lot, p.wafer.unwrap_or(""), p.result.part_id]))
      }
  }
}

///|
fn conflicting_ids(parts : Array[Part]) -> Bool {
  let ids : Map[String, Bool] = Map([])
  for p in parts {
    if p.result.part_id != "" {
      ids[p.result.part_id] = true
    }
  }
  ids.length() > 1
}

///| Explicit first/last selection. Missing or conflicting identities are retained

///|
/// with diagnostics; PART_FLG supersession is preserved but not automatically applied.
pub fn select_retests(
  parts : Array[Part],
  policy : RetestPolicy,
  identity : RetestIdentity,
) -> RetestSelection {
  let groups : Map[String, Array[Part]] = Map([])
  let order : Array[String] = []
  let diagnostics = []
  for p in parts {
    let key = match retest_key(p, identity) {
      Some(k) => k
      None => {
        diagnostics.push({
          offset: p.offset,
          code: "missing-retest-identity",
          message: "observation retained; required lot/wafer/coordinates or part ID missing",
        })
        "missing/\{order.length()}"
      }
    }
    if groups.get(key) is Some(group) {
      group.push(p)
    } else {
      groups[key] = [p]
      order.push(key)
    }
  }
  let selected = []
  let mut duplicates = 0
  for key in order {
    let group = groups[key]
    if identity == WaferCoordinates && conflicting_ids(group) {
      diagnostics.push({
        offset: group[0].offset,
        code: "ambiguous-retest-identity",
        message: "same wafer coordinates have conflicting explicit part IDs; all retained",
      })
      for p in group {
        selected.push(p)
      }
    } else {
      duplicates += group.length() - 1
      selected.push(
        if policy == First {
          group[0]
        } else {
          group[group.length() - 1]
        },
      )
    }
  }
  { parts: selected, diagnostics, duplicates, }
}

///|
fn identity_groups(
  parts : Array[Part],
  identity : RetestIdentity,
) -> (Map[String, Array[Part]], Int32) {
  let groups : Map[String, Array[Part]] = Map([])
  let mut missing = 0
  for p in parts {
    if retest_key(p, identity) is Some(key) {
      if groups.get(key) is Some(g) {
        g.push(p)
      } else {
        groups[key] = [p]
      }
    } else {
      missing += 1
    }
  }
  (groups, missing)
}

///| Pair two files only when each identity is unique on both sides. Duplicate

///|
/// identities require explicit prior first/last selection; they are not guessed.
pub fn compare_retests(
  before : Array[Part],
  after : Array[Part],
  identity : RetestIdentity,
) -> RetestReport {
  let (left, missing_left) = identity_groups(before, identity)
  let (right, missing_right) = identity_groups(after, identity)
  let mut matched = 0
  let mut recovered = 0
  let mut still_failed = 0
  let mut regressed = 0
  let mut unknown = 0
  let mut ambiguous = 0
  let mut unmatched_before = missing_left
  let mut unmatched_after = missing_right
  let transitions : Array[BinTransition] = []
  let bins : Map[String, Int32] = Map([])
  let diagnostics = []
  let keys = left.keys().collect()
  keys.sort()
  for key in keys {
    let a = left[key]
    if right.get(key) is Some(b) {
      if a.length() != 1 ||
        b.length() != 1 ||
        (identity == WaferCoordinates && conflicting_ids([a[0], b[0]])) {
        ambiguous += 1
        diagnostics.push({
          offset: a[0].offset,
          code: "ambiguous-retest-identity",
          message: "cross-file match not unique or explicit IDs conflict",
        })
        continue
      }
      matched += 1
      let x = a[0].result
      let y = b[0].result
      if x.abnormal ||
        y.abnormal ||
        x.outcome == Unknown ||
        y.outcome == Unknown {
        unknown += 1
      } else if x.outcome == Fail && y.outcome == Pass {
        recovered += 1
      } else if x.outcome == Fail && y.outcome == Fail {
        still_failed += 1
      } else if x.outcome == Pass && y.outcome == Fail {
        regressed += 1
      }
      let bin = pair_key(x.hard_bin, y.hard_bin)
      if bins.get(bin) is Some(index) {
        let old = transitions[index]
        transitions[index] = { ..old, count: old.count + 1, }
      } else {
        bins[bin] = transitions.length()
        transitions.push({
          before_bin: x.hard_bin,
          after_bin: y.hard_bin,
          count: 1,
        })
      }
    } else {
      unmatched_before += a.length()
    }
  }
  for key, group in right {
    if !left.contains(key) {
      unmatched_after += group.length()
    }
  }
  if missing_left + missing_right > 0 {
    diagnostics.push({
      offset: 0,
      code: "missing-retest-identity",
      message: "missing identities counted as unmatched",
    })
  }
  {
    matched,
    recovered,
    still_failed,
    regressed,
    unknown,
    ambiguous,
    unmatched_before,
    unmatched_after,
    transitions,
    diagnostics,
  }
}

///|
pub extend RetestIdentity with @debug.Debug::{to_repr}

///|
pub extend RetestIdentity with Eq::{equal, not_equal}

///|
pub extend RetestPolicy with @debug.Debug::{to_repr}

///|
pub extend RetestPolicy with Eq::{equal, not_equal}

///|
pub extend RetestSelection with @debug.Debug::{to_repr}

///|
pub extend BinTransition with @debug.Debug::{to_repr}

///|
pub extend RetestReport with @debug.Debug::{to_repr}
