mod glob;
mod shell;

use std::io::{self, BufRead, Write};

use serde::Deserialize;
use serde_json::{Value, json};

#[derive(Deserialize)]
struct Request {
    id: Value,
    op: String,
    params: Value,
}

fn main() -> io::Result<()> {
    // One native host belongs to one tool session. Ordered requests preserve
    // the shell's real retained state; engine diagnostics use stderr only.
    let input = io::stdin();
    let mut output = io::BufWriter::new(io::stdout().lock());
    let mut line = String::new();
    let mut reader = input.lock();

    while reader.read_line(&mut line)? != 0 {
        let response = match serde_json::from_str::<Request>(&line) {
            Ok(request) => {
                let result = match request.op.as_str() {
                    "glob" => glob::run(request.params),
                    "shell" => shell::run(request.params),
                    _ => Err(format!("unknown engine operation: {}", request.op)),
                };

                match result {
                    Ok(value) => json!({"id": request.id, "output": value}),
                    Err(message) => json!({"id": request.id, "error": message}),
                }
            }
            Err(error) => json!({"id": null, "error": error.to_string()}),
        };

        serde_json::to_writer(&mut output, &response)?;
        output.write_all(b"\n")?;
        output.flush()?;
        line.clear();
    }

    Ok(())
}
