#include <float.h>
#include <math.h>
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#define TIME_SEED time(NULL)

long int compute_points_within(long long int n) {
  long long int i, count;
  double x, y, z;
  count = 0;
  for (i = 0; i < n; ++i) {
    x = (double)rand() / RAND_MAX;
    y = (double)rand() / RAND_MAX;
    z = x * x + y * y;
    if (z <= 1) {
      count++;
    }
  }

  return count;
}

/*
    Useful mpi functions:
        - Scatter - divides data (we have almost no data to scatter)
        - Gather - gathers data to  (we don't need to gather ourselves)
        - Reduce - sums all the data. (we need master which will hold the
   reduced data)
*/

int main(int argc, char* argv[]) {
  MPI_Init(&argc, &argv);

  int rank, n_nodes, seed;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &n_nodes);
  seed = TIME_SEED + rank * n_nodes;
  srand(seed);

  long long int n_points;
  n_points = strtoll(argv[1], NULL, 10);

  MPI_Barrier(MPI_COMM_WORLD);
  double start_time = MPI_Wtime();
  long long int local_n_points = n_points / n_nodes;
  long long int local_within = compute_points_within(local_n_points);
  long long int total_within;
  MPI_Reduce(&local_within, &total_within, 1, MPI_LONG_LONG_INT, MPI_SUM, 0,
             MPI_COMM_WORLD);
  if (rank == 0) {
    double pi = (((double)total_within) / n_points) * 4;
    double time = MPI_Wtime() - start_time;
    printf("%d,%.*f,%.*f,%lld,%lld\n", n_nodes, DBL_DECIMAL_DIG, pi,
           DBL_DECIMAL_DIG, time, n_points, total_within);
  }

  MPI_Finalize();
  return 0;
}