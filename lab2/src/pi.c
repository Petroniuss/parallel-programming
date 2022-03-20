#include <mpi.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>
#define TIME_SEED time(NULL)

double compute_pi(long int n) {
    long int i, count;
    double x, y, z, pi;

    count = 0;
    for(i = 0; i < n; ++i) {
        x = (double)rand() / RAND_MAX;
        y = (double)rand() / RAND_MAX;
        z = x * x + y * y;
        if( z <= 1 ) { 
            count++;
        }
    }

    pi = (double) count / n * 4;
    return pi;
}

/*
    Useful mpi functions:
        - Scatter - divides data ( we have no data to scatter)
        - Gather - gathers data to  (we don't need to gather ourselves)
        - Reduce - sums all the data. (we need master which reduces the data)
*/

int main(int argc, char* argv[]) {
    MPI_Init(&argc, &argv);

    int rank, numprocs, seed;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &numprocs);
    seed = TIME_SEED + rank * numprocs;
    srand(seed);
    printf("node_info: { rank: %d, size: %d, seed: %d }\n", rank, numprocs, seed);

    long int n_points;
    n_points = strtol(argv[1], NULL, 10);

    printf("n_points: %li\n", n_points);
    double computed_pi = compute_pi(n_points);
    printf("computed_pi: %f\n", computed_pi);

    MPI_Finalize();

    return 0;
}