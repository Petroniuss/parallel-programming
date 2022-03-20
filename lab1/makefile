CC = "/usr/local/bin/mpicc"

default: run-ping-pong

run-ping-pong: build/ping_pong
	mpiexec -n 2 ./build/ping_pong 16

ping-pong-measure: build/ping_pong 
	# 1024 65536 1048576
	rm -f build/ping_pong.dat
	for n in 1 64 256 1024 65536 1048576 ; do \
		mpiexec -n 2 ./build/ping_pong $$n build/ping_pong.dat; \
    done

ping-pong-plot: ping-pong-measure
	gnuplot -persistent gnuplot/ping_pong.gpi

build/ping_pong: src/ping_pong.c build
	@echo "Building ping_pong"
	$(CC) -o build/ping_pong src/ping_pong.c

build:
	mkdir -p ./build

clean:
	@echo "Cleaning build"
	rm -rf ./build/*
