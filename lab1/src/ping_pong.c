#include <mpi.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef DEBUG
    #define DEBUG_PRINTF(...) printf(__VA_ARGS__)
#else
    #define DEBUG_PRINTF(...) do {} while (0)
#endif

#define INFO_PRINTF(...) do { printf("INFO: "__VA_ARGS__); puts(""); } while (0)

int message_id(int round_id, bool ping_message) {
  return round_id * 2 + ping_message;
}

int main(int argc, char* argv[]) {
  MPI_Init(&argc, &argv);
  int world_rank;
  MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
  int world_size;
  MPI_Comm_size(MPI_COMM_WORLD, &world_size);

  int partner_rank = (world_rank + 1) % 2;
  long int n = strtol(argv[1], NULL, 10);
  char* data_file = argv[2];

  FILE* datafile_fp = fopen(data_file, "a+");

  // master
  // send ping, receive pong
  if (world_rank == 0) {
    INFO_PRINTF("n: %ld", n);
    char* ping_message = "ping";
    int pong_buffer_size = 64;
    char* pong_buffer = malloc(sizeof(char) * pong_buffer_size);

    // synchronization
    MPI_Barrier(MPI_COMM_WORLD);
    double start_wtime = MPI_Wtime();
    for (long int round_id = 0; round_id < n; round_id++) {
      MPI_Ssend(ping_message, strlen(ping_message) + 1, MPI_CHAR, partner_rank,
                message_id(round_id, true), MPI_COMM_WORLD);
      DEBUG_PRINTF("Round: %ld, sent: %s\n", round_id, ping_message);
      MPI_Recv(pong_buffer, pong_buffer_size, MPI_CHAR, partner_rank, message_id(round_id, false),
              MPI_COMM_WORLD, MPI_STATUS_IGNORE);
      DEBUG_PRINTF("Round: %ld, received: %s\n", round_id, pong_buffer);
    }
    double end_wtime = MPI_Wtime();
    double measured_time = end_wtime - start_wtime;
    INFO_PRINTF("Measured time: %.6fs", measured_time);
    fprintf(datafile_fp, "%ld %f\n", n, measured_time);

  // slave
  // receive ping, send back pong
  } else {
    char* pong_message = "pong";
    int ping_buffer_size = 64;
    char* ping_buffer = malloc(sizeof(char) * ping_buffer_size);

    // synchronization
    MPI_Barrier(MPI_COMM_WORLD);
    for (long int round_id = 0; round_id < n; round_id++) {
      MPI_Recv(ping_buffer, ping_buffer_size, MPI_CHAR, partner_rank, message_id(round_id, true),
              MPI_COMM_WORLD, MPI_STATUS_IGNORE);
      DEBUG_PRINTF("Round: %ld, received: %s\n", round_id, ping_buffer);
      MPI_Ssend(pong_message, strlen(pong_message) + 1, MPI_CHAR, partner_rank,
                message_id(round_id, false), MPI_COMM_WORLD);
      DEBUG_PRINTF("Round: %ld, sent: %s\n", round_id, pong_message);
    }
  }

  MPI_Finalize();
  return 0;
}
