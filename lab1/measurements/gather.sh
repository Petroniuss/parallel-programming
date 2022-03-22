#!/bin/bash

# fun stuff.
# for pathname in ./**/*.dat; do
#     dir=${pathname%/*}
#     name=${pathname##*/}
#     new_name="${name%%.*}.csv"
#     awk -v OFS=, '{$1=$1}1' "$pathname" > "$dir/$new_name"
# done

cd first-run

cat ibsend_single_node-*.csv > ../csv/ibsend_single_node.csv
cat ibsend_two_nodes-*.csv > ../csv/ibsend_two_nodes.csv
cat ssend_single_node-*.csv > ../csv/ssend_single_node.csv
cat ssend_two_nodes-*.csv > ../csv/ssend_two_nodes.csv

cd ..