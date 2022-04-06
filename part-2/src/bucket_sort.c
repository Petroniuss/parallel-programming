#include <omp.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main () {
    int nthreads, tid;
    int LIMIT = 100000000;
    int* array = malloc(sizeof(int) * LIMIT);

    double time = omp_get_wtime();
    int chunk = LIMIT / omp_get_num_threads();
    unsigned short xi[3];
    #pragma omp parallel private(xi, tid, nthreads) shared(chunk, array) 
    {
        tid = omp_get_thread_num();
        xi[0] = tid;
        xi[1] = tid ^ 11;
        xi[2] = tid ^ 111;
        nthreads = omp_get_num_threads();

        int i;

        // #pragma omp for 
        // for (i = 0; i < LIMIT; i++) {
        //     array[i] = erand48(xi);
        // }

        for (i = tid; i < LIMIT; i += nthreads) {
            array[i] = erand48(xi);
        }
    } 

    int i;
    for (i = 0; i < LIMIT; i++) {
        printf("array[%d]: %d\n", i, array[i]);
    }

    double total_time = omp_get_wtime() - time;
    printf("Time: %f \n", total_time);
    return 0;
} 
