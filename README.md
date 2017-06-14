# noddy

The new home of nod


## Making a VM that can run in a noddy cluster

A 2GB DO machine with the latest Ubuntu server works fine, and can have deployment handled by mupx.
Each machine can run 2 instances of noddy, on different ports (see the mup config files).

adduser --gecos "" USERNAME
cd /home/USERNAME
mkdir /home/USERNAME/.ssh
chown USERNAME:USERNAME /home/USERNAME/.ssh
chmod 700 /home/USERNAME/.ssh
mv /root/.ssh/authorized_keys .ssh/
chown USERNAME:USERNAME .ssh/authorized_keys
chmod 600 /home/USERNAME/.ssh/authorized_keys
adduser USERNAME sudo
export VISUAL=vim

visudo
# USERNAME ALL=(ALL) NOPASSWD: ALL

apt-get update
apt-get -q -y install ntp g++ build-essential python

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

curl -X GET https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-5.4.1.deb -o es.deb
dpkg -i es.deb

Need latest java 8 for ES 5.x - which says it does work with openjdk, although old versions had errors
apt-ge install default-jre

cd /etc/elasticsearch
edit elasticsearch.yml to give it a cluster.name, enable bootstrap.memory-lock, network.host: _eth1:ipv4_
also discovery.zen.ping.multicast false and discovery.zen.ping.unicast.hosts list private IP addresses of all cluster machines
and http.cors.enabled

mkdir /etc/systemd/system/elasticsearch.service.d
vim /etc/systemd/system/elasticsearch.service.d/elasticsearch.conf
and add:
[Service]
LimitNOFILE=1000000
LimitMEMLOCK=infinity

vim /etc/default/elasticsearch
and uncomment MAX_LOCKED_MEMORY

vim /etc/elasticsearch/jvm.options
and set xms and xmx to same preferred value

vim /etc/security/limits.conf
elasticsearch hard nproc 100000

cd /usr/share/elasticsearch
sudo bin/elasticsearch-plugin install ingest-attachment
sudo bin/elasticsearch-plugin install repository-s3

TODO read about x-pack and kibana improvements and see if alerting and monitoring features are useful
https://www.elastic.co/products/x-pack
https://www.elastic.co/products/kibana

sudo /bin/systemctl daemon-reload
sudo /bin/systemctl enable elasticsearch.service
sudo systemctl start elasticsearch.service



allow gateway to access 9200 then allow other cluster machines to access 9300
sudo ufw allow in on eth1 from 10.131.190.77 to any port 9200
do similar to allow the other index machines to access 9300
added ufw allow in on eth1 from 10.131.178.95 to any port 9200
and the same for the other apps machine
so that elasticsearch cluster can be queried only via gateway from apps machines on the private network


