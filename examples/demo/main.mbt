///|
fn main {
  try {
    let a = @moonstdf.Analyzer::new()
    let f = @moonstdf.Framer::new()
    let validator = @moonstdf.V4Validator::new()
    // Original complete minimal file: FAR, MIR, PIR, PRR, PCR, MRR.
    // Chunk boundaries are independent of record boundaries.
    let chunks : Array[Bytes] = [
      b"\x02\x00\x00", b"\x0a\x02\x04\x19\x00\x01\x0a\x00\x00\x00\x00\x00\x00\x00\x00\x01P  \xff\xff \x01L\x01D\x01N\x01T\x01J",
      b"\x02\x00\x05\x0a\x01\x01\x07\x00\x05\x14\x01\x01\x00\x00\x00\x01\x00", b"\x06\x00\x01\x1e\xff\xff\x01\x00\x00\x00\x04\x00\x01\x14\x00\x00\x00\x00",
    ]
    for chunk in chunks {
      for frame in f.feed(chunk) {
        let record = @moonstdf.decode_v4_record(frame).unwrap()
        if record.name == "MIR" && record.field("LOT_ID") is None {
          abort("missing named field")
        }
        validator.accept(frame)
        a.accept(frame)
      }
    }
    f.finish()
    if !validator.finish().valid {
      abort("invalid built-in V4 file")
    }
    println(@moonstdf.report_json(a.finish()))
  } catch {
    _ => abort("invalid built-in example")
  }
}
