///|
extern "js" fn args() -> FixedArray[String] =
  #|() => process.argv.slice(2)

///|
extern "js" fn open_file(path : String) -> Int32 =
  #|(p) => { try { return require('node:fs').openSync(p, 'r'); } catch(e) { process.stderr.write('MoonSTDF: cannot open '+p+': '+e.message+'\n'); process.exit(2); } }

///|
extern "js" fn read_chunk(fd : Int32) -> Bytes =
  #|(fd) => { try { const fs=require('node:fs'), b=Buffer.alloc(65536); const n=fs.readSync(fd,b,0,b.length,null); return new Uint8Array(b.buffer,b.byteOffset,n); } catch(e) { process.stderr.write('MoonSTDF: cannot read input: '+e.message+'\n'); process.exit(2); } }

///|
extern "js" fn close_file(fd : Int32) -> Unit =
  #|(fd) => { require('node:fs').closeSync(fd); }

///|
extern "js" fn write_output(path : String, content : String) -> Unit =
  #|(path,text) => { try { if(path==='-') process.stdout.write(text+(text.endsWith('\n')?'':'\n')); else require('node:fs').writeFileSync(path,text,'utf8'); } catch(e) { process.stderr.write('MoonSTDF: cannot write output: '+e.message+'\n'); process.exit(2); } }

///|
extern "js" fn fail(message : String) -> Unit =
  #|(message) => { process.stderr.write('MoonSTDF: '+message+'\n'); process.exitCode=2; }

///|
fn read_analysis(path : String) -> @moonstdf.Analysis raise @moonstdf.StdfError {
  let fd = open_file(path)
  defer close_file(fd)
  let framer = @moonstdf.Framer::new()
  let analyzer = @moonstdf.Analyzer::new()
  while true {
    let chunk = read_chunk(fd)
    if chunk.length() == 0 {
      break
    }
    for frame in framer.feed(chunk) {
      analyzer.accept(frame)
    }
  }
  framer.finish()
  analyzer.finish()
}

///|
extern "js" fn append_output(path : String, content : String) -> Unit =
  #|(p,s) => { try { if(p==='-') process.stdout.write(s+'\n'); else require('node:fs').appendFileSync(p,s+'\n','utf8'); } catch(e) { process.stderr.write('MoonSTDF: cannot write output: '+e.message+'\n'); process.exit(2); } }

///|
extern "js" fn invalid_validation() -> Unit =
  #|() => { process.exitCode=2; }

///|
extern "js" fn clear_output(path : String) -> Unit =
  #|(p) => { try { require('node:fs').writeFileSync(p,'','utf8'); } catch(e) { process.stderr.write('MoonSTDF: cannot write output: '+e.message+'\n'); process.exit(2); } }

///|
extern "js" fn same_file(a : String, b : String) -> Bool =
  #|(a,b) => { const fs=require('node:fs'), p=require('node:path'); if(p.resolve(a)===p.resolve(b))return true; try { const x=fs.statSync(a), y=fs.statSync(b); return x.dev===y.dev && x.ino===y.ino; } catch { return false; } }

///|
fn inspect_file(
  path : String,
  output : String,
  dump~ : Bool,
) -> Unit raise @moonstdf.StdfError {
  let fd = open_file(path)
  defer close_file(fd)
  let framer = @moonstdf.Framer::new()
  let validator = @moonstdf.V4Validator::new()
  if dump && output != "-" {
    clear_output(output)
  }
  while true {
    let chunk = read_chunk(fd)
    if chunk.length() == 0 {
      break
    }
    for frame in framer.feed(chunk) {
      if dump {
        append_output(output, @moonstdf.v4_record_json(frame))
      } else {
        validator.accept(frame)
      }
    }
  }
  framer.finish()
  if !dump {
    let report = validator.finish()
    write_output(output, @moonstdf.validation_json(report))
    if !report.valid {
      invalid_validation()
    }
  }
}

///|
fn usage() -> String {
  "MoonSTDF — offline STDF V4 decoding and analysis\nUsage:\n  dump FILE [--output PATH|-]       Full named fields as JSONL\n  validate FILE [--output PATH|-]   Structural and reference diagnostics\n  analyze FILE [--format json|csv|html] [--output PATH|-]\n      [--policy observations|first|last] [--identity coordinates|part-id]\n  compare BEFORE AFTER [--output PATH|-]\n  retest INITIAL RETEST [--identity coordinates|part-id] [--output PATH|-]\nCore limits: 256 MiB input and 1,000,000 records per file.\n"
}

///|
fn source_diagnostics(
  a : @moonstdf.Analysis,
  label : String,
) -> Array[@moonstdf.Diagnostic] {
  (a.diagnostics + @moonstdf.summary_diagnostics(a)).map(fn(d) {
    { ..d, message: label + ": " + d.message, }
  })
}

///|
fn run(argv : FixedArray[String]) -> Unit raise @moonstdf.StdfError {
  if argv.length() == 0 || argv[0] == "--help" || argv[0] == "-h" {
    write_output("-", usage())
    return
  }
  let command = argv[0]
  if command != "analyze" &&
    command != "compare" &&
    command != "retest" &&
    command != "dump" &&
    command != "validate" {
    fail("unknown command; use --help")
    return
  }
  let positional = []
  let mut format = "json"
  let mut output = "-"
  let mut policy = "observations"
  let mut identity = @moonstdf.WaferCoordinates
  let mut i = 1
  while i < argv.length() {
    let arg = argv[i]
    if arg.has_prefix("--") {
      if i + 1 >= argv.length() {
        fail("option requires value: " + arg)
        return
      }
      let value = argv[i + 1]
      match arg {
        "--format" => format = value
        "--output" => output = value
        "--policy" => policy = value
        "--identity" =>
          match value {
            "coordinates" => identity = @moonstdf.WaferCoordinates
            "part-id" => identity = @moonstdf.PartId
            _ => {
              fail("invalid identity")
              return
            }
          }
        _ => {
          fail("unknown option: " + arg)
          return
        }
      }
      i += 2
    } else {
      positional.push(arg)
      i += 1
    }
  }
  if format != "json" && format != "csv" && format != "html" {
    fail("format must be json, csv or html")
    return
  }
  if policy != "observations" && policy != "first" && policy != "last" {
    fail("invalid policy")
    return
  }
  let single = command == "analyze" ||
    command == "dump" ||
    command == "validate"
  let required = if single { 1 } else { 2 }
  if positional.length() != required {
    fail("wrong number of input files; use --help")
    return
  }
  if command != "analyze" && (format != "json" || policy != "observations") {
    fail(
      "compare/retest produce JSON and require explicit input selection before pairing",
    )
    return
  }
  if output != "-" && positional.any(fn(input) { same_file(input, output) }) {
    fail("output must differ from all input files")
    return
  }
  if command == "dump" || command == "validate" {
    inspect_file(positional[0], output, dump=command == "dump")
    return
  }
  let a = read_analysis(positional[0])
  if command == "analyze" {
    let selected = if policy == "observations" {
      a
    } else {
      let selection = @moonstdf.select_retests(
        a.parts,
        if policy == "first" {
          @moonstdf.First
        } else {
          @moonstdf.Last
        },
        identity,
      )
      // Raw file summaries describe all observations and are not comparable
      // with an explicitly selected effective-part population.
      {
        ..a,
        parts: selection.parts,
        diagnostics: a.diagnostics +
        selection.diagnostics +
        [
          {
            offset: 0,
            code: "retest-selection",
            message: "explicit " +
            policy +
            " policy; reported summary comparisons disabled",
          },
        ],
        summaries: [],
      }
    }
    let content = match format {
      "csv" => @moonstdf.parts_csv(selected.parts)
      "html" => @moonstdf.report_html(selected)
      _ => @moonstdf.report_json(selected)
    }
    write_output(output, content)
  } else {
    let b = read_analysis(positional[1])
    let source = source_diagnostics(a, "before") +
      source_diagnostics(b, "after")
    if command == "compare" {
      let comparison = @moonstdf.compare_batches(a.parts, b.parts)
      write_output(
        output,
        @moonstdf.comparison_json({
          ..comparison,
          diagnostics: source + comparison.diagnostics,
        }),
      )
    } else {
      let retest = @moonstdf.compare_retests(a.parts, b.parts, identity)
      write_output(
        output,
        @moonstdf.retest_json({
          ..retest,
          diagnostics: source + retest.diagnostics,
        }),
      )
    }
  }
}

///|
fn main {
  run(args()) catch {
    @moonstdf.StdfError(offset, message) => fail("offset \{offset}: " + message)
  }
}
