#!/usr/bin/env bash

function compile() {
  SCHEDULE="schedule($1)"
  g++-11 measure.cpp -o build/measure -fopenmp -std=c++11 -DSCHEDULE=$SCHEDULE -DSCHEDULE_STR="\"$SCHEDULE\""
}

function run() {
  for threads in {1..8}; do
    ./build/measure --threads=$threads --size=$1 --repeat=$2
  done
}

SCHEDULES=(
  "static" 
  "static,1"
  "dynamic"
  "dynamic,size/(omp_get_num_threads()*100)"
  "guided"
)

echo "threads;size;schedule;time"
for schedule in ${SCHEDULES[@]}; do
  compile $schedule
  for size in 1000 100000 1000000; do
    run $size 100
  done
done

