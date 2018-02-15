

API.service.lantern.status = () ->
  return
    processes:
      total: job_process.count('service:lantern')
      running: job_processing.count('service:lantern')
    jobs:
      total: job_job.count('service:lantern')
      done: job_job.count('service:lantern AND done:true')
    results: job_result.count('service:lantern')
    users: Users.count({"roles.lantern":"*"})

API.service.lantern.job = (job) ->
  for i of job.processes
    j = job.processes[i]
    j.doi ?= j.DOI
    j.pmid ?= j.PMID
    j.pmcid ?= j.PMCID
    j.title ?= j.TITLE
    j.title ?= j['Article title']
    j.title = j.title.replace(/\s\s+/g,' ').trim() if j.title
    j.pmcid = j.pmcid.replace(/[^0-9]/g,'') if j.pmcid
    j.pmid = j.pmid.replace(/[^0-9]/g,'') if j.pmid
    j.doi = decodeURIComponent(j.doi.replace(/ /g,'')) if j.doi
    job.processes[i] = {doi:j.doi,pmcid:j.pmcid,pmid:j.pmid,title:j.title,refresh:job.refresh,wellcome:job.wellcome}
  job.function = 'API.service.lantern.process'
  job.complete = 'API.service.lantern.complete'
  job.service = 'lantern'
  job = API.job.create job

  if job.email
    text = 'Dear ' + job.email + '\n\nWe\'ve just started processing a batch of identifiers for you, '
    text += 'and you can see the progress of the job here:\n\n'
    # TODO this bit should depend on user group permissions somehow - for now we assume if a signed in user then lantern, else wellcome
    if job.wellcome
      text += if API.settings.dev then 'http://wellcome.test.cottagelabs.com#' else 'https://compliance.cottagelabs.com#'
    else if API.settings.dev
      text += 'https://lantern.test.cottagelabs.com#'
    else
      text += 'https://lantern.cottagelabs.com#'
    text += job._id
    text += '\n\nIf you didn\'t submit this request yourself, it probably means that another service is running '
    text += 'it on your behalf, so this is just to keep you informed about what\'s happening with your account; '
    text += 'you don\'t need to do anything else.\n\n'
    text += 'You\'ll get another email when your job has completed.\n\n'
    text += 'The Lantern Team\n\nP.S This is an automated email, please do not reply to it.'
    API.mail.send
      from: 'Lantern <lantern@cottagelabs.com>'
      to:job.email
      subject:'Lantern: job ' + (job.name ? job._id) + ' submitted successfully'
      text:text
  return job

API.service.lantern.complete = (job) ->
  if job.email
    text = 'Dear ' + job.email + '\n\nWe\'ve just finished processing a batch '
    text += 'of identifiers for you, and you can download the final results here:\n\n'
    # TODO this bit should depend on user group permissions - for now we assume if a signed in user then lantern, else wellcome
    if job.wellcome
      text += if API.settings.dev then 'http://wellcome.test.cottagelabs.com#' else 'https://compliance.cottagelabs.com#'
    else if API.settings.dev
      text += 'https://lantern.test.cottagelabs.com#'
    else
      text += 'https://lantern.cottagelabs.com#'
    text += job._id
    text += '\n\nIf you didn\'t submit the original request yourself, it probably means '
    text += 'that another service was running it on your behalf, so this is just to keep you '
    text += 'informed about what\'s happening with your account; you don\'t need to do anything else.'
    text += '\n\nThe Lantern Team\n\nP.S This is an automated email, please do not reply to it.'
    API.mail.send
      from: 'Lantern <lantern@cottagelabs.com>'
      to:job.email
      subject:'Lantern: job ' + (job.name ? job._id) + ' completed successfully'
      text:text

API.service.lantern.compliance = (result) ->
  result.compliance_wellcome_standard = false
  result.compliance_wellcome_deluxe = false
  epmc_compliance_lic = if result.epmc_licence then result.epmc_licence.toLowerCase().replace(/ /g,'') else ''
  epmc_lics = epmc_compliance_lic in ['cc-by','cc0','cc-zero']
  result.compliance_wellcome_standard = true if result.in_epmc and (result.aam or epmc_lics)
  result.compliance_wellcome_deluxe = true if result.in_epmc and result.aam
  result.compliance_wellcome_deluxe = true if result.in_epmc and epmc_lics and result.open_access
  # add any new compliance standards calculations here - can call them out to separat function if desired, though they have no other use yet
  return result

API.service.lantern.score = (result) -> return 0 # TODO calculate a lantern "open" score for this article

API.service.lantern.csv = (jobid,ignorefields=[]) ->
  fieldnames = {}
  try fieldnames = if typeof API.settings.service.lantern.fieldnames is 'object' then API.settings.service.lantern.fieldnames else JSON.parse(HTTP.call('GET',API.settings.service.lantern.fieldnames).content)
  fields = API.settings.service.lantern?.fields
  grantcount = 0
  fieldconfig = []
  results = []
  for res in (if typeof jobid is 'string' then API.job.results(jobid) else jobid) # can pass in an object list for simple tests
    result = {}
    if ignorefields.indexOf('originals') is -1
      for lf of res
        if lf not in ignorefields and lf not in ['grants','provenance','process','createdAt','_id'] and lf not in fields
          result[lf] = res[lf]
          fieldconfig.push(lf) if lf not in fieldconfig
    for fname in fields
      if fname not in ignorefields
        printname = fieldnames[fname]?.short_name ? fname
        fieldconfig.push(printname) if printname not in fieldconfig
        if fname is 'authors'
          result[printname] = ''
          for r of res.authors
            result[printname] += if r is '0' then '' else '\r\n'
            result[printname] += res.authors[r].fullName if res.authors[r].fullName
        else if fname in ['repositories','repository_urls','repository_fulltext_urls','repository_oai_ids']
          result[printname] = ''
          if res.repositories?
            for rr in res.repositories
              if rr.name
                result[printname] += '\r\n' if result[printname]
                if fname is 'repositories'
                  result[printname] += rr.name
                else if fname is 'repository_urls'
                  result[printname] += rr.url
                else if fname is 'repository_fulltext_urls'
                  result[printname] += rr.fulltexts.join()
                else if fname is 'repository_oai_ids'
                  result[printname] += rr.oai
        else if fname is 'pmcid' and res.pmcid
          res.pmcid = 'PMC' + res.pmcid if res.pmcid.toLowerCase().indexOf('pmc') isnt 0
          result[printname] = res.pmcid
        else if res[fname] is true
          result[printname] = 'TRUE'
        else if res[fname] is false
          result[printname] = 'FALSE'
        else if not res[fname]? or res[fname] is 'unknown'
          result[printname] = 'Unknown'
        else
          result[printname] = res[fname]
    if 'grant' not in ignorefields or 'agency' not in ignorefields or 'pi' not in ignorefields
      if res.grants?
        for grnt in res.grants
          grantcount += 1
          if 'grant' not in ignorefields
            result[(fieldnames.grant?.short_name ? 'grant').split(' ')[0] + ' ' + grantcount] = grnt.grantId
          if 'agency' not in ignorefields
            result[(fieldnames.agency?.short_name ? 'agency').split(' ')[0] + ' ' + grantcount] = grnt.agency
          if 'pi' not in ignorefields
            result[(fieldnames.pi?.short_name ? 'pi').split(' ')[0] + ' ' + grantcount] = grnt.PI ? 'Unknown'
    if 'provenance' not in ignorefields
      tpn = fieldnames['provenance']?.short_name ? 'provenance'
      result[tpn] = ''
      if res.provenance?
        for pr of res.provenance
          result[tpn] += if pr is '0' then '' else '\r\n'
          result[tpn] += res.provenance[pr]
    results.push result
  gc = 1
  while gc < grantcount+1
    if 'grant' not in ignorefields
      fieldconfig.push (fieldnames.grant?.short_name ? 'grant').split(' ')[0] + ' ' + gc
    if 'agency' not in ignorefields
      fieldconfig.push (fieldnames.agency?.short_name ? 'agency').split(' ')[0] + ' ' + gc
    if 'pi' not in ignorefields
      fieldconfig.push (fieldnames.pi?.short_name ? 'pi').split(' ')[0] + ' ' + gc
    gc++
  fieldconfig.push(fieldnames.provenance?.short_name ? 'provenance') if 'provenance' not in ignorefields
  return API.convert.json2csv {fields:fieldconfig, defaultValue:'Unknown'}, undefined, results



