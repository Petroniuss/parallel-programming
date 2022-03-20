#include <stdio.h>
#include <string.h>
#include <mpi.h>
#include <stdlib.h>

int main (int argc, char * argv[]) {
    MPI_Init(&argc, &argv);  
    int world_rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    int world_size;
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    int ping_pong_count = 0;
    int partner_rank = (world_rank + 1) % 2;

    if (world_rank == ping_pong_count % 2) {

        char* message = "This is the message!";
        MPI_Ssend(message, strlen(message), MPI_CHAR, partner_rank, 0, MPI_COMM_WORLD);
        printf("sent: %s\n", message);
    } else {
        int receive_buffer_size = 50;
        char* receive_buffer = malloc(sizeof(char) * receive_buffer_size);
        MPI_Recv(receive_buffer, receive_buffer_size, MPI_CHAR, partner_rank, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("received: %s\n", receive_buffer);
    }

    MPI_Finalize();
    return 0;
}
