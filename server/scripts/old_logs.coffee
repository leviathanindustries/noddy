
'''
API.add 'scripts/old_logs',
  get:
    #authRequired: 'root'
    action: () ->
      res = count: 0, ids: [], records: {}
      q = {
        query: {
          query_string: {
            query: '"2018-04-07"'
          }
        },
        size: 200
      }
      for h in API.es.call('POST', API.settings.es.index + '_log/_search', q).hits.hits
        console.log res.count
        console.log h._id
        try
          res.count += 1
          res.ids.push h._id
          res.records[h._id] = API.es.call 'DELETE', API.settings.es.index + '_log/20180407/' + h._id

      return res'''
