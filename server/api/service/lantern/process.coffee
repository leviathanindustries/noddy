
_formatepmcdate = (date) ->
  try
    date = date.replace(/\//g,'-')
    if date.indexOf('-') isnt -1
      if date.length < 11
        dp = date.split '-'
        if dp.length is 3
          if date.indexOf('-') < 4
            return dp[2] + '-' + dp[1] + '-' + dp[0] + 'T00:00:00Z'
          else
            return date + 'T00:00:00Z'
        else if dp.length is 2
          if date.indexOf('-') < 4
            return dp[1] + dp[0] + date + '-01T00:00:00Z'
          else
            return date + '-01T00:00:00Z'
      return date
    else
      dateparts = date.replace(/  /g,' ').split(' ')
      yr = dateparts[0].toString()
      mth = if dateparts.length > 1 then dateparts[1] else 1
      if isNaN(parseInt(mth))
        mths = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec']
        tmth = mth.toLowerCase().substring(0,3)
        mth = if mths.indexOf(tmth) isnt -1 then mths.indexOf(tmth) + 1 else "01"
      else
        mth = parseInt mth
      mth = mth.toString()
      mth = "0" + mth if mth.length is 1
      dy = if dateparts.length > 2 then dateparts[2].toString() else "01"
      dy = "0" + dy if dy.length is 1
      return yr + '-' + mth + '-' + dy + 'T00:00:00Z'
  catch
    return date


API.service.lantern.process = (proc) ->
  API.log msg: 'Lantern processing', process: proc
  result =
    '_id': proc._id
    pmcid: proc.pmcid
    pmid: proc.pmid
    doi: proc.doi
    title: proc.title
    journal_title: undefined
    pure_oa: false # set to true if found in doaj
    issn: undefined
    eissn: undefined
    publication_date: "Unavailable"
    electronic_publication_date: undefined
    publisher: undefined
    publisher_licence: undefined
    licence: 'unknown' # what sort of licence this has - should be a string like "cc-by"
    epmc_licence: 'unknown' # the licence in EPMC, should be a string like "cc-by"
    licence_source: 'unknown' # where the licence info came from
    epmc_licence_source: 'unknown' # where the EPMC licence info came from (fulltext xml, EPMC splash page, etc.)
    in_epmc: false # set to true if found
    epmc_xml: false # set to true if oa and in epmc and can retrieve fulltext xml from eupmc rest API url
    aam: false # set to true if is an eupmc author manuscript
    open_access: false # set to true if eupmc or other source says is oa
    ahead_of_print: undefined # if pubmed returns a date for this, it will be a date
    romeo_colour: 'unknown' # the sherpa romeo colour
    preprint_embargo: 'unknown'
    preprint_self_archiving: 'unknown'
    postprint_embargo: 'unknown'
    postprint_self_archiving: 'unknown'
    publisher_copy_embargo: 'unknown'
    publisher_copy_self_archiving: 'unknown'
    authors: [] # eupmc author list if available (could look on other sources too?)
    in_core: 'unknown'
    repositories: [] # where CORE says it is. Should be list of objects
    grants:[] # a list of grants, probably from eupmc for now
    confidence: 0 # 1 if matched on ID, 0.9 if title to 1 result, 0.7 if title to multiple results, 0 if unknown article
    score: 0
    provenance: []

  # search eupmc by (in order) pmcid, pmid, doi, title
  identtypes = ['pmcid','pmid','doi','title']
  eupmc
  for st in identtypes
    if not eupmc?
      if proc[st]
        stt = st;
        prst = proc[st]
        if stt is 'title'
          stt = 'search'
          prst = 'TITLE:"' + prst.replace('"','') + '"'
        stt = 'pmc' if stt is 'pmcid'
        res = API.use.europepmc[stt](prst)
        if res?.id and stt isnt 'search'
          eupmc = res
          result.confidence = 1
        else if stt is 'search'
          if res.total is 1
            eupmc = res.data[0]
            result.confidence = 0.9
          else
            prst = prst.replace('"','')
            res2 = API.use.europepmc[stt](prst)
            if res2.total is 1
              eupmc = res2.data[0]
              result.confidence = 0.7

  if eupmc?
    API.log msg: 'Lantern found in eupmc', eupmc: eupmc
    if eupmc.pmcid and result.pmcid isnt eupmc.pmcid
      result.pmcid = eupmc.pmcid
      result.provenance.push 'Added PMCID from EUPMC'
    if eupmc.pmid and result.pmid isnt eupmc.pmid
      result.pmid = eupmc.pmid
      result.provenance.push 'Added PMID from EUPMC'
    if eupmc.doi and result.doi isnt eupmc.doi
      result.doi = eupmc.doi
      result.provenance.push 'Added DOI from EUPMC'
    if eupmc.title and not result.title
      result.title = eupmc.title
      result.provenance.push 'Added article title from EUPMC'
    if eupmc.inEPMC is 'Y'
      result.in_epmc = true
      result.provenance.push 'Confirmed is in EUPMC'
    if eupmc.isOpenAccess is 'Y'
      result.open_access = true
      result.provenance.push 'Confirmed is open access from EUPMC'
    if eupmc.journalInfo?.journal
      if eupmc.journalInfo.journal.title
        result.journal_title = eupmc.journalInfo.journal.title
        result.provenance.push 'Added journal title from EUPMC'
      if eupmc.journalInfo.journal.issn
        result.issn = eupmc.journalInfo.journal.issn
        result.provenance.push 'Added issn from EUPMC'
      if eupmc.journalInfo.journal.essn
        result.eissn = eupmc.journalInfo.journal.essn
        if result.eissn and ( not result.issn or result.issn.indexOf(result.eissn) is -1 )
          result.issn = (if result.issn then result.issn + ', ' else '') + result.eissn
        result.provenance.push 'Added eissn from EUPMC'
    if eupmc.grantsList?.grant
      result.grants = eupmc.grantsList.grant
      result.provenance.push 'Added grants data from EUPMC'
    if eupmc.journalInfo?.dateOfPublication
      result.publication_date = _formatepmcdate eupmc.journalInfo.dateOfPublication
      result.provenance.push 'Added date of publication from EUPMC'
    if eupmc.electronicPublicationDate
      result.electronic_publication_date = _formatepmcdate eupmc.electronicPublicationDate
      result.provenance.push 'Added electronic publication date from EUPMC'

    ft = API.use.europepmc.fulltextXML(result.pmcid) if result.pmcid and result.open_access and result.in_epmc
    if ft is 404
      result.provenance.push 'Not found in EUPMC when trying to fetch full text XML.'
    else if typeof ft isnt 'string' or ft.indexOf('<') isnt 0
      result.provenance.push 'Encountered an error while retrieving the EUPMC full text XML. One possible reason is EUPMC being temporarily unavailable.'
    else
      result.epmc_xml = true
      result.provenance.push 'Confirmed fulltext XML is available from EUPMC'

    lic = API.use.europepmc.licence result.pmcid, eupmc, ft, (not proc.wellcome and API.settings.service.lantern.epmc_ui_only_wellcome)
    if lic isnt false
      result.licence = lic.licence
      result.epmc_licence = lic.licence
      result.licence_source = lic.source
      result.epmc_licence_source = lic.source
      extrainfo = ''
      extrainfo += ' The bit that let us determine the licence was: ' + lic.matched + ' .' if lic.matched
      if lic.match
        extrainfo += ' If licence statements contain URLs we will try to find those in addition to '
        extrainfo += 'searching for the statement\'s text. Here the entire licence statement was: ' + lic.match + ' .'
      result.provenance.push 'Added EPMC licence (' + result.epmc_licence + ') from ' + lic.source + '.' + extrainfo

    if eupmc.authorList?.author
      result.authors = eupmc.authorList.author
      result.provenance.push 'Added author list from EUPMC'
    if result.in_epmc
      aam = API.use.europepmc.authorManuscript result.pmcid, eupmc, undefined, (not proc.wellcome and API.settings.service.lantern.epmc_ui_only_wellcome)
      if aam.aam is false
        result.aam = false
        result.provenance.push 'Checked author manuscript status in EUPMC, found no evidence of being one'
      else if aam.aam is true
        result.aam = true
        result.provenance.push 'Checked author manuscript status in EUPMC, found in ' + aam.info
      else if aam.info.indexOf('404') isnt -1
        result.aam = false
        result.provenance.push 'Unable to locate Author Manuscript information in EUPMC - could not find the article in EUPMC.'
      else if aam.info.indexOf('error') isnt -1
        result.aam = 'unknown'
        result.provenance.push 'Error accessing EUPMC while trying to locate Author Manuscript information. EUPMC could be temporarily unavailable.'
      else if aam.info.indexOf('blocking') isnt -1
        result.aam = 'unknown'
        result.provenance.push 'Error accessing EUPMC while trying to locate Author Manuscript information - EUPMC is blocking access.'
      else
        result.aam = 'unknown'
  else
    result.provenance.push 'Unable to locate article in EPMC.'

  if not result.doi and not result.pmid and not result.pmcid
    result.provenance.push 'Unable to obtain DOI, PMID or PMCID for this article. Compliance information may be severely limited.'

  if result.doi
    crossref = API.use.crossref.works.doi result.doi
    if crossref.status is 'success'
      c = crossref.data;
      result.confidence = 1 if not result.confidence
      result.publisher = c.publisher
      result.provenance.push 'Added publisher name from Crossref'
      if not result.issn and c.ISSN and c.ISSN.length > 0
        result.issn = c.ISSN[0]
        result.provenance.push 'Added ISSN from Crossref'
      if not result.journal_title and c['container-title'] and c['container-title'].length > 0
        result.journal_title = c['container-title'][0]
        result.provenance.push 'Added journal title from Crossref'
      if not result.authors and c.author
        result.authors = c.author
        result.provenance.push 'Added author list from Crossref'
      if not result.title and c.title and c.title.length > 0
        result.title = c.title[0]
        result.provenance.push 'Added article title from Crossref'
    else
      result.provenance.push 'Unable to obtain information about this article from Crossref.'

    # should this use base / dissemin / oab resolve instead?
    if result.doi
      core = API.use.core.articles.doi result.doi
      if core.data?.id
        result.in_core = true
        result.provenance.push 'Found DOI in CORE'
        cc = core.data
        if not result.authors and cc.authors
          result.authors = cc.author
          result.provenance.push 'Added authors from CORE'
        if cc.repositories?.length > 0
          for rep in cc.repositories
            rc = {name:rep.name}
            rc.oai = rep.oai if rep.oai?
            if rep.uri
              rc.url = rep.uri
            else
              try
                repo = API.use.opendoar.search rep.name
                if repo.status is 'success' and repo.total is 1 and repo.data[0].url
                  rc.url = repo.data[0].url
                  result.provenance.push 'Added repo base URL from OpenDOAR'
                else
                  result.provenance.push 'Searched OpenDOAR but could not find repo and/or URL'
              catch
                result.provenance.push 'Tried but failed to search OpenDOAR for repo base URL'
            rc.fulltexts = []
            if cc.fulltextUrls
              for fu in cc.fulltextUrls
                if fu.indexOf('core.ac.uk') is -1 and rep.fulltexts.indexOf(fu) is -1 and (not rep.url or ( rep.url and fu.indexOf(rep.url.replace('http://','').replace('https://','').split('/')[0]) isnt -1 ) )
                  rc.fulltexts.push resolved
            result.repositories.push rc
          result.provenance.push 'Added repositories that CORE claims article is available from'
        if not result.title and cc.title
          result.title = cc.title
          result.provenance.push 'Added title from CORE'
      else
        result.in_core = false
        result.provenance.push 'Could not find DOI in CORE'
  else
    result.provenance.push 'Not attempting Crossref or CORE lookups - do not have DOI for article.'

  if result.grants.length > 0
    for g of result.grants
      gr = result.grants[g]
      if gr.grantId
        grid = gr.grantId
        grid = grid.split('/')[0] if gr.agency?.toLowerCase().indexOf('wellcome') isnt -1
        gres = API.use.grist.grant_id grid
        if gres.total and gres.total > 0 and gres.data.Person
          ps = gres.data.Person
          pid = ''
          pid += ps.Title + ' ' if ps.Title
          pid += ps.GivenName + ' ' if ps.GivenName
          pid += ps.Initials + ' ' if not ps.GivenName and ps.Initials
          pid += ps.FamilyName if ps.FamilyName
          result.grants[g].PI = pid
          result.provenance.push 'Found Grant PI for ' + grid + ' via Grist API'
      else
        result.provenance.push 'Tried but failed to find Grant PI via Grist API'
  else
    result.provenance.push 'Not attempting Grist API grant lookups since no grants data was obtained from EUPMC.'

  if result.pmid and not result.in_epmc
    result.ahead_of_print = API.use.pubmed.aheadofprint result.pmid
    if result.ahead_of_print isnt false
      result.provenance.push 'Checked ahead of print status on pubmed, date found ' + result.ahead_of_print
    else
      result.provenance.push 'Checked ahead of print status on pubmed, no date found'
  else
    msg = 'Not checking ahead of print status on pubmed.'
    msg += ' We don\'t have the article\'s PMID.' if not result.pmid
    msg += ' The article is already in EUPMC.' if result.in_epmc
    result.provenance.push msg

  if result.issn
    doaj = API.use.doaj.journals.issn result.issn
    if doaj.status is 'success'
      result.pure_oa = true
      result.provenance.push 'Confirmed journal is listed in DOAJ'
      result.publisher ?= doaj.data.bibjson.publisher
      result.journal_title ?= doaj.data.bibjson.title
    else
      result.provenance.push 'Could not find journal in DOAJ'

    romeo = API.use.sherpa.romeo.search {issn:result.issn}
    if romeo.status is 'success'
      journal
      publisher
      try journal = romeo.data.journals[0].journal[0]
      try publisher = romeo.data.publishers[0].publisher[0]
      if not result.journal_title
        if journal?.jtitle and journal.jtitle.length > 0
          result.journal_title = journal.jtitle[0]
          result.provenance.push 'Added journal title from Sherpa Romeo'
        else
          result.provenance.push 'Tried, but could not add journal title from Sherpa Romeo.'
      if not result.publisher
        if publisher?.name and publisher.name.length > 0
          result.publisher = publisher.name[0]
          result.provenance.push 'Added publisher from Sherpa Romeo'
        else
          result.provenance.push 'Tried, but could not add publisher from Sherpa Romeo.'
      result.romeo_colour = publisher?.romeocolour[0]
      for k in ['preprint','postprint','publisher_copy']
        main = if k.indexOf('publisher_copy') isnt -1 then k + 's' else 'pdfversion'
        stub = k.replace('print','').replace('publisher_copy','pdf')
        if publisher?[main]
          if publisher[main][0][stub+'restrictions']
            for p in publisher[main][0][stub+'restrictions']
              if p[stub+'restriction']
                if result[k+'_embargo'] is false then result[k+'_embargo'] = '' else result[k+'_embargo'] += ','
                result[k+'_embargo'] += p[stub+'restriction'][0].replace(/<.*?>/g,'')
          result[k+'_self_archiving'] = publisher[k+'s'][0][stub+'archiving'][0] if publisher[main][0][stub+'archiving']
      result.provenance.push 'Added embargo and archiving data from Sherpa Romeo'
    else
      result.provenance.push 'Unable to add any data from Sherpa Romeo.'
  else
    result.provenance.push 'Not attempting to add any data from Sherpa Romeo - don\'t have a journal ISSN to use for lookup.'

  publisher_licence_check_ran = false
  if not result.licence or result.licence is 'unknown' or result.licence not in ['cc-by','cc-zero']
    publisher_licence_check_ran = true
    url = API.use.crossref.resolve(result.doi) if result.doi
    if url and (not result.pmcid or url.indexOf('europepmc') is -1) #if we had a pmcid we already looked at the europepmc page for licence
      lic = API.service.lantern.licence url
      if lic.licence and lic.licence isnt 'unknown'
        result.licence = lic.licence
        result.licence_source = 'publisher_splash_page'
        result.publisher_licence = lic.licence
        extrainfo = ''
        extrainfo += ' The bit that let us determine the licence was: ' + lic.matched + ' .' if lic.matched
        if lic.match
          extrainfo += ' If licence statements contain URLs we will try to find those in addition to ' +
          'searching for the statement\'s text. Here the entire licence statement was: ' + lic.match + ' .'
        result.provenance.push 'Added licence (' + result.publisher_licence + ') via article publisher splash page lookup to ' + lic.resolved + ' (used to be OAG).' + extrainfo
      else
        result.publisher_licence = 'unknown'
        result.provenance.push 'Unable to retrieve licence data via article publisher splash page lookup (used to be OAG).'
        result.provenance.push 'Retrieved content was very long, so was contracted to 500,000 chars from start and end to process' if lic.large
    else
      result.provenance.push 'Unable to retrieve licence data via article publisher splash page - cannot obtain a suitable URL to run the licence detection on.'
  else
    result.provenance.push 'Not attempting to retrieve licence data via article publisher splash page lookup.'
    publisher_licence_check_ran = false

  result.publisher_licence = "not applicable" if not publisher_licence_check_ran and result.publisher_licence isnt 'unknown'
  result.publisher_licence = 'unknown' if not result.publisher_licence?
  if result.epmc_licence? and result.epmc_licence isnt 'unknown' and not result.epmc_licence.startsWith('cc-')
    result.epmc_licence = 'non-standard-licence'
  if result.publisher_licence? and result.publisher_licence isnt 'unknown' and result.publisher_licence isnt "not applicable" and not result.publisher_licence.startsWith('cc-')
    result.publisher_licence = 'non-standard-licence'

  result = API.service.lantern.compliance result
  result.score = API.service.lantern.score result

  return result