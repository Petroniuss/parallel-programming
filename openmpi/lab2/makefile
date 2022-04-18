CC = "mpicc"
MPIEXEC = "mpiexec"

build/ping_pong: src/pi.c build
	$(CC) -o build/pi src/pi.c

build:
	mkdir -p ./build

clean:
	rm -rf ./build/*