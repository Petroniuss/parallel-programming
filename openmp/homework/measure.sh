#!/bin/bash

make clean
make all

size=10000000

mkdir -p results/algorithm

function measure_alg() {
  version=$1
  res_file="results/algorithm/res_${version}.tsv"
  echo "bucket_size;threads;algorithm;generating;splitting;sorting;writing;overall" > "$res_file"
  for i in {1..8}; do
    ./build/measure --threads="${i}" --size="${size}" --repeat=3 --version="$version" --bucket-size=50 | tee -a "$res_file"
  done
}

measure_alg 3
