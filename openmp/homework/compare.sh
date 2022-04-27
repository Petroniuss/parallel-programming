#!/bin/bash

make clean
make all

size=10000000

mkdir -p results/comparision

function measure_alg() {
  res_file="results/comparision/res.tsv"
  echo "bucket_size;threads;algorithm;generating;splitting;sorting;writing;overall" > "$res_file"
  for i in {1..8}; do
        ./build/measure --threads="${i}" --size="${size}" --repeat=1 --version=1 --bucket-size=10 | tee -a "$res_file"
        ./build/measure --threads="${i}" --size="${size}" --repeat=1 --version=3 --bucket-size=10 | tee -a "$res_file"
        ./build/measure --threads="${i}" --size="${size}" --repeat=1 --version=1 --bucket-size=50 | tee -a "$res_file"
        ./build/measure --threads="${i}" --size="${size}" --repeat=1 --version=3 --bucket-size=50 | tee -a "$res_file"
  done
}

measure_alg
