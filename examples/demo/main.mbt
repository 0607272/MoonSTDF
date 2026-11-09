///|
fn main {
  try {
    let a = @moonstdf.Analyzer::new()
    let f = @moonstdf.Framer::new()
    // Synthetic FAR plus one complete part observation. Missing MIR/MRR are
    // deliberately reported as diagnostics, never silently fabricated.
    for
      frame in f.feed(
        b"\x02\x00\x00\x0a\x02\x04\x02\x00\x05\x0a\x01\x01\x07\x00\x05\x14\x01\x01\x00\x00\x00\x01\x00",
      ) {
      a.accept(frame)
    }
    f.finish()
    println(@moonstdf.report_json(a.finish()))
  } catch {
    _ => abort("invalid built-in example")
  }
}
