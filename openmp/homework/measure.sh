#!/bin/bash

make clean
make all

size=15000000
res_3="results/alg_3.tsv"

# size=150000
mkdir -p results
rm "$res_3"

# ./build/measure --threads="8" --size="100000" --repeat=1 -g > "results/generated_data.tsv"

function header() {
  echo "bucket_size;threads;algorithm;generating;splitting;sorting;writing;overall"
}

header | tee -a results/res_3.tsv

for i in {1..8}; do
  ./build/measure --threads="${i}" --size="${size}" --repeat=3 --version=3 --log-format=1 --bucket-size=20 | tee -a "$res_3"
done
