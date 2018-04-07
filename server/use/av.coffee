
import moment from 'moment'

# https://www.alphavantage.co/documentation

# remember to use the full symbol when accessing stocks on multiple markets
# e.g. GSK would return glaxo on nasdaq, whereas to get it on London requires GSK.L
# where is a list of all of these suffixes...?

API.use ?= {}
API.use.av = {}

API.add 'use/av/:symbol', get: () -> return API.use.av[if this.urlParams.symbol.indexOf(',') isnt -1 then 'tickers' else 'ticker'] this.urlParams.symbol, this.queryParams.period, this.queryParams.interval, this.queryParams.size, this.queryParams.simple, this.queryParams.round


# alphavantage can also be used to access data on coin stocks, forex, and various stock indicator values
# can add API calls to those when necessary

API.use.av.ticker = (symbol, period='today', interval=1, size, simple, round) ->
  try symbol = symbol.toString().toUpperCase()
  # accept period of today (intraday), daily, weekly, monthly
  # interval can be 1, 5, 15, 30, 60 for today (intraday)
  # NOTE the AV API also accepts datatype json or csv - in case a csv output would be useful for something
  url = 'https://www.alphavantage.co/query?symbol=' + symbol + '&function=TIME_SERIES_' + if period is 'today' then 'INTRADAY' else period.toUpperCase()
  url += '&interval=' + interval + 'min' if period is 'today'
  if period in ['today','daily']
    # size can be compact (default) to return only 100 or full to return all
    # amount returned depends on interval
    if size? and size not in ['compact','full']
      try
        size = parseInt size
        url += '&outputsize=' + if size > 100 then 'full' else 'compact'
    else
      size ?= if interval in [1,"1",5,"5"] then 'compact' else 'full'
      url += '&outputsize=' + size
  url += '&apikey=' + API.settings.use.av.apikey
  API.log 'Using alphavantage for ' + url
  try
    res = HTTP.call 'GET', url
    if res.statusCode is 200
      results = JSON.parse res.content
      results = if period is 'daily' then results['Time Series (Daily)'] else if period is 'weekly' then results['Weekly Time Series'] else if period is 'monthly' then results['Monthly Time Series'] else results['Time Series (' + interval + 'min)']
      resp = []
      for r of results
        if typeof size isnt 'number' or resp.length < size
          if simple
            resp.push if round then Math.round(results[r]['1. open']) else results[r]['4. close']*10000/10000
          else
            resp.push
              datetime: r
              date: r.split(' ')[0]
              time: r.split(' ')[1].replace(':00','')
              timestamp: moment.unix(r,'YYYY-MM-DD HH:MM:SS')
              open: results[r]['1. open']*10000/10000
              high: results[r]['2. high']*10000/10000
              low: results[r]['3. low']*10000/10000
              close: results[r]['4. close']*10000/10000
              volume: results[r]['5. volume']*10000/10000
      return resp
    else
      return res
  catch err
    return { status: 'error', data: 'alphavantage API error', error: err.toString()}

API.use.av.tickers = (symbols, period='today', interval=1, size, simple, round) ->
  symbols = symbols.split(',') if typeof symbols is 'string'
  results = {}
  for symbol in symbols
    results[symbol] = API.use.av.ticker symbol, period, interval, size, simple, round
  return results