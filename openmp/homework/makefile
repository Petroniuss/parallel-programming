CC = g++-11 -Wall

.PHONY: clean run all

all: build/measure

run: build/measure
	./build/measure --threads=8 --size=100000 --repeat=1 --version=1

build/measure: measure.cpp build
	$(CC) measure.cpp -o build/measure -fopenmp -std=c++11

build:
	mkdir -p ./build

clean:
	rm -rf ./build/*