#include <vector>
#include <random>
#include <cstdio>
#include <omp.h>
#include <algorithm>
#include <iostream>
#include "argh/argh.h"

// ------ Program parameters ----------

int param_threads = 1,
	param_size = 15000000,
	param_repeat = 1,
	param_algorithm_version = 3,
	bucket_size = 50,
	log_format = 1;

bool sample_generator_flag = false;

// ------ Logging utilities --------------------

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


// ------ Rest of utilities ----------
// - measurements
// - timing
// - sequential bucket sort
// - verification


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
	log<INFO>("Verification failed (top -> expected, bottom -> actual)\n");
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

// ------ Actual algorithms ----------

template<int min = 0, int max = 1>
void uniform_fill(std::vector<double>& array) {
#pragma omp parallel num_threads(param_threads)
  {
	std::uniform_real_distribution<double> distribution(min, max);
	std::default_random_engine generator;
	int t_thread = omp_get_thread_num();
	generator.seed(t_thread * time(NULL) + 17);

#pragma omp for SCHEDULE
	for (size_t i = 0; i < array.size(); i++) {
	  array[i] = distribution(generator);
	}
  }
}


// ------ Prefix sums ----------

void synchronous_prefix_sum(std::vector<std::vector<double>>& buckets,
							std::vector<int>& prefix_sum,
							int no_buckets) {
  for (int bucket_index = 1; bucket_index < no_buckets; bucket_index++) {
	prefix_sum[bucket_index] =
		buckets[bucket_index - 1].size() + prefix_sum[bucket_index - 1];
  }
}

void parallel_prefix_sum(std::vector<std::vector<double>>& buckets,
						 std::vector<int>& prefix_sum_z,
						 std::vector<int>& prefix_sum,
						 int no_buckets) {
  int tid = omp_get_thread_num();
  int sum = 0;
#pragma omp for schedule(static)
  for (int bucket_index = 1; bucket_index < no_buckets; bucket_index++) {
	sum += buckets[bucket_index - 1].size();
	prefix_sum[bucket_index] = sum;
  }
  prefix_sum_z[tid + 1] = sum;

#pragma omp barrier
  auto offset = 0;
  for (int i = 0; i < (tid + 1); i++) {
	offset += prefix_sum_z[i];
  }

#pragma omp for schedule(static)
  for (int bucket_index = 1; bucket_index < no_buckets; bucket_index++) {
	prefix_sum[bucket_index] += offset;
  }
}

// algorithm #1
// - each thread has its own buckets
template<int max = 1>
void parallel_bucket_sort_1(std::vector<double>& array, Measurement& measurement) {
  // allocate memory for buckets.
  int no_buckets = param_size / bucket_size;
  int buckets_per_thread = no_buckets / param_threads;
  int estimated_bucket_size = std::max((int)array.size() / no_buckets, 1);
  std::vector<std::vector<double>> buckets(no_buckets);
  for (auto bucket : buckets) {
	bucket.reserve(estimated_bucket_size);
  }

#pragma omp parallel shared(buckets) firstprivate(no_buckets) num_threads(param_threads)
  {
	int tid = omp_get_thread_num();

	// we start by populating buckets
	// each thread fills its own buckets.
	double split_to_buckets_time = timeit([&] {
	  for (size_t i = 0; i < array.size(); i++) {
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
		for (size_t i = 0; i < buckets[bucket_index].size(); i++) {
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

// algorithm #3
// Each thread has its own private buckets
// where it accumulates values from the array.
template<int max = 1>
void parallel_bucket_sort_3(std::vector<double>& array, Measurement& measurement) {

  // allocate memory for shared_buckets.
  int no_buckets = param_size / bucket_size;
  int estimated_bucket_size = std::max((int)array.size() / no_buckets, 1);
  std::vector<std::vector<double>> shared_buckets(no_buckets);
  for (auto bucket : shared_buckets) {
	bucket.reserve(estimated_bucket_size);
  }

  // each thread has its own private buckets.
  std::vector<std::vector<std::vector<double>>> private_buckets(param_threads);

  // datastructures for computing prefix sum in parallel.
  std::vector<int> prefix_sum_z(param_threads + 1);
  prefix_sum_z.reserve(param_threads + 1);
  prefix_sum_z.push_back(0);

  std::vector<int> prefix_sum(no_buckets);
  prefix_sum.reserve(no_buckets);

#pragma omp parallel shared(shared_buckets, private_buckets, no_buckets, estimated_bucket_size) num_threads(param_threads)
  {
	int tid = omp_get_thread_num();

	double split_to_buckets_time = timeit([&] {

	  // each thread allocates its own private buckets.
	  private_buckets[tid].resize(no_buckets);
	  for (auto bucket : private_buckets[tid]) {
		bucket.reserve(estimated_bucket_size);
	  }

	  // each thread updates its own private buckets.
#pragma omp for schedule(static)
	  for (size_t i = 0; i < array.size(); i++) {
		int bucket_index = std::min((int)(no_buckets * array[i] / max), no_buckets - 1);
		private_buckets[tid][bucket_index].push_back(array[i]);
	  }

	  // threads flush the results from private buckets to shared buckets.
#pragma omp for schedule(static)
	  for (int bucket_idx = 0; bucket_idx < no_buckets; bucket_idx++) {

		for (int thread_id = 0; thread_id < param_threads; thread_id++) {
		  for (auto v : private_buckets[thread_id][bucket_idx]) {
			shared_buckets[bucket_idx].push_back(v);
		  }
		}
	  }
	});

	// now each thread sorts its share of shared_buckets.
	double sort_buckets_time = timeit([&] {
#pragma omp for schedule(static)
	  for (int bucket_index = 0; bucket_index < no_buckets; bucket_index++) {
		std::sort(shared_buckets[bucket_index].begin(), shared_buckets[bucket_index].end());
	  }
	});

	// after the shared_buckets have been sorted
	double write_sorted_buckets_time = timeit([&] {

	  // we compute indices where to start writing in the original array.
//	  synchronous_prefix_sum(shared_buckets, prefix_sum, no_buckets);
	  parallel_prefix_sum(shared_buckets, prefix_sum_z, prefix_sum, no_buckets);

	  // finally, we can write the result.
#pragma omp for schedule(static)
	  for (int bucket_index = 0; bucket_index < no_buckets; bucket_index++) {
		int start_idx = prefix_sum[bucket_index];
		for (size_t i = 0; i < shared_buckets[bucket_index].size(); i++) {
		  array[start_idx + i] = shared_buckets[bucket_index][i];
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

void log_generated_data(std::vector<double>& data) {
  for (size_t i = 0; i < data.size() - 1; i++) {
	log<INFO>("%lf; ", data[i]);
  }
  log<INFO>("%lf\n", data[data.size() - 1]);
}

void log_results(Measurement measurement) {
  if (log_format == 1) {
	log<INFO>(
		"%d;"
		"%d;"
		"%d;"
		"%lf;"
		"%lf;"
		"%lf;"
		"%lf;"
		"%lf"
		"\n",
		bucket_size,
		param_threads,
		param_algorithm_version,
		measurement.rand_gen_time,
		measurement.split_to_buckets_time,
		measurement.sort_buckets_time,
		measurement.write_sorted_buckets_time,
		measurement.sort_time);
  } else {
	// Other formats
  }
}

int main(int, char* argv[]) {
  argh::parser cmdl(argv);

  cmdl({"-t", "--threads"}, param_threads) >> param_threads;
  cmdl({"-s", "--size"}, param_size) >> param_size;
  cmdl({"-r", "--repeat"}, param_repeat) >> param_repeat;
  cmdl({"-v", "--version"}, param_algorithm_version) >> param_algorithm_version;
  cmdl({"-b", "--bucket-size"}, bucket_size) >> bucket_size;
  cmdl({"-l", "--log-format"}, log_format) >> log_format;
  cmdl({"-g", "--sample-generator"}, sample_generator_flag) >> sample_generator_flag;

  if (sample_generator_flag) {
	std::vector<double> data(param_size);
	uniform_fill(data);
	log_generated_data(data);

	return 0;
  }

  for (int i = 0; i < param_repeat; i++) {
	std::vector<double> data(param_size);
	Measurement measurement;

	// 1. generate data
	measurement.rand_gen_time = timeit([&] {
	  uniform_fill(data);
	});
	auto data_copy = data;

	// 2. sort using chosen algorithm
	if (param_algorithm_version == 1) {
	  measurement.sort_time = timeit([&] {
		parallel_bucket_sort_1(data, measurement);
	  });
	} else if (param_algorithm_version == 3) {
	  measurement.sort_time = timeit([&] {
		parallel_bucket_sort_3(data, measurement);
	  });
	}

	// 3. verify
	verify(data, data_copy);

	// 4. log results,
	log_results(measurement);
  }

  return 0;
}