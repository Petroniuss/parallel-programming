#include <stdio.h>
#include <mpi.h>

int main (int argc, char * argv[]) {

    char message[] = "I was sent to you";

    MPI_Init (&argc, &argv);  /* starts MPI */

    int world_rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    int world_size;
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    int ping_pong_count = 0;
    int partner_rank = (world_rank + 1) % 2;

    if (world_rank == ping_pong_count % 2) {
        MPI_Ssend(&message, 1, MPI_CHAR, partner_rank, 0, MPI_COMM_WORLD);
        printf("sent: %s\n", message);
    } else {
        MPI_Recv(&message, 1, MPI_CHAR, partner_rank, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("received: %s\n", message);
    }

    MPI_Finalize();
    return 0;
}
