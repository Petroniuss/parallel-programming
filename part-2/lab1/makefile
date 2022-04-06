CC = gcc-11 -Wall

.PHONY: clean 

build/measure: measure.cpp build
	g++-11 measure.cpp -o build/measure -fopenmp -std=c++11 

build:
	mkdir -p ./build

clean:
	rm -rf ./build/*