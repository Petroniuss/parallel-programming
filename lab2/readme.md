# Lab 2

Chosen sizes:
- small:    40000000
- medium:   400000000
- big:      4000000000 6.7s on my local machine with 8 cores.

Let's try that or decrease the size of the problem.
Wall-time: 1h, rough estimate: 1m max on a single core 

## Compilation
`make`

## Run locally
`mpiexec -n 4 build/pi 4000000000`

## Run on vcluster
`mpiexec -machinefile ./vcluster-config/allnodes -np 12 ./build/pi 4000000000`

## Schedule a job on prometheus
But first verify that the script has a chance to work:
`srun --nodes=1 --ntasks=1 --time=00:5:00 --partition=plgrid --account=plgmpr22 --pty /bin/bash`
`sbatch run.sh`
