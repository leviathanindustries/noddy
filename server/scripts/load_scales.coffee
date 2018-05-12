import fs from 'fs'

ml_scales = new API.collection {index:"ml",type:"scales"}

API.add 'ml/scales',
  get: () -> return ml_scales.search this.queryParams
  post: () -> return ml_scales.search this.bodyParams

API.add 'ml/scales/load',
  get:
    #roleRequired: 'root',
    action: () ->

      ml_scales.remove '*'

      sheet = '/home/cloo/scales.csv'
      scales = API.convert.csv2json(undefined,fs.readFileSync(sheet).toString())

      count = 0
      for s in scales
        for k of s
          if typeof s[k] is 'string' and s[k].toLowerCase() is 'na'
            s[k] = 0
          else
            s[k] = s[k].toString()
        ml_scales.insert s
        count += 1

      return count