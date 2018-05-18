# noddy

The new home of nod


## Running noddy

Install meteor.com

Clone this repo.

MONGO_URL="http://nowhere" && meteor --settings settings.json


## Configuring noddy

Edit the settings.json file. If it does not yet exist (it is not included in the repo because it will contain secrets),
then copy the settings_example.json file. Have a look at it to see what to configure.

name and version should be set to your preference.

Using the default noddy logging requires the log section to be completed.
log.connections means all connections to the API will be logged. log.level indicates the log level
('all','trace','debug','info','warn','error','fatal','off'). log.notify indicates whether or not notifications should be sent.
See the "Using logging" section below for more info. log.from and log.to indicate the default from and to email addresses to use.

The es section is also required by default. It needs the es.url to connect to your elasticsearch cluster, the es.index for the
name of the default index to use, the es.version number (as an actual decimal number, not the full semver version - anything
pre-5.x should work, and after 5.x may work or at least with just a few tweaks). es.auth can be populated with index names
that should be accessible, and the name can point to "true" or to an object that contains types within the index to make public -
which itself can be "true" or an object containing the type endpoints to make public. Full granular access control can be managed
with users and groups (see the below section for more info).

The mail section is also necessary by default. It should provide the mail.url to what is assumed to be a mailgun account, along
with the mail.domain registered for that account, the mail.apikey for the account, and the mail.pubkey. The mail section can also
include a mail.error key which should point to an object. That object should contain unique random keys that also point to objects,
within which settings for sending error emails can be set. This allows any remote system that you wish to forward error messages
to do so - see the server/mail.js file and the API.mail.error function for more info. Mail settings for specific services can also
be provided within the service settings (see below for more info about service configuration).

If any of the API you wish to use relies on cron jobs, the cron section must be included and must indicate cron.enabled as "true".
The cron.config can also be customised if so desired.

The cookie section should provide the cookie.name you would like your API to store cookies as on user browsers.


## Using logging

Use API.log to write a log. Provide a string to simply log a message string, or provide an object for more options. In an object,
the message should be in the msg field. You can also provide the error message in the error field, and can set a specific log
level in the level field.

You can also send notifications from a log message using the notify field. This should point to "true" to send a notification to
the default mail.from and mail.to address. or it can be a string providing an email address to send to. Or it can be a string
with a service name to use the default mail of a given service config, or a specific service notification config can be provided
in dot notation as "servicename.notifyname", and if a suitably named mail config object exists in settings.service.servicename.notify
then those settings will be used. Finally notify can just point to a mail config object itself.


## Users and groups


## Services

A service is a set of API endpoints that serve a specific purpose, such as the API of a website. This is a useful way of encapsulating
a set of functionality.

Any specific services that are required should be written in the server/service directory. If they exist there, and if they need
specific config, then their config should be provided in settings.json in an object named with the service name. See some service
examples for how this works in general.

Each service can specify its own service.servicename.mail key, providing a mail object with the usual settings of the mail config
as described above. It can also include a service.servicename.mail.notify key, providing an object that lists names of specific
notification events you would like to trigger. Then the service code can submit logs that include include the notify.service key
with the service name, and the notify.notify key with the notification name - the logger will look up the relevant
service.servicename.mail.notify.notifyname object to retrieve mail settings such as from, to, etc, so that these can be easily
configured via settings rather than code editing. If a relevant notify object does not exist, the default mail settings for the
service will be used instead (and this defaults to the default mail settings for the API if there is no service mail config.
These notifications can also be conveniently turned off by including the disabled key within the notify object, and setting it to true.

The API.mail system will provide a notification email whenever an attempt to send an email fails - this is called a "dropped"
notification. It will try to do this by matching the mail.domain to that of the mail config of any configured service. If there is a
notify section, then it will also look for any specific settings in the notify.dropped object, if it exists.


## Externals


## Scripts


## Making a VM that can run in a noddy cluster

A 2GB 1vCPU DO machine with the latest Ubuntu server works fine.

adduser --gecos "" USERNAME
cd /home/USERNAME
mkdir /home/USERNAME/.ssh
chown USERNAME:USERNAME /home/USERNAME/.ssh
chmod 700 /home/USERNAME/.ssh
mv /root/.ssh/authorized_keys .ssh/
# or make the authorized_keys file and put the necessary key in it
chown USERNAME:USERNAME .ssh/authorized_keys
chmod 600 /home/USERNAME/.ssh/authorized_keys
adduser USERNAME sudo
export VISUAL=vim

visudo
# USERNAME ALL=(ALL) NOPASSWD: ALL

apt-get update
apt-get -q -y install ntp g++ build-essential jq python bpython screen htop git-core curl libxml2-dev libssl-dev

# include anything below that needs to be installed for the noddy app to run
apt-get -q -y install libcairo2-dev libjpeg-dev libpango1.0-dev libgif-dev g++

# these machines will need phantomjs installed too
apt-get -q -y install chrpath libxft-dev libfreetype6 libfreetype6-dev libfontconfig1 libfontconfig1-dev
cd ~
export PHANTOM_JS="phantomjs-2.1.1-linux-x86_64"
wget https://bitbucket.org/ariya/phantomjs/downloads/$PHANTOM_JS.tar.bz2
sudo tar xvjf $PHANTOM_JS.tar.bz2
sudo mv $PHANTOM_JS /usr/local/share
sudo ln -sf /usr/local/share/$PHANTOM_JS/bin/phantomjs /usr/local/bin

dpkg-reconfigure tzdata
# set to Europe/London

dpkg-reconfigure --priority=low unattended-upgrades

vim /etc/ssh/sshd_config
# uncomment PubkeyAuthentication yes
# change PermitRootLogin no
# change PasswordAuthentication no

service ssh restart

ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 3000 # if you want to connect to the app directly (probably best to set just to local network)
ufw enable

# (OR allow only on internal network port like so: ufw allow in on eth1 to any port 22)

# install node
# need to use n to install the same version as the meteor app will be running - may need nvm use x as well?
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | bash
nvm install 8.9.4

# the new machine will have to be given permission to access all index cluster machines (their firewalls only allow specific access on internal network)
# any cluster machines that are destroyed should have their index machine access revoked
sudo ufw allow in on eth1 from MACHINEINTERNALIP to any port 9200




### Build the meteor app and push it to the cluster machine

# in the meteor app file on the dev machine (assuming builing on same arch):
# (or can clone the repo onto the cluster machine and build it there, BUT would need to install meteor and also have any service and other API files copied into it)
npm install --production
meteor build ~ --server-only

# check the node version with meteor node -v or read the .node-version.txt file
# update the node version running on the cluster machine if necessary. node -v will output it, then nvm install x will change it
# if any new machine deps were install via apt or similar, they need to be installed on the cluster machine too

# copy the tar.gz file created by meteor build to the cluster machine and untar it, then cd into it
#scp ~/noddy.tar.gz IP-OF-SERVER:/home/cloo for each cluster machine
# scp the cluster settings file too, if doing manually on the cluster machine, see below to set it into an env variable

#ssh IP-OF-SERVER
# set a CID env variable that is the number of this cluster machine (picked up in logs later for analysis)
# root url would depend on whether dev or live - check settings
# a stringified json rep of the content of settings file to use
# e.g. from code just JSON.stringify(API.settings) or from command line
export CID=1 && export ROOT_URL=https://api.cottagelabs.com && export PORT=3000 && export MONGO_URL=http://nowhere
export METEOR_SETTINGS="$(cat cluster_settings.json )"

# can check the meteor settings is valid json with echo "$METEOR_SETTINGS" | jq .

# before untarring, need to do something to stop the app if it is already running. Look for a main.js pid or if using forever then forever stopall
tar -xzf noddy.tar.gz
cd bundle/programs/server && npm install
cd ../../
node main.js
# or could use forever start main.js
# or more complex forever start -l forever.log -o out.log -e err.log main.js

# on the current cluster machine and the starting machine, can remove the tar if desired
# rm ~/noddy.tar.gz


### The main gateway machine will need more

The main gateway machine also needs nginx and squid, and ufw rules to allow routing connections to the ES cluster

apt-get install mcelog nginx sysv-rc-conf bc vnstat

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


