///|
extern "js" fn register(
  inspect : (Bytes) -> String,
  html : (Bytes) -> String,
) -> Unit =
  #|(inspect, html) => { globalThis.MoonSTDF = Object.freeze({inspect,html}); }

///|
fn inspect(data : Bytes) -> String {
  @moonstdf.report_json(@moonstdf.analyze(data)) catch {
    @moonstdf.StdfError(offset, message) => {
      let error : Json = {
        "error": @json.to_json(message),
        "offset": @json.to_json(offset),
      }
      error.stringify()
    }
  }
}

///|
fn html(data : Bytes) -> String {
  @moonstdf.report_html(@moonstdf.analyze(data)) catch {
    _ =>
      "<!doctype html><meta charset=utf-8><p>Unable to parse input. Read the error next to the file selector.</p>"
  }
}

///|
fn main {
  register(inspect, html)
}
