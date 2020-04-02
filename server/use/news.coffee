
# https://newsapi.org/docs/get-started
# https://newsapi.org/docs
# note requries attribution for dev account, and may be better to write my own instead

# no use, full of garbage, stop using this and replace with one, some or all of options listed on wikipedia
# https://en.wikipedia.org/wiki/List_of_news_media_APIs

API.use ?= {}
API.use.news = {}

API.add 'use/news', get: () -> return API.use.news.search this.queryParams

# https://newsapi.org/docs/endpoints/everything
API.use.news.search = (q,sort='publishedAt',from,endpoint='everything') ->
  # sort defaults to publishedAt anyway, can also be relevancy, popularity
  if not API.settings.use?.news?.apikey?
    return false
  else
    u = 'http://newsapi.org/v2/' + endpoint + '?sortBy=' + sort + '&q=' + q
    u += '&from=' + from if from # from can be like 2020-03-21
    u += '&apiKey=' + API.settings.use.news.apikey
    API.log 'Using news API for ' + u
    res = HTTP.call 'GET', u
    # should add some caching, can only go up to 500 reqs per day on free account
    return res.data

