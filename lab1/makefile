CC = "/usr/local/bin/mpicc"

default: run-ping-pong

run-ping-pong: build/ping_pong
	mpiexec -n 2 ./build/ping_pong

build/ping_pong: src/ping_pong.c build
	@echo "Building ping_pong"
	$(CC) -o build/ping_pong src/ping_pong.c

build:
	mkdir -p ./build

clean:
	@echo "Cleaning build"
	rm -rf ./build/*