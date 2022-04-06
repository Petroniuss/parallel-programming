CC = gcc -Wall

.PHONY: clean run

run: build/bucket_sort
	./build/bucket_sort

build/bucket_sort: src/bucket_sort.c build
	$(CC) src/bucket_sort.c -o build/bucket_sort  -fopenmp

build:
	mkdir -p ./build

clean:
	rm -rf ./build/*