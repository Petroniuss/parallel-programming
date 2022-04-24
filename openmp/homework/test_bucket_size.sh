#!/bin/bash

make clean
make all

threads=1
size=1000000

function measure_alg() {
  version=$1
  res_file="results/bucket_size/res_${version}.tsv"
  echo "bucket_size;threads;algorithm;generating;splitting;sorting;writing;overall" >"$res_file"
  for i in {1..100}; do
    ./build/measure --threads="${threads}" --size="${size}" --repeat=3 --version="${version}" --bucket-size="${i}" | tee -a "$res_file"
  done
}

mkdir -p results/bucket_size
measure_alg 3
