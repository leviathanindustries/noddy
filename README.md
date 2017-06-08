# noddy

The new home of nod


## Making a VM that can run in a noddy cluster

A 2GB DO machine with the latest Ubuntu server works fine, and can have deployment handled by mupx.
Each machine can run 2 instances of noddy, on different ports (see the mup config files).

adduser --gecos "" cloo
cd /home/cloo
mkdir /home/cloo/.ssh
chown cloo:cloo /home/cloo/.ssh
chmod 700 /home/cloo/.ssh
mv /root/.ssh/authorized_keys .ssh/
chown cloo:cloo .ssh/authorized_keys
chmod 600 /home/cloo/.ssh/authorized_keys
adduser cloo sudo
export VISUAL=vim

visudo
# cloo ALL=(ALL) NOPASSWD: ALL

echo "127.0.1.1       "`cat /etc/hostname` >> /etc/hosts
apt-get update
apt-get -q -y install ntp

dpkg-reconfigure tzdata
# set to Europe/London

vim /etc/ssh/sshd_config
# change PermitRootLogin no
# change PasswordAuthentication no

service ssh restart

apt-get -q -y install ufw
ufw allow 22
ufw allow 80
ufw allow 443
ufw enable

(OR allow only on internal network port like so: ufw allow in on eth1 to any port 22)

The main gateway machine also needs nginx and squid, and ufw rules to allow routing connections to the ES cluster

TODO install DO monitoring instead of newrelic.

apt-add-repository ppa:chris-lea/node.js
# requires enter keypress
apt-get update
apt-get -q -y install nodejs

apt-get -q -y install mcelog screen htop nginx git-core curl sysv-rc-conf bc vnstat build-essential libxml2-dev libssl-dev

added a block to gateway nginx config to allow 443 basic auth access to the index
installed apache2-utils on the gateway server for this
and symlinked /etc/nginx/htpasswd to repl/gateway/nginx/htpasswd
and created a user
sudo ln -s /home/cloo/repl/gateway/nginx/htpasswd /etc/nginx/htpasswd
sudo htpasswd -c /home/cloo/repl/gateway/nginx/htpasswd [exampleuser]




## Making an ES VM for the ES cluster

Create a new VM - a cluster of two or more machines with 32GB RAM each is probably ideal.
For test, using a 2GB machine on DO, with Ubuntu OS.
Installing the latest ES 5.x

https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-5.4.1.tar.gz

Need latest java 8 for ES 5.x - update the below commands to get it

add-apt-repository -y ppa:webupd8team/java
apt-get update
echo "debconf shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
echo "debconf shared/accepted-oracle-license-v1-1 seen true" | debconf-set-selections
apt-get -q -y install oracle-java7-installer



OLD ES INSTRUCTIONS

# get elasticsearch
cd /home/cloo
curl -L https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-1.4.4.tar.gz -o elasticsearch.tar.gz
tar -xzvf elasticsearch.tar.gz
ln -s elasticsearch-0.90.7 elasticsearch
rm elasticsearch.tar.gz
cd elasticsearch/bin
git clone git://github.com/elasticsearch/elasticsearch-servicewrapper.git
cd elasticsearch-servicewrapper
mv service ../
cd ../
rm -R elasticsearch-servicewrapper
ln -s /home/cloo/elasticsearch/bin/service/elasticsearch /etc/init.d/elasticsearch
update-rc.d elasticsearch defaults
cd ../
mkdir /home/cloo/repl/index/elasticsearch
mv config /home/cloo/repl/index/elasticsearch
ln -s /home/cloo/repl/index/elasticsearch/config .

# vim config/elasticsearch.yml and uncomment bootstrap.mlockall true
# and uncomment cluster.name: elasticsearch and change to clesc
# uncomment index.number_of_shards and index.number_of_replicas and set to 6 and 1

# vim bin/service/elasticsearch.conf and set.default.ES_HEAP_SIZE=16384
# and set wrapper.logfile.loglevel wrapper.logfile.maxsize wrapper.logfile.maxfiles to WARN 100m and 20

sudo /etc/init.d/elasticsearch start

in elasticsearch.yml
set 
network.host: _eth1:ipv4_
uncomment zen ping multicast false
and in discovery zen ping unicast hosts put the private IP addresses of all machines in the cluster

allow gateway to access 9200 then allow other cluster machines to access 9300
sudo ufw allow in on eth1 from 10.131.190.77 to any port 9200
do similar to allow the other index machines to access 9300

added ufw allow in on eth1 from 10.131.178.95 to any port 9200
and the same for the other apps machine
so that elasticsearch cluster can be queried only via gateway from apps machines on the private network

installed es head and mapper plugins on index machines
sudo /etc/init.d/elasticsearch stop
/home/cloo/elasticsearch/bin/plugin -install mobz/elasticsearch-head
/home/cloo/elasticsearch/bin/plugin install elasticsearch/elasticsearch-mapper-attachments/2.4.3
sudo /etc/init.d/elasticsearch start

uncommented http.jsonp.enable and added http.cors.enabled to config files - they are off by default in new elasticsearch versions




