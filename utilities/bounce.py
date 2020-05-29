
import json, requests, os

# available on the main machine, set up an nginx pass to the script

# check status endpoint - if all fine, do nothing
# check if local machine has any running instances of the meteor app
# if it does, what screen names are they running in?
# (start instances in named screens to make this more useful)

# if they are running, bounce them in the normal way

# if local ones are not running, go into their screens and rerun the last command
# (which should be the one that started them - check it is, and the settings it had)

# check that after bounce everything is running as normal

# also check status to see if that caused cluster to come back up (if it was down)

# if cluster did not come back up, get the list of IPs of the cluster machines (in the settings files)
# (could be dev or live list or both)
# ssh to those machines
# do the same check on their running processes
# if not running, get into their screens and redo the last command (check it is the command to bring them up)

# once all report that they have done that, re-check status

# if status still not good, try a bounce again

# if status still not good, give up and log the problem

# email whoever needs emailed about this

