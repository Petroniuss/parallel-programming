#include <vector>
#include <random>
#include <cstdio>
#include <omp.h>
#include <algorithm>
#include <iostream>
#include "argh/argh.h"

#define timeit(f) ({ double __time0 = omp_get_wtime(); f; omp_get_wtime() - __time0; })

#ifndef SCHEDULE
#define SCHEDULE schedule(static)
#endif

int param_threads = 1,
    param_size = 1e6,
    param_repeat = 1;

template<int min=0, int max=1>
void uniform_fill(std::vector<double>& array) {
  #pragma omp parallel num_threads(param_threads)
  {
    std::uniform_real_distribution<double> distribution(min, max);
    std::default_random_engine generator; 
    int t_thread = omp_get_thread_num();
    generator.seed(t_thread * time(NULL) + 17);
    
    #pragma omp for SCHEDULE
    for (int i = 0; i < array.size(); i++) {
      array[i] = distribution(generator);
    }
  }
}

template<int max=1>
void sequential_sort(std::vector<double>& array, int no_buckets) {
  std::vector<std::vector<double>> buckets(no_buckets);

  for (int i = 0; i < array.size(); i++) {
    int bucket_index = std::min((int) (no_buckets * array[i] / max), no_buckets - 1);
    buckets[bucket_index].push_back(array[i]);
  }

  for (int i = 0; i < buckets.size(); i++) {
    sort(buckets[i].begin(), buckets[i].end());
  }

  int array_idx = 0;
  for (int i = 0; i < buckets.size(); i++) {
    for (int j = 0; j < buckets[i].size(); j++) {
      array[array_idx] = buckets[i][j];
      array_idx++;
    }
  }
}

// algorithm #1
// vectors of buckets
// each thread has its own buckets
// each thread iterates over entire array.
// each param_threads sorts its own buckets//

// at the end all param_threads must join
// and each thread in parallel wrties the result.
template<int max=1>
void bucket_sort(std::vector<double>& array, int no_buckets) {
  std::vector<std::vector<double>> buckets(no_buckets);

  double buckets_per_thread = no_buckets / param_threads;

  #pragma omp parallel shared(buckets) num_threads(threads)
  {
    int tid = omp_get_thread_num();
    for (int i = 0; i < array.size(); i++) {
      int bucket_index = std::min((int) (no_buckets * array[i] / max), no_buckets - 1);

      // figure out which index is mine.
      if ( (tid) * buckets_per_thread <= bucket_index && bucket_index <= (tid + 1) * buckets_per_thread) {
        buckets[bucket_index].push_back(array[i]);
      }
    }
  }

  // for (int i = 0; i < buckets.size(); i++) {
  //   sort(buckets[i].begin(), buckets[i].end());
  // }

  // int array_idx = 0;
  // for (int i = 0; i < buckets.size(); i++) {
  //   for (int j = 0; j < buckets[i].size(); j++) {
  //     array[array_idx] = buckets[i][j];
  //     array_idx++;
  //   }
  // }

//   #pragma omp parallel shared(thread_buckets) num_threads(param_threads)
//   {
//     int thread_id = omp_get_thread_num();

//     #pragma omp for SCHEDULE
//     for (int i = 0; i < no_buckets; i++) {
//       thread_buckets[thread_id]
//       thread_buckets[thread_id][i].push_back(std::vector<double>());
//     }

//     // #pragma omp for SCHEDULE
//     // for (int i = 0; i < size; i++) {
//     //   // compute index of a bucket
//     //   int bucket_index = n * array[i] / max;
//     //   thread_buckets[bucket_index].push_back(array[i]);
//     //   // array[i] = distribution(generator);
//     // }
}

void verify(std::vector<double>& supposedly_sorted, std::vector<double>& original) {
  std::sort(original.begin(), original.end());

  bool are_equal = supposedly_sorted == original;
  // std::cout << "Verified: " << are_equal << std::endl;
  // for (int i = 0; i < size; i++) {
  //   printf("%f, %f\n", supposedly_sorted[i], original[i]);
  // }
}

int main(int argc, char* argv[]) {
  argh::parser cmdl(argv);

  cmdl({ "-t", "--param_threads"}) >> param_threads;
  cmdl({ "-s", "--size" }) >> param_size;
  cmdl({ "-r", "--param_repeat" }) >> param_repeat;

  std::vector<double> data(param_size);

  for (int i = 0; i < param_repeat; i++) {
    double fill_time_0 = omp_get_wtime();
    uniform_fill(data);
    double fill_time = omp_get_wtime() - fill_time_0;
    std::vector<double> original = data;
    // for (int i = 0; i < size; i++) {
    //   printf("%f, %f\n", data[i], original[i]);
    // }
    double bucket_sort_1 = omp_get_wtime();
    bucket_sort(data, 8);
    double bucket_sort_time = omp_get_wtime() - bucket_sort_1;
    verify(data, original);
    printf("fill_time, bucket_time\n");
    printf("%lf, %lf\n", fill_time, bucket_sort_time);
  }
}

// parallel decomposition to buckets.




// template<int min=0, int max=1>
// std::vector<double>& bucket_sort(std::vector<double>& array, int no_buckets) {

//   // create buckets shared accross param_threads.
//   std::vector<std::vector<std::vector<double>>> thread_buckets(param_threads);

//   #pragma omp parallel shared(thread_buckets) num_threads(param_threads)
//   {
//     int thread_id = omp_get_thread_num();

//     #pragma omp for SCHEDULE
//     for (int i = 0; i < no_buckets; i++) {
//       thread_buckets[thread_id]
//       thread_buckets[thread_id][i].push_back(std::vector<double>());
//     }

//     // #pragma omp for SCHEDULE
//     // for (int i = 0; i < size; i++) {
//     //   // compute index of a bucket
//     //   int bucket_index = n * array[i] / max;
//     //   thread_buckets[bucket_index].push_back(array[i]);
//     //   // array[i] = distribution(generator);
//     // }
//   }


  // we could create a lock per bucket.

//   for (int i = 0; i < no_buckets; i++) {
//     printf("%d\n", thread_buckets[i].size());
//   }
// }