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

#ifndef INFO
#define INFO true
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

template<bool B>
void log(const std::vector<std::vector<double>>& array) {}

template<>
void log<true>(const std::vector<std::vector<double>>& array) {
  printf("[ ");
  for (auto bucket : array) {
	log<DEBUG>(bucket);
  }
  printf(" ]\n");
}

int param_threads = 1,
	param_size = 1e6,
	param_repeat = 1,
	param_algorithm_version = 1;

template<int min = 0, int max = 1>
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

struct Measurement {
  double rand_gen_time = 0.;
  double split_to_buckets_time = 0.;
  double sort_buckets_time = 0.;
  double write_sorted_buckets_time = 0.;
  double sort_time = 0.;
};

template<typename Function>
double inline timeit(Function&& timed_function) {
  double time_0 = omp_get_wtime();
  timed_function();
  return omp_get_wtime() - time_0;
}

void verify(const std::vector<double>& supposedly_sorted, const std::vector<double>& original) {
  auto original_sorted = original;
  std::sort(original_sorted.begin(), original_sorted.end());
  bool are_equal = supposedly_sorted == original_sorted;
  if (!are_equal) {
	log<INFO>("Verification failed (top - expected, bottom - actual)\n");
	log<DEBUG>(original_sorted);
	log<DEBUG>(supposedly_sorted);
  }
}

template<int max = 1>
void sequential_bucket_sort(std::vector<double>& array, int no_buckets) {
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
// - each thread has its own buckets
template<int max = 1>
void parallel_bucket_sort_1(std::vector<double>& array, int buckets_per_thread, Measurement& measurement) {
  // allocate memory for buckets.
  int no_buckets = param_threads * buckets_per_thread;
  int estimated_bucket_size = std::max((int)array.size() / no_buckets, 1);
  std::vector<std::vector<double>> buckets(no_buckets);
  for (auto bucket : buckets) {
	buckets.reserve(estimated_bucket_size);
  }

#pragma omp parallel shared(buckets) num_threads(param_threads)
  {
	int tid = omp_get_thread_num();

	// we start by populating buckets
	// each thread fills its own buckets.
	double split_to_buckets_time = timeit([&] {
	  for (int i = 0; i < array.size(); i++) {
		int bucket_index = std::min((int)(no_buckets * array[i] / max), no_buckets - 1);

		if (tid * buckets_per_thread <= bucket_index &&
			bucket_index < (tid + 1) * buckets_per_thread) {
		  buckets[bucket_index].push_back(array[i]);
		}
	  }
	});

	// now each thread sorts its share of buckets.
	double sort_buckets_time = timeit([&] {
	  #pragma omp for schedule(static)
	  for (int bucket_index = 0; bucket_index < no_buckets; bucket_index++) {
		std::sort(buckets[bucket_index].begin(), buckets[bucket_index].end());
	  }
	});

	// after the buckets have been sorted
	double write_sorted_buckets_time = timeit([&] {

	  // we compute indices where to start writing in the original array.
	  std::vector<int> bucket_idx_to_array_idx_table(no_buckets);
	  for (int bucket_index = 1; bucket_index < no_buckets; bucket_index++) {
		bucket_idx_to_array_idx_table[bucket_index] =
			buckets[bucket_index - 1].size() + bucket_idx_to_array_idx_table[bucket_index - 1];
	  }

	  // finally, we can write the result.
#pragma omp for schedule(static)
	  for (int bucket_index = 0; bucket_index < no_buckets; bucket_index++) {
		int start_idx = bucket_idx_to_array_idx_table[bucket_index];
		for (int i = 0; i < buckets[bucket_index].size(); i++) {
		  array[start_idx + i] = buckets[bucket_index][i];
		}
	  }
	});

	// update measurements at the end.
	if (tid == 0) {
	  measurement.split_to_buckets_time = split_to_buckets_time;
	  measurement.sort_buckets_time = sort_buckets_time;
	  measurement.write_sorted_buckets_time = write_sorted_buckets_time;
	}
  }
}

template<int max = 1>
void parallel_bucket_sort_2(std::vector<double>& array, int buckets_per_thread, Measurement& measurement) {
  // allocate memory for buckets.
  int no_buckets = param_threads * buckets_per_thread;
  int estimated_bucket_size = std::max((int)array.size() / no_buckets, 1);
  std::vector<std::vector<double>> buckets(no_buckets);
  for (auto bucket : buckets) {
	buckets.reserve(estimated_bucket_size);
  }

#pragma omp parallel shared(buckets) num_threads(param_threads)
  {
	int tid = omp_get_thread_num();

	// we start by populating buckets
	// each thread fills its own buckets.
	double split_to_buckets_time = timeit([&] {
	  for (int i = 0; i < array.size(); i++) {
		int bucket_index = std::min((int)(no_buckets * array[i] / max), no_buckets - 1);

		if (tid * buckets_per_thread <= bucket_index &&
			bucket_index < (tid + 1) * buckets_per_thread) {
		  buckets[bucket_index].push_back(array[i]);
		}
	  }
	});

	// now each thread sorts its share of buckets.
	double sort_buckets_time = timeit([&] {
#pragma omp for schedule(static)
	  for (int bucket_index = 0; bucket_index < no_buckets; bucket_index++) {
		std::sort(buckets[bucket_index].begin(), buckets[bucket_index].end());
	  }
	});

	// after the buckets have been sorted
	double write_sorted_buckets_time = timeit([&] {

	  // we compute indices where to start writing in the original array.
	  std::vector<int> bucket_idx_to_array_idx_table(no_buckets);
	  for (int bucket_index = 1; bucket_index < no_buckets; bucket_index++) {
		bucket_idx_to_array_idx_table[bucket_index] =
			buckets[bucket_index - 1].size() + bucket_idx_to_array_idx_table[bucket_index - 1];
	  }

	  // finally, we can write the result.
#pragma omp for schedule(static)
	  for (int bucket_index = 0; bucket_index < no_buckets; bucket_index++) {
		int start_idx = bucket_idx_to_array_idx_table[bucket_index];
		for (int i = 0; i < buckets[bucket_index].size(); i++) {
		  array[start_idx + i] = buckets[bucket_index][i];
		}
	  }
	});

	// update measurements at the end.
	if (tid == 0) {
	  measurement.split_to_buckets_time = split_to_buckets_time;
	  measurement.sort_buckets_time = sort_buckets_time;
	  measurement.write_sorted_buckets_time = write_sorted_buckets_time;
	}
  }
}


int main(int argc, char* argv[]) {
  argh::parser cmdl(argv);

  cmdl({"-t", "--threads"}) >> param_threads;
  cmdl({"-s", "--size"}) >> param_size;
  cmdl({"-r", "--repeat"}) >> param_repeat;
  cmdl({"-v", "--version"}) >> param_algorithm_version;

  for (int i = 0; i < param_repeat; i++) {
	std::vector<double> data(param_size);
	Measurement measurement;

	// 1. generate data
	measurement.rand_gen_time = timeit([&] {
	  uniform_fill(data);
	});
	auto data_copy = data;

	// 2. sort
	if (param_algorithm_version == 1) {
	  measurement.sort_time = timeit([&] {
		parallel_bucket_sort_1(data, 3, measurement);
	  });
	}

	// 3. verify
	verify(data, data_copy);

	// 4. log results
	log<INFO>("rand_gen_time: %lfs, "
			  "split_to_buckets_time: %lfs, "
			  "sort_buckets_time: %lfs, "
			  "write_sorted_buckets_time: %lfs, "
			  "sort_time: %lfs"
			  "\n",
			  measurement.rand_gen_time,
			  measurement.split_to_buckets_time,
			  measurement.sort_buckets_time,
			  measurement.write_sorted_buckets_time,
			  measurement.sort_time);
  }
}