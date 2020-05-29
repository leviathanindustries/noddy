
'''API.add 'scripts/scratch',
  get:
    authRequired: 'root'
    action: () ->
      res = {checked: 0, withissn: 0, journal: 0, crossref: 0, notfound: 0, dois: 0, publishers: 0}
      
      _publishers = []
      _check = (rec) ->
        console.log res
        res.checked += 1
        issn = false
        journal = false
        for snak in rec.snaks
          if snak.key is 'ISSN'
            issn = snak.value
          if snak.key is 'instance of' and snak.qid is 'Q5633421'
            journal = true
          if issn and journal
            break
        if journal
          res.journal += 1
          if issn
            res.withissn += 1
            inc = API.use.crossref.journals.issn issn
            if not inc?
              res.notfound += 1
            else if inc.ISSN and inc.ISSN.length and inc.ISSN[0] is issn
              res.crossref += 1
              if inc.counts?['total-dois']?
                res.dois += inc.counts['total-dois']
              if inc.publisher? and inc.publisher.toLowerCase() not in _publishers
                _publishers.push inc.publisher.toLowerCase()
                res.publishers += 1
      
      wikidata_record.each 'snaks.key.exact:"ISSN"', _check

      API.mail.send
        to: 'alert@cottagelabs.com'
        subject: 'Scratch script complete'
        text: JSON.stringify res, "", 2

      return res
'''