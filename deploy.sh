

'''commands needed to install everything noddy could use
meteor for running meteor app without bundling
curl https://install.meteor.com/ | sh

chrome for http.puppeteer
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - 
sudo sh -c 'echo "deb https://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
sudo apt-get update
sudo apt-get install google-chrome-stable -q -y

canvas stuff for convert.svg2png
sudo apt-get install libcairo2-dev libjpeg-dev libpango1.0-dev libgif-dev build-essential g++

which caused an error on a newer machine so had to do this
wget -q -O /tmp/libpng12.deb http://mirrors.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1_amd64.deb && sudo dpkg -i /tmp/libpng12.deb && rm /tmp/libpng12.deb

then still fails on libgif which appears to be out of date. Going to have to disable all this stuff I think

antiword for some text extractions
sudo apt-get install antiword

tesseract for some image conversions
sudo apt install tesseract-ocr

phash was required by jimp on my image server, but it is obsolete now. Needs an alternative, may have to write phash myself

'''

# to start up direct on command line
# typically use 3002 for dev and 3333 for live, and can add those URLs and ports to nginx config
# remember also add internal IPs to index server firewall so they can contact it
# and need to set some env variables for meteor to run properly
# export MONGO_URL=http://nowhere && meteor --port 3002 --settings settings.json

# can also start with setting job startup differently as that is the main one that changes on cluster machines
# export MONGO_URL=http://nowhere && NODDY_SETTINGS_JOB_STARTUP=true && meteor --port 3002 --settings settings.json


# ALTERING PRODUCTION DEPLOYMENT TO PM2 INSTEAD OF FOREVER
# THE BELOW SCRIPT IS STILL IN TESTING AND NEEDS TO BE UPDATED TO USE PM2 INSTEAD
# HERE ARE THE INSTRUCTIONS FOR INSTALLING PM2

# npm install pm2 -g
# pm2 install pm2-logrotate
# pm2 set pm2-logrotate:compress true
# pm2 set pm2-logrotate:max_size 1G
# pm2 set pm2-logrotate:retain 10

# and will make a pm2 ecosystem file, which will be loaded when pm2 starts the app (which it must do from inside the folder)
# if pm2 env has to change, must specifically start/restart with the --update-env flag
# pm2 will restart apps after machine restart by running pm2 startup (and later running apps can be added with pm2 save)

# https://pm2.io/doc/en/runtime/guide/ecosystem-file
# https://github.com/keymetrics/pm2-logrotate
# https://github.com/Unitech/pm2

# deploying with pm2 will need the unzipped meteor bundle and the ecosystem file, as well as the meteor settings.
# Meteor env vars should go in the ecosystem file. These things should all go in one folder, and pm2 should be called from there
# should use datestamped noddy_* folder names and then a noddy folder name symlinked to that, so can try fresh installs but roll back on failure just by changing the symlink
# so meteor settings will have to be written into the env settings if pm2 ecosystem config file
# or could build the entire pm2 file from settings file
# pm2 has deployment ecosystem configs too - can that be used to deploy instead of this script?

# should have an arg parse to optionally just run a settings update instead of full deploy
SETTINGS_FILE="settings.json"
SETTINGS_ONLY=false
if [ "$1" == "-settings" ]
  then
    SETTINGS_ONLY=true
    if [ "$2" != "" ]
      then
        SETTINGS_FILE=$2
    fi
elif [ "$2" != "" ]
  then
    SETTINGS_FILE=$2
fi

# need meteor installed, and jq and curl
# need an ssh key that will allow ssh into the cluster machines
# need to be the right user on this machine to match the user will be ssh-ing into (could add user specification, but not needed yet)
# cluster machines need node and nvm installed, and node forever

if [ "$SETTINGS_ONLY" == false ]
  then
    # in the meteor app file on the dev machine (assuming building on same arch):
    # (or can clone the repo onto the cluster machine and build it there, BUT would need to install meteor and also have any service and other API files copied into it)
    echo "Starting meteor build"
    npm install --production
    meteor build ~ --server-only
    echo "Finished build"
  else
    echo "Starting settings update"
fi

DATE="$(date +%Y-%m-%d_%H%M)"
NODE_V="$(meteor node -v)"
JSETTINGS="$(cat $SETTINGS_FILE)"
IPS=$(echo $JSETTINGS | jq '.cluster.ip[]' | tr ',' '\n' | tr -d '"')
INDEXES=$(echo $JSETTINGS | jq '.es.url[]' | tr ',' '\n' | tr -d '"' | tr -d 'http://' | tr -d 'https://' | tr -d ':9200')
LN=$(echo $JSETTINGS | jq '.cluster.ip|length')
NODDY_V=$(echo $JSETTINGS | jq '.version')
NODDY_DEV=$(echo $JSETTINGS | jq '.dev')
ROOT=$(echo $JSETTINGS | jq '.cluster.root')
if [ $ROOT == "" ] || [ $ROOT == null ]
  then
    ROOT="https://api.cottagelabs.com"
fi
PORT=$(echo $JSETTINGS | jq '.cluster.port')
if [ "$PORT" == "" ] || [ $PORT == null ]
  then
    PORT=3000
fi

echo "$DATE: Updating the settings object for cluster settings"
CSETTINGS=$(echo $JSETTINGS | jq '.cluster.settings')
CSK=$(echo $JSETTINGS | jq '.cluster.settings|keys')
for K in $CSK
do
  # need to take account of key names that are dot noted e.g thing.value - would it work just to pass those right to jq as the var?
  V=$(echo $CSETTINGS | jq ".$K")
  echo "Setting $K to $V"
  JSETTINGS=$(echo $JSETTINGS | jq ".$K=$V")
done

printf "\nUpdating $LN cluster machines\n"
echo "Will be checking for node version " $NODE_V

# would it be worth checking every index machine to ensure they all have the proper 
# firewall settings and running index? and that they are in the cluster?
# probably that is a separate deploy task, but could be written in here and triggered 
# with a command line argument, so that when new cluster machines are added their 
# configs can be taken care of from here
# if so, also need to make sure the index machines can talk to each other, and can run snapshot backups, so need ports for that too

# also if the main gateway machine went down, would need this script to quickly deploy another one
# which would need different nginx and firewall settings

# could also add the ability to actually create a new gateway or cluster or ES machine
# using this script to spin up new machines...

COUNTER=0
for IP in $IPS
do
  let "COUNTER++"
  if [ "$SETTINGS_ONLY" == true ]
    then
      printf "\n$COUNTER: Updating cluster IP $IP with new settings\n"
      #ssh $IP "source ~/.nvm/nvm.sh && forever stopall && MONGO_URL=http://nowhere ROOT_URL=$ROOT PORT=$PORT METEOR_SETTINGS=$CSETTINGS forever start -l ~/forever.log -o ~/out.log -e ~/err.log ~/bundle/main.js"
    else
      CV=$(curl -s -X GET http://$IP:$PORT/api | jq '.version')
      printf "\n$COUNTER: Updating cluster IP $IP from version $CV to version $NODDY_V\n"
    
      # update the node version running on the cluster machine if necessary. node -v will output it, then nvm install x will change it
      CNV=$(ssh $IP "source ~/.nvm/nvm.sh && node -v")
      echo "Cluster machine $IP is using node version" $CNV
      if [ "$CNV" != "$NODE_V" ]
        then
          echo "Updating cluster machine node version to" $NODE_V
          #ssh $IP "source ~/.nvm/nvm.sh && nvm install $NODE_V"
      fi

      # check that the index machines have the necessary firewall settings to allow this cluster machine to query ES
      for EP in $INDEXES
      do
        echo "Setting firewall on index machine $EP"
        #ssh $EP sudo ufw allow in on eth1 from $IP to any port 9200
      done
      
      #scp ~/noddy.tar.gz $IP:~

      #ssh $IP "source ~/.nvm/nvm.sh && forever stopall && sudo rm -R bundle && tar -xzf noddy.tar.gz && cd bundle/programs/server && npm install"
      #ssh $IP "rm ~/noddy.tar.gz && mv ~/forever.log ~/$DATE_forever.log && mv ~/out.log ~/$DATE_out.log && mv ~/err.log ~/$DATE_err.log"
      # could do some log pruning here eventually, or if disk is getting full

      # if any new machine deps were install via apt or similar, they need to be installed on the cluster machine too
      # look for a deploy_installs.sh file, which should be kept up to date with a list of the installs that need to be run

      # for ref, simple start is node main.js in the bundle folder
      # and for ref, settings can be set from a file by export METEOR_SETTINGS="$(cat cluster_settings.json )"
      #ssh $IP "source ~/.nvm/nvm.sh && LAST_UPDATED=$DATE MONGO_URL=http://nowhere ROOT_URL=$ROOT PORT=$PORT METEOR_SETTINGS=$CSETTINGS forever start -l ~/forever.log -o ~/out.log -e ~/err.log ~/bundle/main.js"
    
      # could trigger a snapshot of the cluster machine as well, for future cluster machine creation
  fi
done

printf "\nDone processing cluster machines\n"

# then can also remove the noddy tar on the main machine
printf "\nCleaning up\n"
#rm ~/noddy.tar.gz

echo "All done"
