#!/bin/bash

`make clean`
`make all`

if [ $# -eq 0 ];
then
    SIZE=15000000
else 
    SIZE=$1
fi

mkdir results
truncate -s 0 results/res_1_${SIZE}.tsv
truncate -s 0 results/res_2_${SIZE}.tsv

for i in {1..8}
do
    `./build/measure --threads=${i} --size=${SIZE} --repeat=1 --version=1 >>  results/res_1_${SIZE}.tsv`
    `./build/measure --threads=${i} --size=${SIZE} --repeat=1 --version=2 >>  results/res_2_${SIZE}.tsv`

done

`python3 plots.py ${SIZE} 1,2`
