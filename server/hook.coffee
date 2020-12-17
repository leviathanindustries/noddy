
# write any hooks here as endpoints that other services can push events to

API.add 'hook', post: () -> return API.hook this.bodyParams

API.add 'hook/github', post: () -> return API.hook.github this.bodyParams


API.hook = (opts) ->
  API.mail.send
    from: 'sysadmin@cottagelabs.com'
    to: 'mark@cottagelabs.com'
    subject: 'Githook'
    text: JSON.stringify opts, '', 2
  return true

# for any github webhook action, catch it and trigger something here, which can be configured in settings
# when these hook URLs are hit, they woudl also need to be called on the specific machine 
# that can action them - e.g. the specific dev API machine, or specific local API machine
# and it then controls roll-out to cluster machines where necessary
# https://developer.github.com/webhooks/
# https://developer.github.com/v3/activity/events/types/#pushevent
API.hook.github = (opts) ->
  if opts.ref? and opts.repository?
    repo = opts.repository.full_name # will be like leviathanindustries/noddy, not just the repo name
    if API.settings.hook?.github?[repo]? or API.settings.hook?.github?[repo.split('/').pop()]?
      settings = API.settings.hook.github[repo] ? API.settings.hook.github[repo.split('/').pop()]
      if opts.ref_type is 'branch' and settings.branches
        branch = opts.ref
        folder = if settings.branches is true then (if settings[branch]?.folder? then settings[branch].folder else settings.folder + '/' + branch) else settings.branches + '/' + branch
        # create the folder for this branch if not existing yet
        # if such a folder does not already exist. And then git clone the repo into it
        # and then switch to the new branch
      else
        # for now everything else is assumed to be a git push, requiring a local pull
        branch = opts.ref.split('/').pop()
        folder = if branch is 'master' then settings.folder else (if settings.branches is true then settings.folder else settings.branches) + '/' + branch
        # execute a pull in the specified folder of the branch in question
        # move into the folder first if necessary - may also need to create
        # also, may need to check out the branch if necessary

      # creating branches into folders is designed to allow for lots of different dev versions of sites to be running at different API addresses
      # so these different versions may also need the settings out of some other folder - e.g if there is a live site 
      # running off master, then the live one will have live settings, but if there is a dev site running off develop, 
      # then there is likely a dev settings file in the local develop folder somewhere, and these won't come with the branch 
      # pull because settings quite often contain secrets that are only typed in on the running machine. 
      # so, need a way to pull the right settings file when trying to deploy a branch that isn't master of the main dev one...
      # but also needs to work without knowing the name of the branches, as any branch name could be used later

      if false
        # if the above fails, e.g. there is something in the folder stopping the pull from succeeding, 
        # catch that info and send a warning somewhere
      else if settings.post or settings[branch]?.post?
        post = settings.post ? settings[branch].post
        # execute whatever command is specified in settings.post, e.g. could be node build.js
        # could also be a deploy command, to push the changes out to the cluster
        # if the executed command fails, send a warning somewhere


