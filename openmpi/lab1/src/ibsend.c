#include <mpi.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef DEBUG
#define DEBUG_PRINTF(...) printf(__VA_ARGS__)
#else
#define DEBUG_PRINTF(...)                                                      \
  do {                                                                         \
  } while (0)
#endif

#define INFO_PRINTF(...)                                                       \
  do {                                                                         \
    printf("INFO: "__VA_ARGS__);                                               \
    puts("");                                                                  \
  } while (0)

int message_id(int round_id, bool ping_message) {
  return round_id * 2 + ping_message;
}

char* allocate_n_bytes(int n_bytes) { return malloc(sizeof(char) * n_bytes); }

int compute_transferred_data_single_round_bytes(int message_size) {
  return 2 * message_size;
}

long int compute_rounds_count(long int n_bytes_to_transer, int message_size) {
  return n_bytes_to_transer /
         compute_transferred_data_single_round_bytes(message_size);
}

double compute_throughput_mbit_s(long int ping_pong_rounds, int message_size,
                                 double measured_time) {
  long int transfered_data_bytes =
      compute_transferred_data_single_round_bytes(message_size) *
      ping_pong_rounds;
  return ((transfered_data_bytes * 8) / 1e6) / measured_time;
}

int main(int argc, char* argv[]) {
  // mpi related
  MPI_Init(&argc, &argv);
  int world_rank;
  MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
  int world_size;
  MPI_Comm_size(MPI_COMM_WORLD, &world_size);

  // args,
  // - message_size in bytes
  // - data to be transferred in bytes
  // - output_file with measurements.
  int partner_rank = (world_rank + 1) % 2;
  int message_size_bytes = strtol(argv[1], NULL, 10);
  long int bytes_to_transfer = strtol(argv[2], NULL, 10);

  long int ping_pong_rounds =
      compute_rounds_count(bytes_to_transfer, message_size_bytes);

  char* data_file = argv[3];
  FILE* datafile_fp = fopen(data_file, "a+");

  // allocate buffer
  int buffer_attached_size =  sizeof(char) * message_size_bytes + MPI_BSEND_OVERHEAD;
  char* buffer_attached = allocate_n_bytes(buffer_attached_size);
  MPI_Buffer_attach(buffer_attached, buffer_attached_size);

  // master
  // send ping, receive pong
  if (world_rank == 0) {
    INFO_PRINTF(
        "Bytes to transfer: %ld, ping_pong_rounds: %ld, message_size: %d",
        bytes_to_transfer, ping_pong_rounds, message_size_bytes);
    int ping_buffer_size = message_size_bytes;
    char* ping_message = allocate_n_bytes(message_size_bytes);
    int pong_buffer_size = message_size_bytes;
    char* pong_buffer = allocate_n_bytes(message_size_bytes);

    // synchronization
    MPI_Barrier(MPI_COMM_WORLD);
    double start_wtime = MPI_Wtime();
    long int round_id;
    for (round_id = 0; round_id < ping_pong_rounds; round_id++) {
      MPI_Request request;
      ping_message[round_id % message_size_bytes] = (char) rand();
      MPI_Ibsend(ping_message, ping_buffer_size, MPI_CHAR, partner_rank,
               message_id(round_id, true), MPI_COMM_WORLD, &request);
      DEBUG_PRINTF("Round: %ld, sent: %s\n", round_id, ping_message);

      MPI_Recv(pong_buffer, pong_buffer_size, MPI_CHAR, partner_rank,
               message_id(round_id, false), MPI_COMM_WORLD, MPI_STATUS_IGNORE);
      DEBUG_PRINTF("Round: %ld, received: %s\n", round_id, pong_buffer);

      // Let's wait for the MPI_Ibsend to complete before progressing further.
      // Should reutrn immediatly in our case since message must've been sent at this point.
      MPI_Wait(&request, MPI_STATUS_IGNORE);
      // Detach the buffer. It blocks until all messages stored are sent.
      MPI_Buffer_detach(&buffer_attached, &buffer_attached_size);
      // reattach the buffer.
      MPI_Buffer_attach(buffer_attached, buffer_attached_size);
    }

    double end_wtime = MPI_Wtime();
    double measured_time = end_wtime - start_wtime;

    double throughput = compute_throughput_mbit_s(
        ping_pong_rounds, message_size_bytes, measured_time);
    INFO_PRINTF("Measured_time: %.6fs, Throughput: %.6f[Mbit/s]", measured_time,
                throughput);
    fprintf(datafile_fp, "%d %.6f\n", message_size_bytes, throughput);

    // slave
    // receive ping, send back pong
  } else {
    int pong_buffer_size = message_size_bytes;
    char* pong_message = allocate_n_bytes(message_size_bytes);
    int ping_buffer_size = message_size_bytes;
    char* ping_buffer = allocate_n_bytes(message_size_bytes);

    // synchronization
    MPI_Barrier(MPI_COMM_WORLD);
    MPI_Request request;
    long int round_id;
    for (round_id = 0; round_id < ping_pong_rounds; round_id++) {
      if (round_id != 0) {
        // Let's wait for the MPI_Ibsend to complete before progressing further.
        // Should reutrn immediatly in our case since message must've been sent at this point.
        MPI_Wait(&request, MPI_STATUS_IGNORE);
        // Detach the buffer. It blocks until all messages stored are sent.
        MPI_Buffer_detach(&buffer_attached, &buffer_attached_size);
        // reattach the buffer.
        MPI_Buffer_attach(buffer_attached, buffer_attached_size);
      }
      MPI_Recv(ping_buffer, ping_buffer_size, MPI_CHAR, partner_rank,
               message_id(round_id, true), MPI_COMM_WORLD, MPI_STATUS_IGNORE);
      DEBUG_PRINTF("Round: %ld, received: %s\n", round_id, ping_buffer);

      pong_message[round_id % message_size_bytes] = ping_buffer[round_id % message_size_bytes];
      DEBUG_PRINTF("%c", pong_message[round_id % message_size_bytes]);
      MPI_Ibsend(pong_message, pong_buffer_size, MPI_CHAR, partner_rank,
               message_id(round_id, false), MPI_COMM_WORLD, &request);
      DEBUG_PRINTF("Round: %ld, sent: %s\n", round_id, pong_message);
    }
  }

  MPI_Finalize();
  return 0;
}
