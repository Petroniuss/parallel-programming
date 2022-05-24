# rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

source $HOME/.cargo/env

# git
sudo yum install git

# go into specific directory where there's plenty of memory.
df -h

# clone the repo
git clone https://github.com/Petroniuss/parallel-programming.git

# from local to remote
scp -i labsuser.cer ./word-counter/data/gutenberg-500M.txt.gz hadoop@ec2-54-236-56-193.compute-1.amazonaws.com:/mnt1/hadoop/parallel-programming/hadoop/word-counter/word-counter/data

# unzip
gzip -d data/gutenberg-500M.txt.gz

carog build --release

cp ./target/release/wordcounter_mapper .
cp ./target/release/wordcounter_reducer .
cp ./target/release/wordcounter_single .

iconv -f UTF-8 -t ASCII -c data/gutenberg-500M.txt > data/gtenberg-500M.txt

hdfs dfs -mkdir wc-input
hdfs dfs -put data/gtenberg-500M.txt wc-input
hdfs dfs -rm -r wc-output

time hadoop jar /usr/lib/hadoop/hadoop-streaming.jar -files wordcount_mapper,wordcount_reducer -mapper wordcount_mapper -reducer wordcount_reducer -input wc-input -output wc-output


for i in {1..10}
do
  hdfs dfs -put data/gtenberg-500M.txt "wc-input/g-${i}.txt"
done

for i in {10..20}
do
  hdfs dfs -put data/gtenberg-500M.txt "wc-input/g-${i}.txt"
done
