### A Pluto.jl notebook ###
# v0.17.5

using Markdown
using InteractiveUtils

# ╔═╡ ed491677-bca1-4c08-a568-b062b1ee266d
using Markdown

# ╔═╡ 77326d30-e595-4d99-8a08-c5752e8e10cc
using InteractiveUtils

# ╔═╡ 2f94ff6a-8102-4baf-a253-9d455e3f215e
using Query

# ╔═╡ f594eba6-70a8-4167-a910-6ffc8a872a13
begin
	import CSV
	using DataFrames
	using StatsPlots
	using Measurements
	using Statistics
	using BrowseTables
end

# ╔═╡ aecadb90-bf2c-4011-a70a-d27e38125bb6
function lab1_measurements(csv_file)
	lab1_data_dir = "lab1/measurements/csv"
	raw_df = CSV.read("$lab1_data_dir/$csv_file", DataFrame)
	res_df = DataFrame(size=Int[], throughput=Measurement{Float32}[])
    for df in groupby(raw_df, :size)
		throughput = df[:, :throughput]
		push!(res_df, (df[1,:size], measurement(mean(throughput), std(throughput))))
	end
	res_df
end;

# ╔═╡ 6e8d59e4-661f-4b13-a983-c10e2acb07d9
function select_smaller_than(df, message_size)
	df |> @filter(_.size < message_size) |> DataFrame
end;

# ╔═╡ 806718ac-7efb-4083-8cea-989c730b5765
begin
	ssend_single_node = lab1_measurements("ssend_single_node.csv")
	ssend_two_nodes = lab1_measurements("ssend_two_nodes.csv")
	ibsend_single_node = lab1_measurements("ibsend_single_node.csv")
	ibsend_two_nodes = lab1_measurements("ibsend_two_nodes.csv")
end;

# ╔═╡ 74bcdc04-ba8e-4bc9-bc44-29008045005f
md"""
## Metody programowania równoległego
Patryk Wojtyczek

Kod programów jak i skrypty do uruchomiania programów zamieściłem w sprawozdaniu. Dane znajdują się na końcu.

#### Część 1 - Komunikacja P2P
Programy do pomiaru przepustowości zostały napisane w języku `c` i 
były wykonywane na klastrze `vnode-*.dydaktyka.icsr.agh.edu.pl`. 
Celem zadania jest zmierzenie wartości opóźnienia i charakterystyki przepustowości połączeń w klastrze.

Funkcje wykorzystane do komunikacji:
- `ssend` - Synchronous blocking send. 
Blokuje dopóki odbiorca nie odebrał wiadomości. Po wykonaniu tej funkcji można bezpiecznie
korzystać z przekazanego bufora.

- `ibsend` - Asynchronous non-blocking send.
Funkcja ta stworzy kopię przekazanych danych i wyśle ją w późniejszym czasie.
Funkcja nie blokuje wywołującego, i po jej wywołaniu nie można modyfikować bufora gdyż
mógł on jeszcze nie zostać skopiowany. Do sprawdzenia czy bufora można użyć służy funkcja
`MPI_Test` lub `MPI_Wait`.
"""

# ╔═╡ 86bc5974-d0ff-4d86-bce7-0d87114529a4
md"""
Pomiary wykonywałem w następujący sposób. 
Z góry ustaliłem ilość danych do przesłania - 100MB. 
Dla każdej rozważanej wielkości wiadomości obliczałem ile wiadomości trzeba wysłać aby przesłać
ustaloną wyżej ilość danych. Na podstawie czasu potrzebnego na wykonanie tranferu tych danych obliczałem 
przepustowość. 

Jako MB - przyjąłem (być może zaskakująco) $10^6$B zgodnie z układem SI.

Zmierzyłem wiadomości w zakresie 1B-10MB, przy czym większość zmierzonych
rozmiarów (około 300) mieści się poniżej 250kB, pozostałych jest około 100.
Dla każdej wielkości wiadomości powtórzyłem pomiar trzykrotnie.
"""

# ╔═╡ b75e6d97-432d-4418-82f8-c7e25106c120
md"""
##### Kod Źródłowy i Skrypty
- ibsend.c
```c
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
```

- ssend.c
```c
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
      ping_message[round_id % message_size_bytes] = (char) rand();
      MPI_Send(ping_message, ping_buffer_size, MPI_CHAR, partner_rank,
               message_id(round_id, true), MPI_COMM_WORLD);
      DEBUG_PRINTF("Round: %ld, sent: %s\n", round_id, ping_message);

      MPI_Recv(pong_buffer, pong_buffer_size, MPI_CHAR, partner_rank,
               message_id(round_id, false), MPI_COMM_WORLD, MPI_STATUS_IGNORE);
      DEBUG_PRINTF("Round: %ld, received: %s\n", round_id, pong_buffer);
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
    long int round_id;
    for (round_id = 0; round_id < ping_pong_rounds; round_id++) {
      MPI_Recv(ping_buffer, ping_buffer_size, MPI_CHAR, partner_rank,
               message_id(round_id, true), MPI_COMM_WORLD, MPI_STATUS_IGNORE);
      DEBUG_PRINTF("Round: %ld, received: %s\n", round_id, ping_buffer);

      pong_message[round_id % message_size_bytes] = ping_buffer[round_id % message_size_bytes];
      DEBUG_PRINTF("%c", pong_message[round_id % message_size_bytes]);
      MPI_Send(pong_message, pong_buffer_size, MPI_CHAR, partner_rank,
               message_id(round_id, false), MPI_COMM_WORLD);
      DEBUG_PRINTF("Round: %ld, sent: %s\n", round_id, pong_message);
    }
  }

  MPI_Finalize();
  return 0;
}
```

Skrypty do uruchamiania:
- `run.sh`
```sh
#!/bin/bash 

export VNODE_CLUSTER_SINGLE_NODE=true
make ssend-multiple-runs
make ibsend-multiple-runs

export VNODE_CLUSTER_SINGLE_NODE=false
export VNODE_CLUSTER_TWO_NODES=true
make ssend-multiple-runs
make ibsend-multiple-runs
```

- makefile (nie był to najlepszy pomysł, dużo prościej byłoby po prostu użyć basha)
```makefile
CC = "mpicc"
MPIEXEC = "mpiexec"
NODE_SUFFIX = "single_node"
IBSEND_PREFIX = "ibsend"
SSEND_PREFIX = "ssend"
MEASUREMENTS_DIR = "measurements"
ifeq (${VNODE_CLUSTER_SINGLE_NODE}, true)
	MPIEXEC = mpiexec -machinefile ./vcluster-config/single_node
endif
ifeq (${VNODE_CLUSTER_TWO_NODES}, true)
	MPIEXEC = mpiexec -machinefile ./vcluster-config/two_nodes
	NODE_SUFFIX = "two_nodes"
endif

TRIALS ?= 3
DATA_FILE_ID ?= 0
DATA_TO_BE_TRANFERRED_BYTES = 100000000 # 100 MB

MESSAGE_STEP_SIZE_BYTES = 100000 # 100 kB
MAX_MESSAGE_SIZE = 10000000 # 10 MB

MESSAGE_STEP_SMALL_STEP_SIZE_BYTES = 1000 # 5kB
SMALL_STEP_THRESHOLD_BYTES = 250000 # 250kb

MESSAGE_STEP_VERY_SMALL_STEP_SIZE_BYTES = 100 # 100B
VERY_SMALL_STEP_THRESHOLD_BYTES = 5000 # 5 kB
# ~ 50 + 250 + 100 measurements.

# ibsend
ibsend-plot: 
	./gnuplot/composite_stats.sh "./$(MEASUREMENTS_DIR)/$(IBSEND_PREFIX)_$(NODE_SUFFIX)-*.dat" > "./build/$(IBSEND_PREFIX)_$(NODE_SUFFIX)_composite.dat"
	gnuplot -persistent gnuplot/$(IBSEND_PREFIX)_$(NODE_SUFFIX).gpi

ibsend-multiple-runs:
	for (( i=1; i<=${TRIALS}; i++ )) ; do \
		$(MAKE) ibsend-run DATA_FILE_ID=$$i ; \
	done

ibsend-run: build/ibsend 
	mkdir -p ./${MEASUREMENTS_DIR}
	rm -f "${MEASUREMENTS_DIR}/ibsend-${DATA_FILE_ID}.dat"

	message_size="1" ; while [[ $$message_size -le $(VERY_SMALL_STEP_THRESHOLD_BYTES) ]] ; do \
		${MPIEXEC} -n 2 ./build/ibsend $$message_size ${DATA_TO_BE_TRANFERRED_BYTES} "${MEASUREMENTS_DIR}/${IBSEND_PREFIX}_${NODE_SUFFIX}-${DATA_FILE_ID}.dat"; \
        ((message_size = message_size + $(MESSAGE_STEP_VERY_SMALL_STEP_SIZE_BYTES))) ; \
    done

	message_size=$(VERY_SMALL_STEP_THRESHOLD_BYTES) ; while [[ $$message_size -le $(SMALL_STEP_THRESHOLD_BYTES) ]] ; do \
		$(MPIEXEC) -n 2 ./build/ibsend $$message_size ${DATA_TO_BE_TRANFERRED_BYTES} "${MEASUREMENTS_DIR}/${IBSEND_PREFIX}_${NODE_SUFFIX}-${DATA_FILE_ID}.dat"; \
        ((message_size = message_size + $(MESSAGE_STEP_SMALL_STEP_SIZE_BYTES))) ; \
    done

	message_size=$(MESSAGE_STEP_SIZE_BYTES) ; while [[ $$message_size -le $(MAX_MESSAGE_SIZE) ]] ; do \
		$(MPIEXEC) -n 2 ./build/ibsend $$message_size ${DATA_TO_BE_TRANFERRED_BYTES} "${MEASUREMENTS_DIR}/${IBSEND_PREFIX}_${NODE_SUFFIX}-${DATA_FILE_ID}.dat"; \
        ((message_size = message_size + $(MESSAGE_STEP_SIZE_BYTES))) ; \
    done

build/ibsend: src/ibsend.c build
	$(CC) -o build/ibsend src/ibsend.c

# ssend
ssend-plot: 
	./gnuplot/composite_stats.sh "./$(MEASUREMENTS_DIR)/$(SSEND_PREFIX)_$(NODE_SUFFIX)-*.dat" > "./build/$(SSEND_PREFIX)_$(NODE_SUFFIX)_composite.dat"
	gnuplot -persistent gnuplot/$(SSEND_PREFIX)_$(NODE_SUFFIX).gpi

ssend-multiple-runs:
	for (( i=1; i<=${TRIALS}; i++ )) ; do \
		$(MAKE) ssend-run DATA_FILE_ID=$$i ; \
	done

ssend-run: build/ssend 
	mkdir -p ./${MEASUREMENTS_DIR}
	rm -f "${MEASUREMENTS_DIR}/ssend-${DATA_FILE_ID}.dat"

	message_size="1" ; while [[ $$message_size -le $(VERY_SMALL_STEP_THRESHOLD_BYTES) ]] ; do \
		$(MPIEXEC) -n 2 ./build/ssend $$message_size ${DATA_TO_BE_TRANFERRED_BYTES} "${MEASUREMENTS_DIR}/${SSEND_PREFIX}_${NODE_SUFFIX}-${DATA_FILE_ID}.dat"; \
        ((message_size = message_size + $(MESSAGE_STEP_VERY_SMALL_STEP_SIZE_BYTES))) ; \
    done

	message_size=$(VERY_SMALL_STEP_THRESHOLD_BYTES) ; while [[ $$message_size -le $(SMALL_STEP_THRESHOLD_BYTES) ]] ; do \
		$(MPIEXEC) -n 2 ./build/ssend $$message_size ${DATA_TO_BE_TRANFERRED_BYTES} "${MEASUREMENTS_DIR}/${SSEND_PREFIX}_${NODE_SUFFIX}-${DATA_FILE_ID}.dat"; \
        ((message_size = message_size + $(MESSAGE_STEP_SMALL_STEP_SIZE_BYTES))) ; \
    done

	message_size=$(MESSAGE_STEP_SIZE_BYTES) ; while [[ $$message_size -le $(MAX_MESSAGE_SIZE) ]] ; do \
		$(MPIEXEC) -n 2 ./build/ssend $$message_size ${DATA_TO_BE_TRANFERRED_BYTES} "${MEASUREMENTS_DIR}/${SSEND_PREFIX}_${NODE_SUFFIX}-${DATA_FILE_ID}.dat"; \
        ((message_size = message_size + $(MESSAGE_STEP_SIZE_BYTES))) ; \
    done

build/ssend: src/ssend.c build
	$(CC) -o build/ssend src/ssend.c

# ping-pong
run-ping-pong: build/ping_pong
	$(MPIEXEC) -n 2 ./build/ping_pong 16

ping-pong-measure-multiple-runs:
	for (( i=1; i<=${TRIALS}; i++ )) ; do \
		$(MAKE) ping-pong-measure DATA_FILE_ID=$$i ; \
	done
		
ping-pong-measure: build/ping_pong 
	rm -f "build/ping_pong-${DATA_FILE_ID}.dat"
	for n in 1 64 256 1024 65536 1048576 ; do \
		$(MPIEXEC) -n 2 ./build/ping_pong $$n "build/ping_pong-${DATA_FILE_ID}.dat"; \
    done

ping-pong-plot: 
	./gnuplot/composite_stats.sh "./build/ping_pong-*.dat" > "./build/ping_pong_composite.dat"
	gnuplot -persistent gnuplot/ping_pong.gpi

build/ping_pong: src/ping_pong.c build
	$(CC) -o build/ping_pong src/ping_pong.c

build:
	mkdir -p ./build

clean:
	rm -rf ./build/*

```


"""




# ╔═╡ ed774b67-b8ca-4215-b03f-542ff83df9f7
md"""
#### Przepustowość na pojedyńczym węźle

Na pojedyńczym węźle przepustowość P2P jest olbrzymia. 
Największy throughput uzyskujemy dla wiadomości o rozmiarze 100kB - 1MB, 
później throughput zaczyna spadać. Dla bardzo małych wiadmości throughput jest bardzo niski
gdyż narzut ze względu na komunikację między procesami jest znacznie większy od narzutu ze względu na 
przenoszenie danych.

`Ssend` osiąga większy throughput od ibsend ze względu na fakt, że ssend nie robi dodatkowych kopii i to koszt tego
kopiowania widzimy na wykresie. Gdyby program na którym testujemy nie działał na zasadzie 
`wyślij-ping, odbierz-ping, wyślij-pong, odbierz-pong` tylko raczej 
`wyślij kilkanaście wiadomości i jakiś czas później sprawdź czy zostały wysłane`
to myślę, że buforowanie wiadomości miałoby pozytywny wpływ na performance.

Poniżej przedstawiłem wykresy przepustowości dla wszystkich przetestowanych rozmiarów 
i tylko dla mniejszych rozmiarów wiadomości.
"""


# ╔═╡ d7515cd9-fbbd-4f82-85f7-a3ad8b93aa38
begin
	plot(ylabel="Przepustowość [MB/s]", xlabel="Rozmiar wiadomości [B]")
	title!("Przepustowość na pojedyńczym węźle")
	@df ssend_single_node scatter!(:size, :throughput, label=".ssend")
	@df ibsend_single_node scatter!(:size, :throughput, label=".ibsend")
end


# ╔═╡ fc31e18d-2524-45b4-be45-2b9deaee4f76
begin
	plot(ylabel="Przepustowość [MB/s]", xlabel="Rozmiar wiadomości [B]", legend=:topleft)
	title!("Przepustowość na pojedyńczym węźle")

	threshold_single_node = 3e5 
	@df select_smaller_than(ssend_single_node, threshold_single_node) scatter!(:size, :throughput, label=".ssend")
	@df select_smaller_than(ibsend_single_node, threshold_single_node) scatter!(:size, :throughput, label=".ibsend")
end

# ╔═╡ f0f03907-6aba-433b-9878-60bbc6c7f62e
md"""
#### Przepustowość na dwóch węzłach

Tutaj wykonane pomiary były obarczone bardzo dużą wariancją. 
Wykres wygląda o tyle podobnie, że znowu małe rozmiary wiadmości dają niską przepustowość i wraz
ze wzrostem rozmiaru wiadomości osiągamy coraz lepszą przepustowość.
Mimo wszystko widać, że przepustowość spadła conajmniej 10-krotnie ze względu na komunikację przez sieć.
Nie widać tutaj też trendu: im większy rozmiar wiadomości tym throughput zaczyna spadać.
Różnice pomiędzy funkcjami wydają się być pomijalne, głównie ze względu na dominujący narzut w samej komunikacji.
Widać też ciekawy spadek przepustowości w okolicach $1.25 \cdot 10^5 kB$ 
choć ciężko powiedzieć czym jest spowodowany.
"""


# ╔═╡ 803d33bc-0320-4c67-9573-c7b98a869a2a
begin
	plot(ylabel="Przepustowość [MB/s]", xlabel="Rozmiar wiadomości [B]")
	title!("Przepustowość na dwóch maszynach")
	@df ssend_two_nodes scatter!(:size, :throughput, label=".ssend")
	@df ibsend_two_nodes scatter!(:size, :throughput, label=".ibsend")
end

# ╔═╡ 419114e5-54a1-4ba6-8914-0327229711ee
begin
	plot(ylabel="Przepustowość [MB/s]", xlabel="Rozmiar wiadomości [B]")
	title!("Przepustowość na dwóch maszynach")

	threshold_two_nodes = 3e5 
	@df select_smaller_than(ssend_two_nodes, threshold_two_nodes) scatter!(:size, :throughput, label=".ssend")
	@df select_smaller_than(ibsend_two_nodes, threshold_two_nodes) scatter!(:size, :throughput, label=".ibsend")
end

# ╔═╡ a0c5dc3f-be3d-4a3e-a3ae-4eea77f8dfc5
function delay(df)
	dff = df |> @filter(_.size <= 101) |> DataFrame
	thr = dff[:,:throughput] 
	time = 1 / thr
	measurement(mean(time), std(time))
end;

# ╔═╡ faa0408d-f418-413f-8480-b63ffbdb4a9d
md"""
#### Opóźnienie
Na podstawie zebranych danych można oszacować opóźnienie (czyli czas na wysłanie 1B) w komunikacji. 

W przypadku funkcji `ssend` jest to:
- jeden węzeł: $(delay(CSV.read("lab1/measurements/csv/ssend_single_node.csv", DataFrame)))s
- dwa węzły: $(delay(CSV.read("lab1/measurements/csv/ssend_two_nodes.csv", DataFrame)))s

W przypadku funkcji `ibsend` jest to:
- jeden węzeł: $(delay(CSV.read("lab1/measurements/csv/ibsend_single_node.csv", DataFrame)))s
- dwa węzły: $(delay(CSV.read("lab1/measurements/csv/ibsend_two_nodes.csv", DataFrame)))s
"""


# ╔═╡ a7a4a356-2493-4f99-9652-6b9e9e4b0af2
md"""
#### Część 2 - Badanie efektywności programu równoległego

Program do szacowania liczby pi metodą monte carlo został napisany w języku `c`. 
Wyniki zostały zebrane z wielokrotnego uruchomiania go na prometeuszu.
Program posiada znikomą część sekwencyjną (faza reduce, gdy czekamy na wyniki od pozostałych węzłów) 
stąd możemy go porównywać do programu idealnie równoległego.

##### Pomiary
Pomiary wykonałem dla pięciu liczb punktów:
- π s1: 20000000 = $2 ⋅ 10^7$ 
- π s2: 40000000 = $4 ⋅ 10^7$ - mniej niż sekunda dla jednego węzła.
- π s3: 400000000 = $4 ⋅ 10^8$
- π s4: 4000000000 = $4 ⋅ 10^9$
- π s5: 20000000000 = $2 ⋅ 10^{10}$ - ponad minuta ze wszystkimi węzłami.

Pomiary zostały powtórzone wielokrotnie (między 10-20 razy) oprócz grupy π s5 gdzie udało 
mi się je wykonać tylko raz i rozpocząć drugi pomiar.

Większość wykresów jest podzielona na dwa ze względu na fakt, że wykresy wyglądają dość nieczytelnie 
z pięcioma grupami.
"""

# ╔═╡ c88f6105-1e02-48d6-8860-e9c37c96a4fa
md"""
##### Kod Źródłowy i Skrypty
- pi.c

```c
#include <float.h>
#include <math.h>
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define TIME_SEED time(NULL)
#ifndef DBL_DECIMAL_DIG        
#define DBL_DECIMAL_DIG        17
#endif

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
```

- makefile
```makefile
CC = "mpicc"
MPIEXEC = "mpiexec"

build/ping_pong: src/pi.c build
	$(CC) -o build/pi src/pi.c

build:
	mkdir -p ./build

clean:
	rm -rf ./build/*
```

- run.sh
```sh
#!/bin/bash -l
#SBATCH --nodes 1
#SBATCH --ntasks 12
#SBATCH --time=01:00:00
#SBATCH --partition=plgrid-short
#SBATCH --account=plgmpr22
#SBATCH --sockets-per-node=2

module add plgrid/tools/openmpi
make

for repeat in {1..20}; do
	for points in {40000000,400000000,4000000000}; do
		for nodes in {1..12}; do
			mpiexec -np $nodes ./build/pi $points | tee -a data/data.csv
		done
	done
done
```

- run-small.sh
```sh
#!/bin/bash -l
#SBATCH --nodes 1
#SBATCH --ntasks 12
#SBATCH --time=01:00:00
#SBATCH --partition=plgrid-short
#SBATCH --account=plgmpr22
#SBATCH --sockets-per-node=2

module add plgrid/tools/openmpi
make

for repeat in {1..20}; do
	for points in 20000000; do
		for nodes in {1..12}; do
			mpiexec -np $nodes ./build/pi $points | tee -a data/data.csv
		done
	done
done
```

- run-med.sh
```sh
#!/bin/bash -l
#SBATCH --nodes 1
#SBATCH --ntasks 12
#SBATCH --time=01:00:00
#SBATCH --partition=plgrid-short
#SBATCH --account=plgmpr22
#SBATCH --sockets-per-node=2

module add plgrid/tools/openmpi
make

for repeat in {1..20}; do
	for points in 4000000000; do
		for nodes in {1..12}; do
			mpiexec -np $nodes ./build/pi $points | tee -a data/data.csv
		done
	done
done
```

- run-big.sh
```sh
#!/bin/bash -l
#SBATCH --nodes 1
#SBATCH --ntasks 12
#SBATCH --time=01:00:00
#SBATCH --partition=plgrid-short
#SBATCH --account=plgmpr22
#SBATCH --sockets-per-node=2

module add plgrid/tools/openmpi
make

for repeat in {1..20}; do
	for points in 20000000000; do
		for nodes in {1..12}; do
			mpiexec -np $nodes ./build/pi $points | tee -a data/data.csv
		done
	done
done
```

"""


# ╔═╡ c3780def-41ca-4648-ad73-034f3f782dc3
function lab2_measurements(csv_file)
	lab1_data_dir = "lab2/data"
	raw_df = CSV.read("$lab1_data_dir/$csv_file", DataFrame)
	res_df = DataFrame(size=Int[], throughput=Measurement{Float32}[])
    for df in groupby(raw_df, :size)
		throughput = df[:, :throughput]
		# nodes,pi,time,points,points_within
		push!(res_df, (df[1,:size], measurement(mean(throughput), std(throughput))))
	end
	res_df
end;

# ╔═╡ 8953fb85-6e35-4f2f-8018-0e37f393b1f4
function measure(pi_by_points)
	msm_df = DataFrame(nodes=Int[], time=Measurement{Float32}[])
	for df in groupby(pi_by_points, :nodes, sort=true)
		time = df[:,:time]
		push!(msm_df, (df[:,:nodes][1], measurement(mean(time), std(time))))
	end
	msm_df
end;

# ╔═╡ 8bf38410-d62a-44ae-8683-08e327f9b1e7
begin
	lab1_data_dir = "lab2/data"
	pi_df = CSV.read("$lab1_data_dir/data.csv", DataFrame)
	pi_groupped = groupby(pi_df, :points, sort=true)
	pi_s1, pi_s2, pi_s3, pi_s4, pi_s5 = measure.(collect(pi_groupped));
	collect(pi_groupped)
end;

# ╔═╡ 0a97c46b-3d85-4737-a702-4c4e076ff81d
begin 
	function plot_sf!(df; kwargs...)
		T = df[1,:time]
		S  = T ./ df[:,:time]
		p = df[:,:nodes]
		@df df scatter!(p, (1 ./ S .- 1 ./ p) ./ (1 .- 1 ./ p); kwargs...)
	end

	function plot_speedup!(df; kwargs...)
		T = df[1,:time]
		@df df scatter!(:nodes, T ./ :time; kwargs...)
	end

	function plot_efficiency!(df; kwargs...)
		T = df[1,:time]
		@df df scatter!(:nodes, T ./ :time ./ :nodes; kwargs...)
	end

	function plot_time!(df; kwargs...)
		@df df scatter!(:nodes, :time; kwargs...)
	end
end;

# ╔═╡ 9433a028-f000-48af-a5d1-b7672d2cf936
md"""
##### Czas wykonania

Widzimy, że czas wykonania w zależności od liczby węzłów przypomina funkcję $\frac{1}{x}$.
Nie obserwujemy tutaj sytuacji w której dodawanie węzłów nie przyspiesza obliczenia. 
Można się było odrobinę spodziewać jakiegoś spadku przy 8 węzłach ze względu na to, 
że tyle mieści się w jednym sockecie, a później mamy droższą komunikację między socketami natomiast w
tym problemie sama przepustowość komunikacji nie jest tak istotna bo nie przesyłamy dużych ilości danych.

Przy większej ilości węzłów zysk z każdego następnego węzła nie jest 
aż tak zauważalny jak dla kilku węzłów.
"""


# ╔═╡ 5db2f023-f4ed-47cc-98e5-edadac859907
begin
	plot(ylabel="Czas wykonania [s]", xlabel="ilość węzłów", xticks=0:1:12)
	plot_time!(pi_s1; label="π s1")
	plot_time!(pi_s2; label="π s2")
end

# ╔═╡ 801fbbda-2064-4ab0-948b-487ace41781f
begin
	plot(ylabel="Czas wykonania [s]", xlabel="ilość węzłów", xticks=0:1:12)
	plot_time!(pi_s3; label="π s3")
	plot_time!(pi_s4; label="π s4")
	plot_time!(pi_s5; label="π s5")
end

# ╔═╡ ce0e8a8e-3fca-49dc-8103-09b6805d6f16
md"""
##### Przyspieszenie względne
Widać, że o ile na początku trzymamy się idealne przyspieszenia to wraz z dodawniem
nowych węzłow odchodzimy od tej linii. Jest to spowodowane częścią sekwencyjną naszego programu.
Nawet jeśli podzieliśmy nasz problem na równe kawałki to różne węzły mogą skończyć swoje obliczenia w różnym
czasie co zmusza nas na czekanie w części sekwencyjnej.
"""


# ╔═╡ f7eda722-9660-42ac-89ec-dfc3d9933821
begin
	plot(ylabel="Przyśpieszenie względne", xlabel="ilość węzłów", xticks=0:1:12, legend = :topleft)
	plot_speedup!(pi_s1; label="π s1")
	plot_speedup!(pi_s2; label="π s2")
	plot_speedup!(pi_s3; label="π s3")
	plot_speedup!(pi_s4; label="π s4")
	plot_speedup!(pi_s5; label="π s5")
	plot!(x -> x, 1:12, label="")
end


# ╔═╡ b9a46140-5ed7-4c3f-9f1f-900724f35a37
md"""
##### Efektywność

Efektywność utrzymuje się pomiędzy 0.8 - 1.0, co wydaje się być rozsądnym zakresem. Idealną wartością 
dla efektywności byłaby wartość 1.
Wydaje się, że mniejsze liczby punktów osiągały lepszą efektywność. To przypuszczalnie dlatego, że różnice
w czasie wykonania programu na różnych węzłach są bardziej widoczne im ten program się dłużej wykonuje, a to w efekcie zwiększa
sekwencyjną część czekania na wyniki. 
"""

# ╔═╡ 737a4839-a22d-4293-9642-4c0592f59403
begin
	plot(ylabel="efektywność", xlabel="ilość węzłów", xticks=0:1:12)
	plot_efficiency!(pi_s1; label="π s1")
	plot_efficiency!(pi_s2; label="π s2")

	plot!(x -> 1, 1:12, label="")
end

# ╔═╡ b9328834-2d84-4e02-bb07-8dc9b1c7e01b
begin
	plot(ylabel="efektywność", xlabel="ilość węzłów", xticks=0:1:12)
	plot_efficiency!(pi_s3; label="π s3")
	plot_efficiency!(pi_s4; label="π s4")
	plot_efficiency!(pi_s5; label="π s5")
	plot!(x -> 1, 1:12, label="")
end

# ╔═╡ 21121a41-ff78-4a50-aa26-d57d28c6860a
md"""
##### Część Sekwencyjna

Wykresy pokazują niezerową część sekwencyjną, która idealnie byłaby zerowa.
Dla naszego problemu ma ona bardzo niską wartość.
"""


# ╔═╡ b983255e-4174-4ff3-84f9-62c29f638364
begin
	plot(xlabel="ilość węzłów", ylabel="serial fraction", xticks=0:1:12)
	plot_sf!(pi_s1; label="π s1")
	plot_sf!(pi_s2; label="π s2")
	plot!(x -> 0, 1:12, label="")
end


# ╔═╡ f126d7c8-3aee-44cf-8bbf-373521315fae
begin
	plot(xlabel="ilość węzłów", ylabel="serial fraction", xticks=0:1:12)
	plot_sf!(pi_s3; label="π s3")
	plot_sf!(pi_s4; label="π s4")
	plot_sf!(pi_s5; label="π s5")
	plot!(x -> 0, 1:12, label="")
end


# ╔═╡ 1d6e7215-ccd0-4252-afc8-f48bfd43889d
md"""md
#### Dane

"""

# ╔═╡ 7c12ebe4-9ae5-42db-8f4c-5acf57a12b11
begin 
	ssend_single = CSV.read("lab1/measurements/csv/ssend_single_node.csv", DataFrame)
	HTMLTable(ssend_single)
end

# ╔═╡ a87255d9-6585-4437-96f6-d0a29845eefb
begin 
	ssend_two = CSV.read("lab1/measurements/csv/ssend_two_nodes.csv", DataFrame)
	HTMLTable(ssend_two)
end

# ╔═╡ 399ccc73-6eff-4476-a460-4aaab2203ef9
begin 
	ibsend_single = CSV.read("lab1/measurements/csv/ibsend_single_node.csv", DataFrame)
	HTMLTable(ibsend_single)
end

# ╔═╡ 349b7ea0-2d04-49f8-a10f-309ccf20a4c2
begin 
	ibsend_two = CSV.read("lab1/measurements/csv/ibsend_two_nodes.csv", DataFrame)
	HTMLTable(ibsend_two)
end

# ╔═╡ 0fc26550-ac42-4a2a-aafc-a22b92593649
begin 
	raw_data_pi =CSV.read("lab2/data/data.csv", DataFrame)
	HTMLTable(raw_data_pi)
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
BrowseTables = "5f4fecfd-7eb0-5078-b7f6-ad1f2563c22a"
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
InteractiveUtils = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
Markdown = "d6f4376e-aef5-505a-96c1-9c027394607a"
Measurements = "eff96d63-e80a-5855-80a2-b1b0885c5ab7"
Query = "1a8c2f83-1ff3-5112-b086-8aa67b057ba1"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
StatsPlots = "f3b207a7-027a-5e70-b257-86293d7955fd"

[compat]
BrowseTables = "~0.3.0"
CSV = "~0.10.3"
DataFrames = "~1.3.2"
Measurements = "~2.7.1"
Query = "~1.0.0"
StatsPlots = "~0.14.33"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.2"
manifest_format = "2.0"

[[deps.AbstractFFTs]]
deps = ["ChainRulesCore", "LinearAlgebra"]
git-tree-sha1 = "6f1d9bc1c08f9f4a8fa92e3ea3cb50153a1b40d4"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.1.0"

[[deps.Adapt]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "af92965fb30777147966f58acb05da51c5616b5f"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.3.3"

[[deps.ArgCheck]]
git-tree-sha1 = "a3a402a35a2f7e0b87828ccabbd5ebfbebe356b4"
uuid = "dce04be8-c92d-5529-be00-80e4d2c0e197"
version = "2.3.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[deps.Arpack]]
deps = ["Arpack_jll", "Libdl", "LinearAlgebra", "Logging"]
git-tree-sha1 = "91ca22c4b8437da89b030f08d71db55a379ce958"
uuid = "7d9fca2a-8960-54d3-9f78-7d1dccf2cb97"
version = "0.5.3"

[[deps.Arpack_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "OpenBLAS_jll", "Pkg"]
git-tree-sha1 = "5ba6c757e8feccf03a1554dfaf3e26b3cfc7fd5e"
uuid = "68821587-b530-5797-8361-c406ea357684"
version = "3.5.1+1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.AxisAlgorithms]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "WoodburyMatrices"]
git-tree-sha1 = "66771c8d21c8ff5e3a93379480a2307ac36863f7"
uuid = "13072b0f-2c55-5437-9ae7-d433b7a33950"
version = "1.0.1"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BrowseTables]]
deps = ["ArgCheck", "DefaultApplication", "DocStringExtensions", "Parameters", "Tables"]
git-tree-sha1 = "2df4c05941860fd6149c349422d584174044718a"
uuid = "5f4fecfd-7eb0-5078-b7f6-ad1f2563c22a"
version = "0.3.0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "SentinelArrays", "Tables", "Unicode", "WeakRefStrings"]
git-tree-sha1 = "9310d9495c1eb2e4fa1955dd478660e2ecab1fbb"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.3"

[[deps.Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "4b859a208b2397a7a623a03449e4636bdb17bcf2"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+1"

[[deps.Calculus]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f641eb0a4f00c343bbc32346e1217b86f3ce9dad"
uuid = "49dc2e85-a5d0-5ad3-a950-438e2897f1b9"
version = "0.5.1"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "c9a6160317d1abe9c44b3beb367fd448117679ca"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.13.0"

[[deps.ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "bf98fa45a0a4cee295de98d4c1462be26345b9a1"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.2"

[[deps.Clustering]]
deps = ["Distances", "LinearAlgebra", "NearestNeighbors", "Printf", "SparseArrays", "Statistics", "StatsBase"]
git-tree-sha1 = "75479b7df4167267d75294d14b58244695beb2ac"
uuid = "aaaa29a8-35af-508c-8bc3-b662a17a0fe5"
version = "0.14.2"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "Colors", "FixedPointNumbers", "Random"]
git-tree-sha1 = "12fc73e5e0af68ad3137b886e3f7c1eacfca2640"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.17.1"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "024fe24d83e4a5bf5fc80501a314ce0d1aa35597"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.0"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "417b0ed7b8b838aa6ca0a87aadf1bb9eb111ce40"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.8"

[[deps.Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "96b0bc6c52df76506efc8a441c6cf1adcb1babc4"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.42.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.Contour]]
deps = ["StaticArrays"]
git-tree-sha1 = "9f02045d934dc030edad45944ea80dbd1f0ebea7"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.5.7"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "cc70b17275652eb47bc9e5f81635981f13cea5c8"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.9.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Reexport", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "ae02104e835f219b8930c7664b8012c93475c340"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.3.2"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "3daef5523dd2e769dad2365274f760ff5f282c7d"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.11"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.DataValues]]
deps = ["DataValueInterfaces", "Dates"]
git-tree-sha1 = "d88a19299eba280a6d062e135a43f00323ae70bf"
uuid = "e7dc6d0d-1eca-5fa6-8ad6-5aecde8b7ea5"
version = "0.4.13"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DefaultApplication]]
deps = ["InteractiveUtils"]
git-tree-sha1 = "fc2b7122761b22c87fec8bf2ea4dc4563d9f8c24"
uuid = "3f0dd361-4fe0-5fc6-8523-80b14ec94d85"
version = "1.0.0"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[deps.DensityInterface]]
deps = ["InverseFunctions", "Test"]
git-tree-sha1 = "80c3e8639e3353e5d2912fb3a1916b8455e2494b"
uuid = "b429d917-457f-4dbc-8f4c-0cc954292b1d"
version = "0.4.0"

[[deps.Distances]]
deps = ["LinearAlgebra", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "3258d0659f812acde79e8a74b11f17ac06d0ca04"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.7"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.Distributions]]
deps = ["ChainRulesCore", "DensityInterface", "FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "StatsBase", "StatsFuns", "Test"]
git-tree-sha1 = "c43e992f186abaf9965cc45e372f4693b7754b22"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.52"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "b19534d1895d702889b219c382a6e18010797f0b"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.6"

[[deps.Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.DualNumbers]]
deps = ["Calculus", "NaNMath", "SpecialFunctions"]
git-tree-sha1 = "90b158083179a6ccbce2c7eb1446d5bf9d7ae571"
uuid = "fa6b7ba4-c1ee-5f82-b5fc-ecf0adba8f74"
version = "0.6.7"

[[deps.EarCut_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3f3a2501fa7236e9b911e0f7a588c657e822bb6d"
uuid = "5ae413db-bbd1-5e63-b57d-d24a61df00f5"
version = "2.2.3+0"

[[deps.Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ae13fcbc7ab8f16b0856729b050ef0c446aa3492"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.4.4+0"

[[deps.FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[deps.FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "Pkg", "Zlib_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "d8a578692e3077ac998b50c0217dfd67f21d1e5f"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.0+0"

[[deps.FFTW]]
deps = ["AbstractFFTs", "FFTW_jll", "LinearAlgebra", "MKL_jll", "Preferences", "Reexport"]
git-tree-sha1 = "505876577b5481e50d089c1c68899dfb6faebc62"
uuid = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
version = "1.4.6"

[[deps.FFTW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c6033cc3892d0ef5bb9cd29b7f2f0331ea5184ea"
uuid = "f5851436-0d7a-5f13-b9de-f02708fd171a"
version = "3.3.10+0"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "129b104185df66e408edd6625d480b7f9e9823a0"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.18"

[[deps.FillArrays]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "Statistics"]
git-tree-sha1 = "246621d23d1f43e3b9c368bf3b72b2331a27c286"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "0.13.2"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "87eb71354d8ec1a96d4a7636bd57a7347dde3ef9"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.10.4+0"

[[deps.FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Pkg", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "51d2dfe8e590fbd74e7a842cf6d13d8a2f45dc01"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.6+0"

[[deps.GR]]
deps = ["Base64", "DelimitedFiles", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Printf", "Random", "RelocatableFolders", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "9f836fb62492f4b0f0d3b06f55983f2704ed0883"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.64.0"

[[deps.GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Pkg", "Qt5Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "a6c850d77ad5118ad3be4bd188919ce97fffac47"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.64.0+0"

[[deps.GeometryBasics]]
deps = ["EarCut_jll", "IterTools", "LinearAlgebra", "StaticArrays", "StructArrays", "Tables"]
git-tree-sha1 = "83ea630384a13fc4f002b77690bc0afeb4255ac9"
uuid = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
version = "0.4.2"

[[deps.Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[deps.Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "a32d672ac2c967f3deb8a81d828afc739c838a06"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.68.3+2"

[[deps.Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[deps.Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[deps.HTTP]]
deps = ["Base64", "Dates", "IniFile", "Logging", "MbedTLS", "NetworkOptions", "Sockets", "URIs"]
git-tree-sha1 = "0fa77022fe4b511826b39c894c90daf5fce3334a"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "0.9.17"

[[deps.HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[deps.HypergeometricFunctions]]
deps = ["DualNumbers", "LinearAlgebra", "SpecialFunctions", "Test"]
git-tree-sha1 = "65e4589030ef3c44d3b90bdc5aac462b4bb05567"
uuid = "34004b35-14d8-5ef3-9330-4cdb6864b03a"
version = "0.3.8"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "61feba885fac3a407465726d0c330b3055df897f"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.1.2"

[[deps.IntelOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "d979e54b71da82f3a65b62553da4fc3d18c9004c"
uuid = "1d5cc7b8-4909-519e-a0f8-d0f5ad9712d0"
version = "2018.0.3+2"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.Interpolations]]
deps = ["AxisAlgorithms", "ChainRulesCore", "LinearAlgebra", "OffsetArrays", "Random", "Ratios", "Requires", "SharedArrays", "SparseArrays", "StaticArrays", "WoodburyMatrices"]
git-tree-sha1 = "b15fc0a95c564ca2e0a7ae12c1f095ca848ceb31"
uuid = "a98d9a8b-a2ab-59e6-89dd-64a1c18fca59"
version = "0.13.5"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "91b5dcf362c5add98049e6c29ee756910b03051d"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.3"

[[deps.InvertedIndices]]
git-tree-sha1 = "bee5f1ef5bf65df56bdd2e40447590b272a5471f"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.1.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

[[deps.IterTools]]
git-tree-sha1 = "fa6287a4469f5e048d763df38279ee729fbd44e5"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.4.0"

[[deps.IterableTables]]
deps = ["DataValues", "IteratorInterfaceExtensions", "Requires", "TableTraits", "TableTraitsUtils"]
git-tree-sha1 = "70300b876b2cebde43ebc0df42bc8c94a144e1b4"
uuid = "1c8ee90f-4401-5389-894e-7a04a3dc0f4d"
version = "1.0.0"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b53380851c6e6664204efb2e62cd24fa5c47e4ba"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "2.1.2+0"

[[deps.KernelDensity]]
deps = ["Distributions", "DocStringExtensions", "FFTW", "Interpolations", "StatsBase"]
git-tree-sha1 = "591e8dc09ad18386189610acafb970032c519707"
uuid = "5ab0869b-81aa-558d-bb23-cbf5423bbe9b"
version = "0.6.3"

[[deps.LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[deps.LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[deps.LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[deps.Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "Printf", "Requires"]
git-tree-sha1 = "4f00cc36fede3c04b8acf9b2e2763decfdcecfa6"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.15.13"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[deps.Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[deps.Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "7739f837d6447403596a75d19ed01fd08d6f56bf"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.3.0+3"

[[deps.Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "42b62845d70a619f063a7da093d995ec8e15e778"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+1"

[[deps.Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[deps.Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "c9551dd26e31ab17b86cbd00c2ede019c08758eb"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.3.0+1"

[[deps.Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "58f25e56b706f95125dcb796f39e1fb01d913a71"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.10"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.MKL_jll]]
deps = ["Artifacts", "IntelOpenMP_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "Pkg"]
git-tree-sha1 = "e595b205efd49508358f7dc670a940c790204629"
uuid = "856f044c-d86e-5d09-b602-aeab76dc8ba7"
version = "2022.0.0+0"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "3d3e902b31198a27340d0bf00d6ac452866021cf"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.9"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "Random", "Sockets"]
git-tree-sha1 = "1c38e51c3d08ef2278062ebceade0e46cefc96fe"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.0.3"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Measurements]]
deps = ["Calculus", "LinearAlgebra", "Printf", "RecipesBase", "Requires"]
git-tree-sha1 = "88cd033eb781c698e75ae0b680e5cef1553f0856"
uuid = "eff96d63-e80a-5855-80a2-b1b0885c5ab7"
version = "2.7.1"

[[deps.Measures]]
git-tree-sha1 = "e498ddeee6f9fdb4551ce855a46f54dbd900245f"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.1"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.MultivariateStats]]
deps = ["Arpack", "LinearAlgebra", "SparseArrays", "Statistics", "StatsAPI", "StatsBase"]
git-tree-sha1 = "7008a3412d823e29d370ddc77411d593bd8a3d03"
uuid = "6f286f6a-111f-5878-ab1e-185364afe411"
version = "0.9.1"

[[deps.NaNMath]]
git-tree-sha1 = "737a5957f387b17e74d4ad2f440eb330b39a62c5"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.0"

[[deps.NearestNeighbors]]
deps = ["Distances", "StaticArrays"]
git-tree-sha1 = "16baacfdc8758bc374882566c9187e785e85c2f0"
uuid = "b8a86587-4115-5ab1-83bc-aa920d37bbce"
version = "0.4.9"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[deps.Observables]]
git-tree-sha1 = "fe29afdef3d0c4a8286128d4e45cc50621b1e43d"
uuid = "510215fc-4207-5dde-b226-833fc4488ee2"
version = "0.4.0"

[[deps.OffsetArrays]]
deps = ["Adapt"]
git-tree-sha1 = "043017e0bdeff61cfbb7afeb558ab29536bbb5ed"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.10.8"

[[deps.Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ab05aa4cc89736e95915b01e7279e61b1bfe33b8"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.14+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.PCRE_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b2a7af664e098055a7529ad1a900ded962bca488"
uuid = "2f80f16e-611a-54ab-bc61-aa92de5b98fc"
version = "8.44.0+0"

[[deps.PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "e8185b83b9fc56eb6456200e873ce598ebc7f262"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.7"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "85b5da0fa43588c75bb1ff986493443f821c70b7"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.2.3"

[[deps.Pixman_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b4f5d02549a10e20780a24fce72bea96b6329e29"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.40.1+0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.PlotThemes]]
deps = ["PlotUtils", "Requires", "Statistics"]
git-tree-sha1 = "a3a964ce9dc7898193536002a6dd892b1b5a6f1d"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "2.0.1"

[[deps.PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "Printf", "Random", "Reexport", "Statistics"]
git-tree-sha1 = "bb16469fd5224100e422f0b027d26c5a25de1200"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.2.0"

[[deps.Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "GeometryBasics", "JSON", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg", "PlotThemes", "PlotUtils", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "Requires", "Scratch", "Showoff", "SparseArrays", "Statistics", "StatsBase", "UUIDs", "UnicodeFun", "Unzip"]
git-tree-sha1 = "1690b713c3b460c955a2957cd7487b1b725878a7"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.27.1"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "db3a23166af8aebf4db5ef87ac5b00d36eb771e2"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.0"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "d3538e7f8a790dc8903519090857ef8e1283eecd"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.2.5"

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "Markdown", "Reexport", "Tables"]
git-tree-sha1 = "dfb54c4e414caa595a1f2ed759b160f5a3ddcba5"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "1.3.1"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Qt5Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "xkbcommon_jll"]
git-tree-sha1 = "ad368663a5e20dbb8d6dc2fddeefe4dae0781ae8"
uuid = "ea2cea3b-5b76-57ae-a6ef-0a8af62496e1"
version = "5.15.3+0"

[[deps.QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "78aadffb3efd2155af139781b8a8df1ef279ea39"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.4.2"

[[deps.Query]]
deps = ["DataValues", "IterableTables", "MacroTools", "QueryOperators", "Statistics"]
git-tree-sha1 = "a66aa7ca6f5c29f0e303ccef5c8bd55067df9bbe"
uuid = "1a8c2f83-1ff3-5112-b086-8aa67b057ba1"
version = "1.0.0"

[[deps.QueryOperators]]
deps = ["DataStructures", "DataValues", "IteratorInterfaceExtensions", "TableShowUtils"]
git-tree-sha1 = "911c64c204e7ecabfd1872eb93c49b4e7c701f02"
uuid = "2aef5ad7-51ca-5a8f-8e88-e75cf067b44b"
version = "0.9.3"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Ratios]]
deps = ["Requires"]
git-tree-sha1 = "dc84268fe0e3335a62e315a3a7cf2afa7178a734"
uuid = "c84ed2f1-dad5-54f0-aa8e-dbefe2724439"
version = "0.4.3"

[[deps.RecipesBase]]
git-tree-sha1 = "6bf3f380ff52ce0832ddd3a2a7b9538ed1bcca7d"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.2.1"

[[deps.RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "RecipesBase"]
git-tree-sha1 = "995a812c6f7edea7527bb570f0ac39d0fb15663c"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.5.1"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "cdbd3b1338c72ce29d9584fdbe9e9b70eeb5adca"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "0.1.3"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "bf3188feca147ce108c76ad82c2792c57abe7b1f"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.7.0"

[[deps.Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "68db32dff12bb6127bac73c209881191bf0efbb7"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.3.0+0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "0b4b7f1393cff97c33891da2a0bf69c6ed241fda"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.1.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "6a2f7d70512d205ca8c7ee31bfa9f142fe74310c"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.12"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "5ba658aeecaaf96923dce0da9e703bd1fe7666f9"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.1.4"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "6976fab022fea2ffea3d945159317556e5dad87c"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.4.2"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "c3d8ba7f3fa0625b062b82853a7d5229cb728b6b"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.2.1"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "8977b17906b0a1cc74ab2e3a05faa16cf08a8291"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.16"

[[deps.StatsFuns]]
deps = ["ChainRulesCore", "HypergeometricFunctions", "InverseFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "25405d7016a47cf2bd6cd91e66f4de437fd54a07"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "0.9.16"

[[deps.StatsPlots]]
deps = ["AbstractFFTs", "Clustering", "DataStructures", "DataValues", "Distributions", "Interpolations", "KernelDensity", "LinearAlgebra", "MultivariateStats", "Observables", "Plots", "RecipesBase", "RecipesPipeline", "Reexport", "StatsBase", "TableOperations", "Tables", "Widgets"]
git-tree-sha1 = "4d9c69d65f1b270ad092de0abe13e859b8c55cad"
uuid = "f3b207a7-027a-5e70-b257-86293d7955fd"
version = "0.14.33"

[[deps.StructArrays]]
deps = ["Adapt", "DataAPI", "StaticArrays", "Tables"]
git-tree-sha1 = "57617b34fa34f91d536eb265df67c2d4519b8b98"
uuid = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
version = "0.6.5"

[[deps.SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.TableOperations]]
deps = ["SentinelArrays", "Tables", "Test"]
git-tree-sha1 = "e383c87cf2a1dc41fa30c093b2a19877c83e1bc1"
uuid = "ab02a1b2-a7df-11e8-156e-fb1833f50b87"
version = "1.2.0"

[[deps.TableShowUtils]]
deps = ["DataValues", "Dates", "JSON", "Markdown", "Test"]
git-tree-sha1 = "14c54e1e96431fb87f0d2f5983f090f1b9d06457"
uuid = "5e66a065-1f0a-5976-b372-e0b8c017ca10"
version = "0.2.5"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.TableTraitsUtils]]
deps = ["DataValues", "IteratorInterfaceExtensions", "Missings", "TableTraits"]
git-tree-sha1 = "78fecfe140d7abb480b53a44f3f85b6aa373c293"
uuid = "382cd787-c1b6-5bf2-a167-d5b971a19bda"
version = "1.0.2"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "5ce79ce186cc678bbb5c5681ca3379d1ddae11a1"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.7.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "216b95ea110b5972db65aa90f88d8d89dcb8851c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.6"

[[deps.URIs]]
git-tree-sha1 = "97bbe755a53fe859669cd907f2d96aee8d2c1355"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.3.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[deps.Unzip]]
git-tree-sha1 = "34db80951901073501137bdbc3d5a8e7bbd06670"
uuid = "41fe7b60-77ed-43a1-b4f0-825fd5a5650d"
version = "0.1.2"

[[deps.Wayland_jll]]
deps = ["Artifacts", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "3e61f0b86f90dacb0bc0e73a0c5a83f6a8636e23"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.19.0+0"

[[deps.Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4528479aa01ee1b3b4cd0e6faef0e04cf16466da"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.25.0+0"

[[deps.WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "b1be2855ed9ed8eac54e5caff2afcdb442d52c23"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.2"

[[deps.Widgets]]
deps = ["Colors", "Dates", "Observables", "OrderedCollections"]
git-tree-sha1 = "505c31f585405fc375d99d02588f6ceaba791241"
uuid = "cc8bc4a8-27d6-5769-a93b-9d913e69aa62"
version = "0.6.5"

[[deps.WoodburyMatrices]]
deps = ["LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "de67fa59e33ad156a590055375a30b23c40299d3"
uuid = "efce3f68-66dc-5838-9240-27a6d6f5f9b6"
version = "0.5.5"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "1acf5bdf07aa0907e0a37d3718bb88d4b687b74a"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.9.12+0"

[[deps.XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[deps.Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "5be649d550f3f4b95308bf0183b82e2582876527"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.6.9+4"

[[deps.Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4e490d5c960c314f33885790ed410ff3a94ce67e"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.9+4"

[[deps.Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[deps.Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fe47bd2247248125c428978740e18a681372dd4"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.3+4"

[[deps.Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[deps.Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[deps.Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[deps.Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[deps.Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[deps.Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[deps.Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6783737e45d3c59a4a4c4091f5f88cdcf0908cbb"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.0+3"

[[deps.Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "daf17f441228e7a3833846cd048892861cff16d6"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.13.0+3"

[[deps.Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "926af861744212db0eb001d9e40b5d16292080b2"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.0+4"

[[deps.Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[deps.Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[deps.Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "4bcbf660f6c2e714f87e960a171b119d06ee163b"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.2+4"

[[deps.Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "5c8424f8a67c3f2209646d4425f3d415fee5931d"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.27.0+4"

[[deps.Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "79c31e7844f6ecf779705fbc12146eb190b7d845"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.4.0+3"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[deps.Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e45044cd873ded54b6a5bac0eb5c971392cf1927"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.2+0"

[[deps.libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[deps.libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[deps.libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "94d180a6d2b5e55e447e2d27a29ed04fe79eb30c"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.38+0"

[[deps.libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"

[[deps.x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[deps.x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[deps.xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "ece2350174195bb31de1a63bea3a41ae1aa593b6"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "0.9.1+5"
"""

# ╔═╡ Cell order:
# ╟─ed491677-bca1-4c08-a568-b062b1ee266d
# ╟─77326d30-e595-4d99-8a08-c5752e8e10cc
# ╟─2f94ff6a-8102-4baf-a253-9d455e3f215e
# ╟─f594eba6-70a8-4167-a910-6ffc8a872a13
# ╟─aecadb90-bf2c-4011-a70a-d27e38125bb6
# ╟─6e8d59e4-661f-4b13-a983-c10e2acb07d9
# ╟─806718ac-7efb-4083-8cea-989c730b5765
# ╟─74bcdc04-ba8e-4bc9-bc44-29008045005f
# ╟─86bc5974-d0ff-4d86-bce7-0d87114529a4
# ╟─b75e6d97-432d-4418-82f8-c7e25106c120
# ╟─ed774b67-b8ca-4215-b03f-542ff83df9f7
# ╟─d7515cd9-fbbd-4f82-85f7-a3ad8b93aa38
# ╟─fc31e18d-2524-45b4-be45-2b9deaee4f76
# ╟─f0f03907-6aba-433b-9878-60bbc6c7f62e
# ╟─803d33bc-0320-4c67-9573-c7b98a869a2a
# ╟─419114e5-54a1-4ba6-8914-0327229711ee
# ╟─a0c5dc3f-be3d-4a3e-a3ae-4eea77f8dfc5
# ╟─faa0408d-f418-413f-8480-b63ffbdb4a9d
# ╟─a7a4a356-2493-4f99-9652-6b9e9e4b0af2
# ╟─c88f6105-1e02-48d6-8860-e9c37c96a4fa
# ╟─c3780def-41ca-4648-ad73-034f3f782dc3
# ╟─8953fb85-6e35-4f2f-8018-0e37f393b1f4
# ╟─8bf38410-d62a-44ae-8683-08e327f9b1e7
# ╟─0a97c46b-3d85-4737-a702-4c4e076ff81d
# ╟─9433a028-f000-48af-a5d1-b7672d2cf936
# ╟─5db2f023-f4ed-47cc-98e5-edadac859907
# ╟─801fbbda-2064-4ab0-948b-487ace41781f
# ╟─ce0e8a8e-3fca-49dc-8103-09b6805d6f16
# ╟─f7eda722-9660-42ac-89ec-dfc3d9933821
# ╟─b9a46140-5ed7-4c3f-9f1f-900724f35a37
# ╟─737a4839-a22d-4293-9642-4c0592f59403
# ╟─b9328834-2d84-4e02-bb07-8dc9b1c7e01b
# ╟─21121a41-ff78-4a50-aa26-d57d28c6860a
# ╟─b983255e-4174-4ff3-84f9-62c29f638364
# ╟─f126d7c8-3aee-44cf-8bbf-373521315fae
# ╟─1d6e7215-ccd0-4252-afc8-f48bfd43889d
# ╠═7c12ebe4-9ae5-42db-8f4c-5acf57a12b11
# ╠═a87255d9-6585-4437-96f6-d0a29845eefb
# ╠═399ccc73-6eff-4476-a460-4aaab2203ef9
# ╠═349b7ea0-2d04-49f8-a10f-309ccf20a4c2
# ╠═0fc26550-ac42-4a2a-aafc-a22b92593649
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
