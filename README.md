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
apt-get update
apt-get install nodejs

apt-get install mcelog screen htop nginx git-core curl sysv-rc-conf bc vnstat build-essential libxml2-dev libssl-dev

added a block to gateway nginx config to allow 443 basic auth access to the index
installed apache2-utils on the gateway server for this
and symlinked /etc/nginx/htpasswd to repl/gateway/nginx/htpasswd
and created a user
sudo ln -s /home/cloo/repl/gateway/nginx/htpasswd /etc/nginx/htpasswd
sudo htpasswd -c /home/cloo/repl/gateway/nginx/htpasswd [exampleuser]




## Making an ES VM for the ES cluster

Create a new VM - a cluster of two or more machines with 32GB RAM each is probably ideal.
Install ES 1.7.6

add-apt-repository -y ppa:webupd8team/java
apt-get update
echo "debconf shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
echo "debconf shared/accepted-oracle-license-v1-1 seen true" | debconf-set-selections
apt-get install oracle-java7-installer

curl -X GET https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.7.6.deb -o es.deb
dpkg -i es.deb

cd /etc/elasticsearch
edit elasticsearch.yml to give it a cluster.name, enable bootstrap.mlockall, network.host: _eth1:ipv4_
also discovery.zen.ping.multicast false and discovery.zen.ping.unicast.hosts list private IP addresses of all cluster machines
and http.cors.enabled and http.jsonp.enable
and index.number_of_shards and index.number_of_replicas and set to 4 and 1

mkdir /etc/systemd/system/elasticsearch.service.d
vim /etc/systemd/system/elasticsearch.service.d/elasticsearch.conf
and add:
[Service]
LimitNOFILE=1000000
LimitMEMLOCK=infinity

vim /etc/default/elasticsearch
and uncomment MAX_LOCKED_MEMORY
and set ES_HEAP_SIZE as required

vim /etc/security/limits.conf
elasticsearch hard nproc 100000

cd /usr/share/elasticsearch
sudo bin/plugin install elasticsearch/elasticsearch-mapper-attachments/2.7.1
sudo bin/plugin install elasticsearch/elasticsearch-cloud-aws/2.7.1
sudo bin/plugin install lukas-vlcek/bigdesk/2.5.0
sudo bin/plugin -install mobz/elasticsearch-head/1.x

sudo /bin/systemctl daemon-reload
sudo /bin/systemctl enable elasticsearch.service
sudo systemctl start elasticsearch.service

cd
curl -X GET https://artifacts.elastic.co/downloads/kibana/kibana-5.4.1-amd64.deb -o kibana.deb
sudo dpkg -i kibana.deb

Edit /etc/kibana/kibana.yml with address of ES (which is prob not available on localhost) and any other necessary settings

sudo /bin/systemctl daemon-reload
sudo /bin/systemctl enable kibana.service
sudo systemctl start kibana.service


allow gateway to access 9200 then allow other cluster machines to access 9300
sudo ufw allow in on eth1 from GATEWAYINTERNALIP to any port 9200
do similar to allow the other index machines to access 9300
added ufw allow in on eth1 from OTHERESCLUSTERIP to any port 9200
and the same for the other apps machine
so that elasticsearch cluster can be queried only via gateway from apps machines on the private network


