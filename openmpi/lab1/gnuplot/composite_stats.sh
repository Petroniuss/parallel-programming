#!/bin/bash 

# input: data files with two columns: x, y
# output: x, mean of y, std of y
# calculated for each row of all files.
awk '
    {
        x=$1
        y=$2
        X[FNR] = x
        n[FNR] += 1
        delta = y - mean[FNR]
        mean[FNR] += delta/n[FNR]
        delta2 = y - mean[FNR]
        M2[FNR] += delta * delta2
    }
    END {
    for(i=1;i<=FNR;i++)
        if(n[i]<2)
                print X[i], mean[i], 0
        else
                print X[i], mean[i], sqrt(M2[i]/(n[i]-1))
    }' $@

