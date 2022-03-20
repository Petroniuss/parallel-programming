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
