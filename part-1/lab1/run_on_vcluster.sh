#!/bin/bash 
export VNODE_CLUSTER_SINGLE_NODE=true
make ssend-multiple-runs
make ibsend-multiple-runs

export VNODE_CLUSTER_SINGLE_NODE=false
export VNODE_CLUSTER_TWO_NODES=true
make ssend-multiple-runs
make ibsend-multiple-runs