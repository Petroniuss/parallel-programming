CC = "mpicc"
MPIEXEC = "mpiexec"
ifeq ($(VNODE_CLUSTER_SINGLE_NODE), "true")
	MPIEXEC = "mpiexec -machinefile ./vcluster-config/single_node"
endif
ifeq ($(VNODE_CLUSTER_TWO_NODES), "true")
	MPIEXEC = "mpiexec -machinefile ./vcluster-config/two_nodes"
endif

TRIALS ?= 3
DATA_FILE_ID ?= 0
DATA_TO_BE_TRANFERRED_BYTES = 100000000 # 100 MB
MAX_MESSAGE_SIZE = 10000000 # 10 MB
MESSAGE_STEP_SIZE_BYTES = 50000 # 50 kB

# homework
hw-send-single-node-plot: 
	mkdir -p ./plots
	./gnuplot/composite_stats.sh "./build/hw_send_single_node-*.dat" > "./build/hw_send_single_node_composite.dat"
	gnuplot -persistent gnuplot/hw_send_single_node.gpi

hw-send-measure-single-node-multiple-runs:
	for (( i=1; i<=${TRIALS}; i++ )) ; do \
		$(MAKE) hw-send-measure-single-node DATA_FILE_ID=$$i ; \
	done

hw-send-measure-single-node: build/hw_send 
	rm -f "build/hw_send-${DATA_FILE_ID}.dat"
	for message_size in 1 32 64 256 512 1024 2048 4096 8192 16384 32768 ; do \
		$(MPIEXEC) -n 2 ./build/hw_send $$message_size $(DATA_TO_BE_TRANFERRED_BYTES) "build/hw_send_single_node-${DATA_FILE_ID}.dat"; \
    done

	message_size=$(MESSAGE_STEP_SIZE_BYTES) ; while [[ $$message_size -le $(MAX_MESSAGE_SIZE) ]] ; do \
		$(MPIEXEC) -n 2 ./build/hw_send $$message_size $(DATA_TO_BE_TRANFERRED_BYTES) "build/hw_send_single_node-${DATA_FILE_ID}.dat"; \
        ((message_size = message_size + $(MESSAGE_STEP_SIZE_BYTES))) ; \
    done

build/hw_send: src/hw_send.c build
	$(CC) -o build/hw_send src/hw_send.c

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
