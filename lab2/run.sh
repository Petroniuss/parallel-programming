#!/bin/bash -l
#SBATCH --nodes 1
#SBATCH --ntasks 12
#SBATCH --time=01:00:00
#SBATCH --partition=plgrid-short
#SBATCH --account=plgmpr22
#SBATCH --sockets-per-node=2

module add plgrid/tools/openmpi

40000000
400000000
4000000000
# run 
for repeat in {1..20}; do
	for points in {400000,4000000,40000000}; do
		for nodes in {1..12}; do
			mpiexec -np $nodes ./src/pi $points | tee -a data/data.csv
		done
	done
done

