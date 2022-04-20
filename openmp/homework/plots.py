from matplotlib import pyplot as plt
import pandas as pd
import sys

def main(size, variants):
    plt.rcParams["figure.figsize"] = [7.50, 3.50]
    plt.rcParams["figure.autolayout"] = True
    plt.rcParams['lines.linewidth'] = .7


    for variant in variants:
        plot(variant, size)


def plot(variant, size):
    headers = ['Threads no','Generating','Splitting to buckets','Sorting buckets','Writing sorted buckets','Overall']

    df = pd.read_csv(f'results/res_{variant}_{size}.tsv', names=headers)

    plot = df.set_index('Threads no').plot(style='.-')
    plot.set_ylabel('Time [s]')
    plot.set_title(f'Execution time for variant=1 and SIZE={size}')

    plt.savefig(f'results/plot_{variant}_{size}.png')



if __name__ == "__main__":
   main(int(sys.argv[1]), sys.argv[2].split(','))

