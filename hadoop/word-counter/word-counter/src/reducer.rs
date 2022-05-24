extern crate efflux;

use efflux::prelude::{Context, Reducer};

fn main() {
    // simply run the reduction phase with our reducer
    efflux::run_reducer(WordcountReducer);
}

/// Simple struct to represent a word counter reducer.
struct WordcountReducer;

// Reducing stage implementation.
impl Reducer for WordcountReducer {
    fn reduce(&mut self, key: &[u8], values: &[&[u8]], ctx: &mut Context) {
        // base counter
        let mut count = 0;

        for value in values {
            // parse each value sum them all to obtain total appearances
            let value = std::str::from_utf8(value);
            if value.is_err() {
                continue;
            }

            let value = value.unwrap().parse::<usize>();
            if value.is_err() {
                continue;
            }

            count += value.unwrap();
        }

        // write the word and the total count as bytes
        ctx.write(key, count.to_string().as_bytes());
    }
}
