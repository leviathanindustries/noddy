import fs from 'fs'

ml_scales = new API.collection {index:"ml",type:"scales"}

API.add 'ml/scales',
  get: () -> return ml_scales.search this.queryParams
  post: () -> return ml_scales.search this.bodyParams

API.add 'ml/scales/load',
  get:
    #roleRequired: 'root',
    action: () ->

      sheet = '/home/cloo/scales.csv'
      scales = API.convert.csv2json(undefined,fs.readFileSync(sheet).toString())

      count = 0
      for s in scales
        for k of s
          s[k] = 0 if typeof s[k] is 'string' and s[k].toLowerCase() is 'na'
        ml_scales.insert s

      return count