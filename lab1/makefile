CC = "mpicc"
TRIALS ?= 3
DATA_FILE_ID ?= 0

default: run-ping-pong

# homework








# ping-pong
run-ping-pong: build/ping_pong
	mpiexec -n 2 ./build/ping_pong 16

ping-pong-measure-multiple-runs:
	for (( i=1; i<=${TRIALS}; i++ )) ; do \
		$(MAKE) ping-pong-measure DATA_FILE_ID=$$i ; \
	done
		
ping-pong-measure: build/ping_pong 
	rm -f "build/ping_pong-${DATA_FILE_ID}.dat"
	for n in 1 64 256 1024 65536 1048576 ; do \
		mpiexec -n 2 ./build/ping_pong $$n "build/ping_pong-${DATA_FILE_ID}.dat"; \
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
