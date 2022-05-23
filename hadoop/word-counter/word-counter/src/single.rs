use std::collections::HashMap;
use std::io;
use std::io::{BufRead, Write};

fn main() {
    let stdin = io::stdin();
    let mut map = HashMap::new();
    let mut lines = stdin.lock().lines();

    while let Some(line) = lines.next() {
        let value = line.unwrap();

        // trim whitespaces
        let trimmed = value.trim();

        // split on spaces to find words
        for word in trimmed.split(" ") {
            *map.entry(word.to_string()).or_insert(0) += 1;
        }
    }

    let stdout = io::stdout();
    let mut handle = stdout.lock();

    for (key, value) in map.into_iter() {
        let _ = handle.write(key.as_bytes());
        let _ = handle.write(b" : ");
        let _ = handle.write(value.to_string().as_bytes());
        let _ = handle.write(b"\n");
    }
}
