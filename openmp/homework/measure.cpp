#include <vector>
#include <random>
#include <cstdio>
#include <omp.h>
#include <algorithm>
#include <iostream>
#include "argh/argh.h"

#ifndef SCHEDULE
#define SCHEDULE schedule(static)
#endif

#ifndef DEBUG
#define DEBUG true
#endif

template<bool B>
void log(const char* format, ...) {}

template<>
void log<true>(const char* format, ...) {
  va_list argptr;
  va_start(argptr, format);
  vprintf(format, argptr);
  va_end(argptr);
}

template<bool B>
void log(const std::vector<double>& array) {}

template<>
void log<true>(const std::vector<double>& array) {
  printf("[ ");
  for (auto e : array) {
	printf("%.2f ", e);
  }
  printf(" ]\n");
}

int param_threads = 1,
	param_size = 1e6,
	param_repeat = 1;

template<int min = 0, int max = 1>
void uniform_fill(std::vector<double>& array) {
#pragma omp parallel num_threads(param_threads)
  {
	std::uniform_real_distribution<double> distribution(min, max);
	std::default_random_engine generator;
	int t_thread = omp_get_thread_num();
	int threads_num = omp_get_num_threads();
	generator.seed(t_thread * time(NULL) + 17);

#pragma omp for SCHEDULE
	for (int i = 0; i < array.size(); i++) {
	  array[i] = distribution(generator);
	}
  }
}

template<typename Function>
double timeit(Function&& timed_function) {
  double time_0 = omp_get_wtime();
  timed_function();
  return omp_get_wtime() - time_0;
}

void verify(const std::vector<double>& supposedly_sorted, const std::vector<double>& original) {
  auto original_sorted = original;
  std::sort(original_sorted.begin(), original_sorted.end());
  bool are_equal = supposedly_sorted == original_sorted;
  if (!are_equal) {
	log<DEBUG>("Verification failed (top - expected, bottom - actual)\n");
	log<DEBUG>(original_sorted);
	log<DEBUG>(supposedly_sorted);
  }
}

template<int max = 1>
void sequential_sort(std::vector<double>& array, int no_buckets) {
  std::vector<std::vector<double>> buckets(no_buckets);

  for (int i = 0; i < array.size(); i++) {
	int bucket_index = std::min((int)(no_buckets * array[i] / max), no_buckets - 1);
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
template<int max = 1>
void bucket_sort(std::vector<double>& array, int no_buckets) {
  std::vector<std::vector<double>> buckets(no_buckets);

  double buckets_per_thread = no_buckets / param_threads;

#pragma omp parallel shared(buckets) num_threads(param_threads)
  {
	int tid = omp_get_thread_num();
	for (int i = 0; i < array.size(); i++) {
	  int bucket_index = std::min((int)(no_buckets * array[i] / max), no_buckets - 1);

	  // figure out which index is mine.
	  if ((tid) * buckets_per_thread <= bucket_index && bucket_index <= (tid + 1) * buckets_per_thread) {
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


int main(int argc, char* argv[]) {
  argh::parser cmdl(argv);

  cmdl({"-t", "--threads"}) >> param_threads;
  cmdl({"-s", "--size"}) >> param_size;
  cmdl({"-r", "--repeat"}) >> param_repeat;

  for (int i = 0; i < param_repeat; i++) {
	std::vector<double> data(param_size);

	// 1. Generate data
	double fill_time = timeit([&] {
	  uniform_fill(data);
	});
	auto data_copy = data;
	log<DEBUG>("fill_time: %lfs\n", fill_time);

	// 2. Sort
	double sort_time = timeit([&] {
	  sequential_sort(data, 10);
	});

	log<DEBUG>("sort_time: %lfs\n", sort_time);

	// 3. Verify
	verify(data, data_copy);
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