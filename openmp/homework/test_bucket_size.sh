#!/bin/bash

`make clean`
`make all`

if [ $# -eq 1 ];
then
    THREADS=1
else 
    THREADS=$2
fi
SIZE=100000000
VERSION=$1

mkdir results/bucket_size
echo "size;generating;splitting;sorting;writing;overall" > results/bucket_size/res_${VERSION}.tsv

for i in {1..100}
do
    `./build/measure --threads=${THREADS} --size=${SIZE} --repeat=1 --version=${VERSION} --bucket-size=${i} --log-format=1 >>  results/bucket_size/res_${VERSION}.tsv`
done
