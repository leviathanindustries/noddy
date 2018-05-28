
import { Random } from 'meteor/random'

# reminder - did not use numjs here because it did not work properly, as in was not the 
# same as numpy, and also numjs installs sharp, which on ubuntu errors when loaded after canvas. 
# This is known by the devs and they don't seem to intend to fix it

# Building a profile of subjective well-being for social media users (chen)
# http://journals.plos.org/plosone/article?id=10.1371/journal.pone.0187278

# Epistemic Public Reason: A Formal Model of Strategic Communication and Deliberative Democracy
# https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2862013

# Comparative efficacy and acceptability of 21 antidepressant drugs for the acute treatment of adults with major depressive disorder: a systematic review and network meta-analysis
# https://www.thelancet.com/journals/lancet/article/PIIS0140-6736(17)32802-7/fulltext

# What’s True, and Fake, About the Facebook Effect
# http://behavioralscientist.org/whats-true-and-fake-about-the-facebook-effect/

neural_model = new API.collection index: API.settings.es.index + "_neural", type: "model"
neural_prediction = new API.collection index: API.settings.es.index + "_neural", type: "prediction"

API.neural = {}
an = API.neural # short convenience, for use in this file only

API.add 'neural/train', 
  get:
    authOptional: true
    action: () ->
      this.queryParams.classes = this.queryParams.classes.split(',') if this.queryParams.classes?
      # do other values need to be converted, say to numbers, etc?
      # how would recs and answers be passed in to this? Does it really need to be a POST with data? Probably both...
      # could recs be a url to a records set, of either csv or json?
      # if POST, could post json and/or csv? and could contain recs and answers, maybe classes too, or just recs
      # need to get an email from the signed in user, or one passed in the args, to notify of completion
      return an.train(this.queryParams)
  post:
    authOptional: true
    action: () ->
      this.queryParams.classes = this.queryParams.classes.split(',') if this.queryParams.classes?
      # do other values need to be converted, say to numbers, etc?
      # how would recs and answers be passed in to this? Does it really need to be a POST with data? Probably both...
      # could recs be a url to a records set, of either csv or json?
      # if POST, could post json and/or csv? and could contain recs and answers, maybe classes too, or just recs
      model = this.queryParams
      return an.train(model)

API.add 'neural/:model/predict',
  get: () -> 
    model = neural_model.get this.urlParams.model
    return {} if not model?
    return an.predict model, this.queryParams.record.split(',')
# add a POST so record could be posted too

API.add 'neural/prediction/:prediction',
  get: () -> return neural_prediction.get this.urlParams.prediction

API.add 'neural/prediction/:prediction/:value',
  get: () -> 
    prediction = neural_prediction.get this.urlParams.prediction
    return {} if not prediction?
    return an.prediction this.urlParams.prediction, this.urlParams.value


an._seed = 987654321
an._seedi = 1
an._mask = 0xffffffff
an.seed = (i) -> 
  an._seed = 987654321
  an._seedi = i
  return true
an.random = (min, max, int, seed) ->
  #return Math.floor(Math.random()*(max-min+1)+min) # old simpler random
  #x = Math.sin(seed++) * 10000 # another simpler solution
  #return x - Math.floor x
  API.neural.seed(seed) if seed?
  an._seed = (36969 * (an._seed & 65535) + (an._seed >> 16)) & an._mask
  an._seedi = (18000 * (an._seedi & 65535) + (an._seedi >> 16)) & an._mask
  result = ((an._seed << 16) + an._seedi) & an._mask
  result /= 4294967296
  #result += 0.5 # random between 0 inclusive and 1.0 exclusive
  if min? and max?
    result = parseInt(min) + ((parseInt(max) - parseInt(min)) * result)
  return if int? then Math.round(result) else result

an.range = (start, stop, step=1) ->
  if not stop?
    stop = start
    start = 0
  return [] if (step > 0 and start >= stop) or (step < 0 and start <= stop)
  result = []
  i = start
  if step > 0
    while i < stop
      result.push i
      i += step
  else
    while i > stop
      result.push i
      i += step
  return result

an.hash = (v) ->
  hash = 0
  if typeof v is 'number'
    hash = v
  else
    v = JSON.stringify(v) if typeof v isnt 'string'
    c = 0
    while c < v.length
      hash = (((hash << 5) - hash) + v.charCodeAt(c)) & 0xFFFFFFFF
      c++
  return hash

# https://towardsdatascience.com/activation-functions-and-its-types-which-is-better-a9a5310cc8f
an.relu = (arr, W, b, leaky) ->
  _relu = (v) -> return if v > 0 then v else if not leaky then 0 else v/100
  if typeof arr is 'number'
    return _relu arr
  else
    res = []
    for i of arr
      res.push []
      if W?
        for j of W[0]
          res[i][j] = if b? then b[j] else 0
          res[i][j] += arr[i][k] * W[k][j] for k of arr[0]
          res[i][j] = _relu res[i][j]
      else
        res[i][j] = _relu(arr[i][j]) for j of arr[i]
    return res
an.lrelu = (arr, W, b) -> return an.relu(arr, W, b, true)

an.softmax = (arr, W, b) ->
  res = []
  for i of arr
    res.push []
    if W?
      for j of W[0]
        res[i][j] = if b? then b[j] else 0
        res[i][j] += arr[i][k] * W[k][j] for k of arr[0]
        res[i][j] = Math.exp res[i][j]
    else
      res[i][j] = Math.exp(arr[i][j]) for j of arr[i]
    _sum = res[i].reduce((a, v) -> return a + v)
    res[i][j] /= _sum for j of res[i]
  return res

an.forward = (model, recs) ->
  # First linear step Z1 is the input layer x times the dot product of the weights + bias, then run through the activation function
  cache = []
  for l of model.layers
    cache.push an[model.layers[l]]((if l is "0" then recs else cache[parseInt(l)-1]), model[if l is "0" then 'W' else 'W2'], model[if l is "0" then 'b' else 'b2'])
  return cache

an.predict = (model, rec) ->
  model = neural_model.get(model) if typeof model is 'string'
  cache = an.forward model, [rec]
  res = cache[cache.length-1][0].indexOf Math.max.apply this, cache[cache.length-1][0]
  # TODO should actually save the prediciton, and which model was used for it, and return a prediction object
  # then later can use the prediction as extra training data, once informed if it is correct or not
  return if model.classes then model.classes[res] else res

an.accuracy = (model, recs, answers) ->
  cache = an.forward model, recs
  correct = 0
  for i of answers
    correct += answers[i][cache[cache.length-1][i].indexOf(Math.max.apply this, cache[cache.length-1][i])]
  return correct / recs.length

# https://stats.stackexchange.com/questions/181/how-to-choose-the-number-of-hidden-layers-and-nodes-in-a-feedforward-neural-netw
# http://cs231n.github.io/neural-networks-case-study/#net
# https://medium.freecodecamp.org/building-a-3-layer-neural-network-from-scratch-99239c4af5d3
an.train = (model={}, recs, classes, answers, save, epochs=10000, accuracy=98, layers=['relu','softmax'], rate=1, reg=0.001, scale=0.01, losses=100) ->
  # TODO the trainer should run as a job if the job runner is running, so that it does not block. Should also email someone once done.
  # Should also have some name to save the trained object as - and maybe a cache? If inputs are same and name is same, why bother running again...
  
  # NOTE it is harder for leaky relu to hit such high accuracy. Where relu may get 98% in X epochs, lrelu may only get 97%
  # on the default stanford test dataset, relu hits 98% after a couple of thousand epochs, whereas lrelu takes 3500 to reach 97% and does not reach 98% within 10k epochs
  # so default to relu, and only turn on lrelu if necessary - but note the general problem with relu, on some datasets too many nodes will tend to 0 and the network will not operate
  
  # this still needs work to be able to run with anything other than one hidden layer and one softmax final layer
  # recs here is a list of rec data lists/objects
  # answers is a list of answer data lists too, e.g. [[1,0,0],[0,1,0]]
  #recs = an.test._examples.recs # list of records to train on D is length of rec keys / list
  #answers = an.test._examples.answers # the answers that the records must match to
  recs = an.test._examples.wine
  classes = ['Cultivar 1','Cultivar 2','Cultivar 3']
  
  # if recs is a csv, should that be acceptable and converted to json? If so, how to know if it has headers row or not?
  build = false
  if not answers?
    answers = []
    build = true
  if not _.isArray recs[0] # if given objects, change to a list of lists
    for r of recs
      if classes?
        answers.push([]) if build
        for c in classes
          answers[r].push(parseInt(recs[r][c])) if build # NOTE incoming data will need to be checked to be numbers, or hashed into a number...
          delete recs[r][c]
      recs[r] = _.values(recs[r])
      recs[r][v] = parseFloat(recs[r][v]) for v of recs[r]

  model.classes ?= classes # a list of class names, which are the names of the answer rows, if answers is a list of lists of 1/0 values, where 1 indicates the correct class for the row
  model.inputs = {rows: recs.length, cols: if _.isArray(recs[0]) then recs[0].length else _.keys(recs[0]).length}
  model.outputs = 3 # how many nodes in last result layer - depends on how many things trying to classify into, could be just one if looking for a specific result somehow
  model.hiddens = if model.inputs.cols < model.outputs + 2 then Math.floor(recs.length/3) else model.inputs.cols - Math.ceil(model.inputs.cols/(if model.outputs is 1 then 2 else model.outputs))
  model.layers = layers
  model.rate ?= rate # learning rate
  model.reg ?= reg # regularisation rate
  model.scale ?= scale # a scale factor on the initial random weights
  model.epochs ?= epochs
  model.accuracy ?= accuracy # if a number and not 0, when accuracy goes above this on an epoch loss check, epochs will stop regardless how many have run
  model.losses = []
  model._id ?= if save is true then Random.id() else if neural_model.get(save)? then save + '_' + Random.id() else save

  model.W = []
  model.W2 = []
  model.b = []
  model.b2 = []
  for i in an.range model.inputs.cols
    model.W.push []
    for j in an.range model.hiddens
      model.W[i][j] = an.random() * model.scale
      model.b.push(0) if i is 0
  for i in an.range model.hiddens
    model.W2.push []
    for j in an.range model.outputs
      model.W2[i][j] = an.random() * model.scale
      model.b2.push(0) if i is 0

  for iteration in an.range model.epochs
    cache = an.forward(model,recs)
    hidden_layer = cache[0]
    probs = cache[1]
    
    # compute the gradient on scores
    cp = 0
    ws = 0
    accuracy = 0
    dscores = []
    dhidden = []
    W2T = _.zip.apply _, model.W2 # transpose W2 before updating it, calculate dhidden as dot product of dscores and transposition of W2
    for i of probs
      accuracy += answers[i][probs[i].indexOf(Math.max.apply this, probs[i])] if iteration % losses is 0
      dscores.push []
      for j of probs[i]
        dscores[i][j] = (probs[i][j] - answers[i][j])/recs.length
        model.b2[j] -= dscores[i][j] * model.rate # update second layer biases - this could be done separately for readability, but keep here to minimise loops
        if iteration % losses is 0 # only bother doing this on a loss-check epoch (otherwise save a bit of processing)
          cp -= if answers[i][j] is 1 then Math.log(probs[i][j]) else 0
      # backpropate the gradient to the parameters (W,b)
      # this can be separated out into another loop over dscores for better readability, but want to minimise loops as much as possible
      dhidden.push []
      for j of W2T[0]
        dhidden[i][j] = 0
        dhidden[i][j] += dscores[i][k] * W2T[k][j] for k of dscores[0]
        dhidden[i][j] = if hidden_layer[i][j] <= 0 then 0 else dhidden[i][j] # go backwards through relu
        model.b[j] -= dhidden[i][j] * model.rate # update first layer bias

    # update weights - worth pulling this into the above mixed loops?
    for i of hT = _.zip.apply _, hidden_layer
      for j of dscores[0]
        ws += model.W2[i][j] * model.W2[i][j] if iteration % losses is 0 # do before weight is adjusted for next round
        _ans = 0
        _ans += hT[i][k] * dscores[k][j] for k of hT[0]
        model.W2[i][j] += (_ans + model.W2[i][j] * model.reg) * -model.rate
    for i of xT = _.zip.apply _, recs
      for j of dhidden[0]
        ws += model.W[i][j] * model.W[i][j] if iteration % losses is 0
        _ans = 0
        _ans += xT[i][k] * dhidden[k][j] for k of xT[0]
        model.W[i][j] += (_ans + model.W[i][j] * model.reg) * -model.rate

    if iteration % losses is 0
      # compute the loss: average cross-entropy loss and regularization
      loss = cp/recs.length + 0.5*model.reg*ws
      accuracy = accuracy / recs.length * 100
      model.losses.push {iteration:iteration, loss: loss, accuracy: accuracy}
      # TODO could add a learning rate adjustment here, if accuracy is not getting high enough, half the learning rate
      console.log 'iteration ' + iteration + ': loss ' + loss + ', accuracy ' + accuracy + '%'
      if model.accuracy and accuracy >= model.accuracy
        console.log 'Stopping iterations, reached required accuracy of ' + model.accuracy
        break

  # model.prediction = an.predict model, an.test._examples.predict.rec # this works, for the wine test dataset, finds the right answer after training
  neural_model.insert(model) if model._id?
  return model
  


# reduce size of needle image so that narrowest defined part is q pixel wide
# do the same with the haystack image. Then should be able to find same-sized image in haystack

# and remember the problem - will this be any better for finding if one image contains another?
# maybe not, but may be useful for other things anyway

# https://github.com/roytseng-tw/Detectron.pytorch
# https://cs.stackexchange.com/questions/14717/object-recognition-given-an-image-does-it-contain-a-particular-3d-object-of-i
# https://www.pyimagesearch.com/2017/11/27/image-hashing-opencv-python/

# and for what I am probably doing (finding logos in pdfs) need to extract pdf to image first
# and probably best to throw out all text first if possible, or extract all images, rather than turning the whole doc into an image
# and if it would be possible to know how many pages to bother checking, that could reduce the search space
# e.g if no logo in the first few pages, it probably won't turn up on page 100

# pdf.js (which is used a bit in the old api code too) may be useful
# https://www.npmjs.com/package/pdfjs-dist
# http://mozilla.github.io/pdf.js/examples/index.html#interactive-examples


an.test = {} # this can become the usual test function eventually
an.test._examples = {
  recs: [
    [0.00000000e+00,0.00000000e+00], [-4.23708671e-03,9.16937845e-03], [4.86593277e-03,1.96072517e-02],
    [5.27460182e-03,2.98404461e-02], [-1.23668002e-02,3.84649026e-02], [2.13217197e-02,4.57836695e-02],
    [1.93537084e-02,5.74328177e-02], [-1.91772153e-02,6.80567723e-02], [1.21100808e-02,7.98955059e-02],
    [1.76281756e-02,8.91835760e-02], [4.95784574e-02,8.80057786e-02], [5.52812805e-02,9.63828773e-02],
    [4.61544595e-02,1.12080972e-01], [4.82141941e-02,1.22141434e-01], [1.27645000e-02,1.40836881e-01],
    [1.26174047e-01,8.38865367e-02], [7.75981862e-02,1.41768492e-01], [1.16479985e-01,1.26171312e-01],
    [1.55781239e-01,9.37553021e-02], [1.12162455e-01,1.55732334e-01], [1.79745934e-01,9.22147551e-02],
    [1.83857229e-01,1.05791908e-01], [1.58543668e-01,1.55713266e-01], [2.02182743e-01,1.14438729e-01],
    [1.58562711e-01,1.83377698e-01], [2.15376004e-01,1.31841495e-01], [2.25771074e-01,1.34163990e-01],
    [2.56513306e-01,9.26341673e-02], [2.73845426e-01,7.07143584e-02], [2.80434567e-01,8.46405583e-02],
    [2.88841117e-01,9.16415487e-02], [1.80350240e-01,2.55978535e-01], [3.22470754e-01,2.21753864e-02],
    [2.94779874e-01,1.55614707e-01], [3.31458714e-01,8.99014431e-02], [3.42265107e-01,8.85541789e-02],
    [3.43811815e-01,1.18426521e-01], [3.73734787e-01,-1.39045023e-03], [3.82851096e-01,2.75125954e-02],
    [3.91154272e-01,-4.67608960e-02], [3.85046921e-01,1.22423512e-01], [3.99012334e-01,-1.10915591e-01],
    [4.15367649e-01,-8.63212085e-02], [3.70117267e-01,-2.27304702e-01], [4.27501943e-01,-1.21544037e-01],
    [3.96228137e-01,-2.22743875e-01], [4.52711091e-01,-1.04637494e-01], [3.84479970e-01,-2.78496531e-01],
    [3.93744775e-01,-2.82918903e-01], [4.19058584e-01,-2.63372182e-01], [4.14729436e-01,-2.88228221e-01],
    [4.59569700e-01,-2.32759047e-01], [4.37765591e-01,-2.90261094e-01], [4.17628819e-01,-3.34947127e-01],
    [5.31892721e-01,-1.20875121e-01], [3.77536708e-01,-4.07563503e-01], [4.70370114e-01,-3.14196285e-01],
    [4.89950121e-01,-3.02399843e-01], [4.75834954e-01,-3.41776797e-01], [4.55664196e-01,-3.84106730e-01],
    [3.70246457e-01,-4.79819778e-01], [4.22899406e-01,-4.48119660e-01], [4.54156936e-01,-4.31214975e-01],
    [2.29134195e-01,-5.93680216e-01], [4.47543767e-01,-4.66498785e-01], [3.74825653e-01,-5.39058616e-01],
    [2.94883210e-01,-5.97903284e-01], [7.83182321e-02,-6.72220755e-01], [-1.78626076e-02,-6.86636381e-01],
    [3.09995616e-01,-6.24235113e-01], [2.73978454e-01,-6.51831874e-01], [2.76904047e-01,-6.61558327e-01],
    [9.49923115e-02,-7.21042357e-01], [1.91115845e-01,-7.12176075e-01], [8.20741475e-02,-7.42955135e-01],
    [2.30419926e-01,-7.21683924e-01], [1.60757942e-01,-7.50656049e-01], [-4.65068899e-02,-7.76386103e-01],
    [-1.21555209e-02,-7.87785014e-01], [-1.63958107e-01,-7.80954222e-01], [-2.00092982e-01,-7.82915954e-01],
    [1.10454247e-01,-8.10691894e-01], [6.42003100e-02,-8.25790993e-01], [-4.32846843e-01,-7.18004924e-01],
    [-8.22039124e-02,-8.44493372e-01], [-2.94434760e-01,-8.06522069e-01], [-3.73026579e-01,-7.84517716e-01],
    [-4.20195344e-01,-7.71818637e-01], [-3.51091570e-01,-8.16613841e-01], [-6.16268940e-02,-8.96875111e-01],
    [-4.65836964e-01,-7.80667793e-01], [-8.79615363e-01,-2.66815661e-01], [-5.53187955e-01,-7.46705052e-01],
    [-6.19746959e-01,-7.05956571e-01], [-3.53045706e-01,-8.81418963e-01], [-6.47982150e-01,-7.07773649e-01],
    [-7.59905888e-01,-6.02374680e-01], [-7.28106216e-01,-6.55641228e-01], [-6.34274249e-01,-7.59997492e-01],
    [-6.55306324e-01,-7.55363239e-01], [-0.00000000e+00,-0.00000000e+00], [-8.23942366e-03,-5.84314152e-03],
    [-1.81149153e-02,-8.94267646e-03], [-2.97612736e-02,-5.70440510e-03], [-3.22796768e-02,-2.43003899e-02],
    [-4.76614481e-02,-1.67076777e-02], [-4.54019836e-02,-4.01466619e-02], [-6.13682745e-02,-3.51201471e-02],
    [-7.61988825e-02,-2.69012310e-02], [-8.80986494e-02,-2.24296855e-02], [-9.53604540e-02,-3.33080219e-02],
    [-1.11102125e-01,1.41305482e-03], [-1.21209317e-01,-8.24460486e-04], [-1.30659862e-01,-1.30820028e-02],
    [-1.41124439e-01,9.04721026e-03], [-1.50667515e-01,1.60044030e-02], [-1.60417667e-01,1.96457564e-02],
    [-1.68665766e-01,3.22280369e-02], [-1.81355332e-01,1.29651376e-02], [-1.90404577e-01,2.40639443e-02],
    [-2.01527830e-01,1.40959473e-02], [-2.07293142e-01,4.49995746e-02], [-2.19292379e-01,-3.59662123e-02],
    [-2.29672488e-01,3.49947520e-02], [-2.40253931e-01,3.23660597e-02], [-2.20845419e-01,1.22459398e-01],
    [-2.11316342e-01,1.55942160e-01], [-2.54723441e-01,-9.74481093e-02], [-2.51611011e-01,1.29165540e-01],
    [-2.67289055e-01,1.19850455e-01], [-2.92315170e-01,7.98699309e-02], [-3.10372698e-01,4.14729757e-02],
    [-2.59479848e-01,1.92741650e-01], [-2.03423782e-01,2.64064151e-01], [-2.29071576e-01,2.55877629e-01],
    [-2.23422926e-01,2.73988033e-01], [-2.59563037e-01,2.54673192e-01], [-2.28759704e-01,2.95548003e-01],
    [-3.45760001e-01,1.66679113e-01], [-2.10391740e-01,3.33051890e-01], [-3.21531313e-01,2.44675832e-01],
    [-2.51951024e-01,3.28684944e-01], [-2.70213356e-01,3.27057146e-01], [-2.65039473e-01,3.44105066e-01],
    [-2.65754811e-01,3.56237624e-01], [-7.94053011e-02,4.47555995e-01], [-1.87366424e-01,4.25194262e-01],
    [-1.31426607e-01,4.56193174e-01], [-2.27992447e-01,4.27898934e-01], [-4.44335775e-02,4.92950971e-01],
    [2.10479672e-01,4.59101645e-01], [-1.66112947e-01,4.87634671e-01], [-1.42876201e-01,5.05446937e-01],
    [-2.42694872e-01,4.77181943e-01], [-1.18537588e-01,5.32418540e-01], [4.49012887e-02,5.53738069e-01],
    [-5.08105400e-02,5.63369896e-01], [-7.76437631e-04,5.75757052e-01], [-1.65073330e-01,5.62121943e-01],
    [3.32470484e-02,5.95031490e-01], [3.98655256e-02,6.04748045e-01], [9.87638397e-02,6.08194740e-01],
    [1.17040458e-01,6.15228745e-01], [1.72233290e-01,6.12612742e-01], [2.05802690e-01,6.12830965e-01],
    [2.55813549e-01,6.04679989e-01], [1.83543899e-01,6.40902552e-01], [3.83087985e-01,5.57905085e-01],
    [2.38207448e-01,6.44240487e-01], [3.66852742e-01,5.92609335e-01], [3.69446327e-01,6.02875108e-01],
    [4.51136563e-01,5.57504326e-01], [2.43613390e-01,6.85257715e-01], [4.60034514e-01,5.76271008e-01],
    [4.24187730e-01,6.15453709e-01], [4.32437980e-01,6.22027670e-01], [5.84808874e-01,4.97319013e-01],
    [6.50639740e-01,4.26152789e-01], [5.66474701e-01,5.47594190e-01], [6.68012761e-01,4.36498235e-01],
    [6.74484325e-01,4.45045489e-01], [6.05691351e-01,5.50054065e-01], [6.60323063e-01,5.00025895e-01],
    [7.20097077e-01,4.29357263e-01], [7.08210472e-01,4.67294837e-01], [7.16070256e-01,4.73722561e-01],
    [8.03177320e-01,3.30942697e-01], [8.16955142e-01,3.23809253e-01], [8.87268950e-01,5.36401593e-02],
    [8.03286710e-01,4.03625198e-01], [8.67502187e-01,2.71820228e-01], [9.11073926e-01,1.21893746e-01],
    [9.28674721e-01,-3.38911760e-02], [9.26017267e-01,1.57965168e-01], [9.45105863e-01,9.11897340e-02],
    [9.56767002e-01,-7.36295377e-02], [9.65840708e-01,-8.63940949e-02], [9.45129469e-01,-2.58329959e-01],
    [9.39724374e-01,-3.11156087e-01], [9.96752513e-01,-8.05259476e-02], [0.00000000e+00,-0.00000000e+00],
    [1.00956925e-02,-3.27717548e-04], [2.00842766e-02,-2.17794711e-03], [2.90662217e-02,-8.56903737e-03],
    [3.90931876e-02,-1.02082889e-02], [3.96382194e-02,-3.12981100e-02], [5.72075622e-02,-2.00097329e-02],
    [6.87989468e-02,-1.63154764e-02], [7.04441520e-02,-3.95925167e-02], [8.41506969e-02,-3.43965555e-02],
    [8.30610963e-02,-5.74795162e-02], [8.45387038e-02,-7.21033049e-02], [9.30286167e-02,-7.77049214e-02],
    [8.72209605e-02,-9.81613086e-02], [1.25539610e-01,-6.50981230e-02], [9.60047671e-02,-1.17217430e-01],
    [9.50075359e-02,-1.30741546e-01], [1.20616695e-01,-1.22222747e-01], [9.17506973e-02,-1.56970254e-01],
    [1.33795989e-01,-1.37592185e-01], [1.37636635e-01,-1.47879406e-01], [7.38717261e-02,-1.98842593e-01],
    [5.04816645e-02,-2.16412379e-01], [4.34408672e-03,-2.32282615e-01], [8.93145855e-02,-2.25371733e-01],
    [1.44337272e-01,-2.07209447e-01], [1.07391043e-01,-2.39665846e-01], [1.46581980e-01,-2.29986714e-01],
    [9.08349764e-02,-2.67844814e-01], [2.84722888e-02,-2.91542277e-01], [8.00521687e-02,-2.92265316e-01],
    [-1.66537846e-02,-3.12688137e-01], [9.74908601e-02,-3.08179602e-01], [1.09753441e-01,-3.14746395e-01],
    [-2.95339704e-02,-3.42162086e-01], [-3.99780620e-02,-3.51267705e-01], [1.24573106e-01,-3.41632765e-01],
    [6.51151013e-02,-3.68021260e-01], [-5.13537795e-02,-3.80387558e-01], [-7.70657008e-02,-3.86327742e-01],
    [2.80752589e-02,-4.03063801e-01], [-9.39582115e-02,-4.03342244e-01], [-9.42187038e-02,-4.13647761e-01],
    [-1.70656330e-01,-3.99412864e-01], [5.10506982e-02,-4.41502764e-01], [-8.38342042e-02,-4.46747576e-01],
    [-1.87257850e-01,-4.25242090e-01], [-1.53136083e-01,-4.49371233e-01], [-2.05856083e-01,-4.38977592e-01],
    [-2.30426149e-01,-4.38039716e-01], [-2.11519254e-01,-4.58623613e-01], [-4.23184521e-01,-2.93761714e-01],
    [-3.57899297e-01,-3.84445456e-01], [-2.73597832e-01,-4.60160444e-01], [-4.05152417e-01,-3.65201561e-01],
    [-4.56646832e-01,-3.16410566e-01], [-4.14288022e-01,-3.85139956e-01], [-5.52114759e-01,-1.63297516e-01],
    [-4.70779119e-01,-3.48708050e-01], [-4.78311427e-01,-3.55508114e-01], [-5.19119724e-01,-3.12768558e-01],
    [-4.02869314e-01,-4.66209666e-01], [-5.35926950e-01,-3.24017254e-01], [-6.30973900e-01,-8.26475377e-02],
    [-6.11024534e-01,-2.11105562e-01], [-5.75630795e-01,-3.15796849e-01], [-6.47512822e-01,-1.58655568e-01],
    [-6.62719618e-01,-1.37175784e-01], [-6.84098875e-01,-6.16224118e-02], [-6.92422306e-01,-7.94865302e-02],
    [-7.02235702e-01,-8.25469758e-02], [-7.16687032e-01,-2.63622898e-02], [-7.08031648e-01,-1.66183047e-01],
    [-7.37313923e-01,-9.39188860e-03], [-7.43541641e-01,7.65788887e-02], [-7.50766763e-01,-1.01342467e-01],
    [-6.86972823e-01,-3.42630938e-01], [-7.63379461e-01,1.48963320e-01], [-7.62835739e-01,1.97065015e-01],
    [-7.96392420e-01,5.03077672e-02], [-8.07058941e-01,4.06258317e-02], [-7.56691805e-01,3.11189653e-01],
    [-7.97057776e-01,2.25280591e-01], [-7.81415386e-01,3.03772046e-01], [-8.36369156e-01,-1.42874675e-01],
    [-8.49120508e-01,1.27137877e-01], [-7.04233740e-01,5.08597793e-01], [-8.61311815e-01,1.74384898e-01],
    [-7.49268003e-01,4.78247756e-01], [-8.26794088e-01,3.52979284e-01], [-7.43538781e-01,5.23064396e-01],
    [-6.92416572e-01,6.04543692e-01], [-7.14528099e-01,5.94167438e-01], [-7.55134995e-01,5.58777338e-01],
    [-7.48550178e-01,5.84134650e-01], [-6.18485050e-01,7.33689749e-01], [-4.22400513e-01,8.72863116e-01],
    [-3.47921122e-01,9.15944853e-01], [-5.85088773e-01,7.98480518e-01], [-4.59191376e-01,8.88337368e-01]
  ],
  answers: [
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], 
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], 
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], 
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], 
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], 
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], 
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0],
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], 
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], 
    [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0], [1,0,0],
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], 
    [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0], [0,1,0],
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], 
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1],
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], 
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], 
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], 
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], 
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], 
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], 
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], 
    [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1], [0,0,1]
  ],
  wine: [
    {"OD280/OD315 of diluted wines": "1.847919567", "Hue": "0.362177276", "Nonflavanoid phenols": "-0.659563114", "Malic acid": "-0.562249798", "Total phenols": "0.808997395", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.034818958", "Color intensity": "0.25171685", "Proanthocyanins": "1.224883984", "Magnesium": "1.913905218", "Cultivar 1": "1", "Ash": "0.232052541", "Proline": "1.013008927", "Alcalinity of ash": "-1.169593175", "Alcohol": "1.518612541"}, 
    {"OD280/OD315 of diluted wines": "1.113449303", "Hue": "0.406050663", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.499413378", "Total phenols": "0.568647662", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.733628941", "Color intensity": "-0.293321329", "Proanthocyanins": "-0.544720987", "Magnesium": "0.018145021", "Cultivar 1": "1", "Ash": "-0.827996323", "Proline": "0.965241521", "Alcalinity of ash": "-2.490847141", "Alcohol": "0.246289627"}, 
    {"OD280/OD315 of diluted wines": "0.788587455", "Hue": "0.318303889", "Nonflavanoid phenols": "-0.498406993", "Malic acid": "0.021231246", "Total phenols": "0.808997395", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.215532968", "Color intensity": "0.269019649", "Proanthocyanins": "2.135967732", "Magnesium": "0.088358361", "Cultivar 1": "1", "Ash": "1.10933436", "Proline": "1.395148175", "Alcalinity of ash": "-0.268738198", "Alcohol": "0.196879028"}, 
    {"OD280/OD315 of diluted wines": "1.184071443", "Hue": "-0.427543693", "Nonflavanoid phenols": "-0.981875357", "Malic acid": "-0.346810643", "Total phenols": "2.49144552", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.466524649", "Color intensity": "1.186068013", "Proanthocyanins": "1.03215473", "Magnesium": "0.930918449", "Cultivar 1": "1", "Ash": "0.487926405", "Proline": "2.334573828", "Alcalinity of ash": "-0.809251184", "Alcohol": "1.691549636"}, 
    {"OD280/OD315 of diluted wines": "0.449601179", "Hue": "0.362177276", "Nonflavanoid phenols": "0.226795553", "Malic acid": "0.22769377", "Total phenols": "0.808997395", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.663351271", "Color intensity": "-0.319275528", "Proanthocyanins": "0.401404443", "Magnesium": "1.281985152", "Cultivar 1": "1", "Ash": "1.840402542", "Proline": "-0.037874007", "Alcalinity of ash": "0.451945783", "Alcohol": "0.295700226"}, 
    {"OD280/OD315 of diluted wines": "0.336605754", "Hue": "0.406050663", "Nonflavanoid phenols": "-0.17609475", "Malic acid": "-0.517366641", "Total phenols": "1.562093222", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.366127977", "Color intensity": "0.731869531", "Proanthocyanins": "0.664217062", "Magnesium": "0.860705108", "Cultivar 1": "1", "Ash": "0.305159359", "Proline": "2.239039016", "Alcalinity of ash": "-1.289707172", "Alcohol": "1.481554592"}, 
    {"OD280/OD315 of diluted wines": "1.367689009", "Hue": "0.274430501", "Nonflavanoid phenols": "-0.498406993", "Malic acid": "-0.418623695", "Total phenols": "0.32829793", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.492676928", "Color intensity": "0.083014556", "Proanthocyanins": "0.681737904", "Magnesium": "-0.262708342", "Cultivar 1": "1", "Ash": "0.305159359", "Proline": "1.729520018", "Alcalinity of ash": "-1.469878167", "Alcohol": "1.716254935"}, 
    {"OD280/OD315 of diluted wines": "1.367689009", "Hue": "0.44992405", "Nonflavanoid phenols": "-0.417828932", "Malic acid": "-0.167278014", "Total phenols": "0.488531085", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.482637261", "Color intensity": "-0.00349944", "Proanthocyanins": "-0.597283511", "Magnesium": "1.492625174", "Cultivar 1": "1", "Ash": "0.890013905", "Proline": "1.745442487", "Alcalinity of ash": "-0.56902319", "Alcohol": "1.308617497"}, 
    {"OD280/OD315 of diluted wines": "0.336605754", "Hue": "0.537670824", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.625086219", "Total phenols": "0.808997395", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.95450162", "Color intensity": "0.061386057", "Proanthocyanins": "0.681737904", "Magnesium": "-0.192495001", "Cultivar 1": "1", "Ash": "-0.718336096", "Proline": "0.949319052", "Alcalinity of ash": "-1.650049163", "Alcohol": "2.25977152"}, 
    {"OD280/OD315 of diluted wines": "1.325315725", "Hue": "0.230557114", "Nonflavanoid phenols": "-1.143031478", "Malic acid": "-0.885408531", "Total phenols": "1.097417073", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.125175963", "Color intensity": "0.935177423", "Proanthocyanins": "0.453966967", "Magnesium": "-0.122281661", "Cultivar 1": "1", "Ash": "-0.352802005", "Proline": "0.949319052", "Alcalinity of ash": "-1.049479178", "Alcohol": "1.061564504"}, 
    {"OD280/OD315 of diluted wines": "0.788587455", "Hue": "1.283518406", "Nonflavanoid phenols": "-1.143031478", "Malic acid": "-0.158301383", "Total phenols": "1.049347127", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.295850306", "Color intensity": "0.299299548", "Proanthocyanins": "1.382571556", "Magnesium": "0.369211724", "Cultivar 1": "1", "Ash": "-0.243141777", "Proline": "2.43010864", "Alcalinity of ash": "-0.448909194", "Alcohol": "1.358028096"}, 
    {"OD280/OD315 of diluted wines": "0.29423247", "Hue": "0.932531309", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.768712322", "Total phenols": "-0.152401534", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.402319923", "Color intensity": "-0.025127939", "Proanthocyanins": "-0.03661659", "Magnesium": "-0.332921683", "Cultivar 1": "1", "Ash": "-0.170034959", "Proline": "1.697675081", "Alcalinity of ash": "-0.809251184", "Alcohol": "1.382733395"}, 
    {"OD280/OD315 of diluted wines": "0.407227895", "Hue": "0.844784535", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.544296535", "Total phenols": "0.488531085", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.733628941", "Color intensity": "0.234414051", "Proanthocyanins": "0.383883602", "Magnesium": "-0.754201726", "Cultivar 1": "1", "Ash": "0.158945723", "Proline": "1.82505483", "Alcalinity of ash": "-1.049479178", "Alcohol": "0.925685358"}, 
    {"OD280/OD315 of diluted wines": "0.167112616", "Hue": "1.283518406", "Nonflavanoid phenols": "0.549107795", "Malic acid": "-0.544296535", "Total phenols": "1.289696859", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.667317993", "Color intensity": "0.147900054", "Proanthocyanins": "2.135967732", "Magnesium": "-0.613775045", "Cultivar 1": "1", "Ash": "0.085838905", "Proline": "1.283690895", "Alcalinity of ash": "-2.430790143", "Alcohol": "2.160950323"}, 
    {"OD280/OD315 of diluted wines": "0.548472176", "Hue": "1.06415147", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.418623695", "Total phenols": "1.610163169", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.617119657", "Color intensity": "1.056297018", "Proanthocyanins": "2.398780351", "Magnesium": "0.158571702", "Cultivar 1": "1", "Ash": "0.049285495", "Proline": "2.547934909", "Alcalinity of ash": "-2.250619147", "Alcohol": "1.703902286"}, 
    {"OD280/OD315 of diluted wines": "0.378979039", "Hue": "1.415138568", "Nonflavanoid phenols": "-0.498406993", "Malic acid": "-0.472483484", "Total phenols": "0.889113972", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.88422395", "Color intensity": "0.969783022", "Proanthocyanins": "-0.229345844", "Magnesium": "0.860705108", "Cultivar 1": "1", "Ash": "1.218994587", "Proline": "1.793209893", "Alcalinity of ash": "-0.689137187", "Alcohol": "0.777453562"}, 
    {"OD280/OD315 of diluted wines": "0.054117191", "Hue": "0.493797437", "Nonflavanoid phenols": "-0.256672811", "Malic acid": "-0.373740538", "Total phenols": "0.808997395", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.115136296", "Color intensity": "0.49395604", "Proanthocyanins": "0.664217062", "Magnesium": "1.422411833", "Cultivar 1": "1", "Ash": "1.292101405", "Proline": "1.697675081", "Alcalinity of ash": "0.151660791", "Alcohol": "1.605081089"}, 
    {"OD280/OD315 of diluted wines": "-0.058878234", "Hue": "0.75703776", "Nonflavanoid phenols": "0.307373613", "Malic acid": "-0.687922639", "Total phenols": "1.049347127", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.376167644", "Color intensity": "0.666984033", "Proanthocyanins": "0.22619603", "Magnesium": "1.07134513", "Cultivar 1": "1", "Ash": "0.926567314", "Proline": "1.22000102", "Alcalinity of ash": "0.151660791", "Alcohol": "1.024506555"}, 
    {"OD280/OD315 of diluted wines": "0.29423247", "Hue": "1.195771632", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "-0.669969376", "Total phenols": "1.610163169", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.908270007", "Color intensity": "1.575380998", "Proanthocyanins": "0.471487808", "Magnesium": "0.579851746", "Cultivar 1": "1", "Ash": "0.414819587", "Proline": "2.971472576", "Alcalinity of ash": "-0.899336682", "Alcohol": "1.469201942"}, 
    {"OD280/OD315 of diluted wines": "1.05695159", "Hue": "0.011190179", "Nonflavanoid phenols": "-1.545921781", "Malic acid": "0.685501974", "Total phenols": "0.64876424", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.004699956", "Color intensity": "0.018129059", "Proanthocyanins": "0.121070982", "Magnesium": "1.141558471", "Cultivar 1": "1", "Ash": "0.707246859", "Proline": "0.312420304", "Alcalinity of ash": "-1.289707172", "Alcohol": "0.789806212"}, 
    {"OD280/OD315 of diluted wines": "1.551306575", "Hue": "0.581544212", "Nonflavanoid phenols": "-0.981875357", "Malic acid": "-0.63406285", "Total phenols": "1.129463704", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.145255298", "Color intensity": "0.25604255", "Proanthocyanins": "0.891987999", "Magnesium": "1.843691877", "Cultivar 1": "1", "Ash": "-0.316248596", "Proline": "0.105428211", "Alcalinity of ash": "-1.049479178", "Alcohol": "1.308617497"}, 
    {"OD280/OD315 of diluted wines": "1.28294244", "Hue": "0.318303889", "Nonflavanoid phenols": "-0.901297296", "Malic acid": "1.313866176", "Total phenols": "0.184088091", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.382240589", "Color intensity": "-0.241412931", "Proanthocyanins": "0.681737904", "Magnesium": "0.158571702", "Cultivar 1": "1", "Ash": "1.036227541", "Proline": "0.073583274", "Alcalinity of ash": "-0.268738198", "Alcohol": "-0.087231914"}, 
    {"OD280/OD315 of diluted wines": "1.960914992", "Hue": "0.669290986", "Nonflavanoid phenols": "-0.740141175", "Malic acid": "-0.427600326", "Total phenols": "0.5045544", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.854104948", "Color intensity": "-0.544211919", "Proanthocyanins": "0.173633506", "Magnesium": "0.088358361", "Cultivar 1": "1", "Ash": "-0.023821323", "Proline": "0.917474115", "Alcalinity of ash": "-0.869308183", "Alcohol": "0.876274759"}, 
    {"OD280/OD315 of diluted wines": "1.43831115", "Hue": "0.581544212", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.660992744", "Total phenols": "0.296251299", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.34208192", "Color intensity": "-0.487977821", "Proanthocyanins": "-0.229345844", "Magnesium": "-0.332921683", "Cultivar 1": "1", "Ash": "0.561033223", "Proline": "0.85378424", "Alcalinity of ash": "-0.508966192", "Alcohol": "-0.186053111"}, 
    {"OD280/OD315 of diluted wines": "1.706675285", "Hue": "0.713164373", "Nonflavanoid phenols": "-0.659563114", "Malic acid": "-0.472483484", "Total phenols": "0.376367877", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.583033933", "Color intensity": "-0.665331514", "Proanthocyanins": "0.121070982", "Magnesium": "-0.262708342", "Cultivar 1": "1", "Ash": "0.890013905", "Proline": "0.312420304", "Alcalinity of ash": "0.151660791", "Alcohol": "0.616869117"}, 
    {"OD280/OD315 of diluted wines": "0.830960739", "Hue": "0.75703776", "Nonflavanoid phenols": "0.871420038", "Malic acid": "-0.257044329", "Total phenols": "0.536601031", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.653311604", "Color intensity": "-0.639377315", "Proanthocyanins": "0.576612856", "Magnesium": "1.703265196", "Cultivar 1": "1", "Ash": "3.119771861", "Proline": "0.264652898", "Alcalinity of ash": "1.653085752", "Alcohol": "0.060999882"}, 
    {"OD280/OD315 of diluted wines": "0.859209596", "Hue": "-0.16430337", "Nonflavanoid phenols": "-0.17609475", "Malic acid": "-0.50839001", "Total phenols": "0.889113972", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.914342951", "Color intensity": "-0.111641936", "Proanthocyanins": "-0.246866685", "Magnesium": "-0.473348364", "Cultivar 1": "1", "Ash": "0.926567314", "Proline": "1.426993113", "Alcalinity of ash": "-1.019450679", "Alcohol": "0.48098997"}, 
    {"OD280/OD315 of diluted wines": "0.223610329", "Hue": "0.274430501", "Nonflavanoid phenols": "-0.740141175", "Malic acid": "-0.553273167", "Total phenols": "0.168064775", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.16136791", "Color intensity": "-0.479326421", "Proanthocyanins": "-0.422075098", "Magnesium": "-0.403135023", "Cultivar 1": "1", "Ash": "-0.827996323", "Proline": "1.713597549", "Alcalinity of ash": "-0.749194186", "Alcohol": "0.369816124"}, 
    {"OD280/OD315 of diluted wines": "1.113449303", "Hue": "1.283518406", "Nonflavanoid phenols": "0.065639431", "Malic acid": "-0.391693801", "Total phenols": "1.049347127", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.944461953", "Color intensity": "-0.241412931", "Proanthocyanins": "0.296279395", "Magnesium": "0.509638405", "Cultivar 1": "1", "Ash": "1.584528678", "Proline": "0.535334866", "Alcalinity of ash": "-0.028510204", "Alcohol": "1.073917154"}, 
    {"OD280/OD315 of diluted wines": "1.381813437", "Hue": "0.362177276", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.589179693", "Total phenols": "0.568647662", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.301923251", "Color intensity": "-0.154898934", "Proanthocyanins": "0.681737904", "Magnesium": "-0.262708342", "Cultivar 1": "1", "Ash": "-0.572122459", "Proline": "0.917474115", "Alcalinity of ash": "-1.049479178", "Alcohol": "1.259206898"}, 
    {"OD280/OD315 of diluted wines": "0.13886376", "Hue": "1.020278083", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.750759059", "Total phenols": "1.129463704", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.225572635", "Color intensity": "0.277671049", "Proanthocyanins": "1.382571556", "Magnesium": "0.088358361", "Cultivar 1": "1", "Ash": "1.218994587", "Proline": "1.713597549", "Alcalinity of ash": "0.902373272", "Alcohol": "0.900980058"}, 
    {"OD280/OD315 of diluted wines": "0.378979039", "Hue": "0.581544212", "Nonflavanoid phenols": "-1.143031478", "Malic acid": "-0.607132956", "Total phenols": "0.905137288", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.165334632", "Color intensity": "0.796755028", "Proanthocyanins": "0.62917538", "Magnesium": "0.439425064", "Cultivar 1": "1", "Ash": "-0.023821323", "Proline": "2.446031109", "Alcalinity of ash": "-0.118595702", "Alcohol": "0.715690314"}, 
    {"OD280/OD315 of diluted wines": "0.36485461", "Hue": "1.195771632", "Nonflavanoid phenols": "0.468529735", "Malic acid": "-0.454530221", "Total phenols": "0.200111406", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.663351271", "Color intensity": "-0.52690912", "Proanthocyanins": "0.664217062", "Magnesium": "0.298998383", "Cultivar 1": "1", "Ash": "-0.023821323", "Proline": "0.774171896", "Alcalinity of ash": "-0.689137187", "Alcohol": "0.83921681"}, 
    {"OD280/OD315 of diluted wines": "0.548472176", "Hue": "1.283518406", "Nonflavanoid phenols": "1.11315422", "Malic acid": "-0.723829165", "Total phenols": "1.049347127", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.713549607", "Color intensity": "0.147900054", "Proanthocyanins": "-0.422075098", "Magnesium": "2.264971921", "Cultivar 1": "1", "Ash": "1.218994587", "Proline": "1.554372862", "Alcalinity of ash": "0.001518295", "Alcohol": "0.938038007"}, 
    {"OD280/OD315 of diluted wines": "0.36485461", "Hue": "0.625417599", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.481460115", "Total phenols": "0.087948198", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.502716595", "Color intensity": "-0.371183926", "Proanthocyanins": "-0.089179114", "Magnesium": "0.720278427", "Cultivar 1": "1", "Ash": "1.036227541", "Proline": "1.108543739", "Alcalinity of ash": "-0.148624201", "Alcohol": "0.629221766"}, 
    {"OD280/OD315 of diluted wines": "1.2123203", "Hue": "0.362177276", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.472483484", "Total phenols": "0.64876424", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.95450162", "Color intensity": "0.018129059", "Proanthocyanins": "0.471487808", "Magnesium": "0.018145021", "Cultivar 1": "1", "Ash": "0.158945723", "Proline": "0.551257335", "Alcalinity of ash": "0.301803287", "Alcohol": "0.592163817"}, 
    {"OD280/OD315 of diluted wines": "0.237734757", "Hue": "0.581544212", "Nonflavanoid phenols": "-0.17609475", "Malic acid": "-0.625086219", "Total phenols": "0.488531085", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.653311604", "Color intensity": "-0.198155932", "Proanthocyanins": "-0.404554257", "Magnesium": "0.720278427", "Cultivar 1": "1", "Ash": "1.730742315", "Proline": "0.423877585", "Alcalinity of ash": "-1.199621674", "Alcohol": "0.345110824"}, 
    {"OD280/OD315 of diluted wines": "-0.143624803", "Hue": "0.713164373", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.616109587", "Total phenols": "0.248181353", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.402319923", "Color intensity": "-0.349555426", "Proanthocyanins": "-0.264387527", "Magnesium": "-0.122281661", "Cultivar 1": "1", "Ash": "0.67069345", "Proline": "1.140388676", "Alcalinity of ash": "-0.448909194", "Alcohol": "0.060999882"}, 
    {"OD280/OD315 of diluted wines": "0.110614904", "Hue": "0.976404696", "Nonflavanoid phenols": "-0.659563114", "Malic acid": "-0.750759059", "Total phenols": "0.168064775", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.613152935", "Color intensity": "-0.587468917", "Proanthocyanins": "-0.387033416", "Magnesium": "-0.122281661", "Cultivar 1": "1", "Ash": "-0.97420996", "Proline": "0.869706709", "Alcalinity of ash": "-1.199621674", "Alcohol": "0.085705182"}, 
    {"OD280/OD315 of diluted wines": "1.297066869", "Hue": "-0.295923532", "Nonflavanoid phenols": "-1.304187599", "Malic acid": "1.484422174", "Total phenols": "1.129463704", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.014739624", "Color intensity": "0.018129059", "Proanthocyanins": "0.856946317", "Magnesium": "1.984118558", "Cultivar 1": "1", "Ash": "0.524479814", "Proline": "0.041738336", "Alcalinity of ash": "-1.890277157", "Alcohol": "1.506259891"}, 
    {"OD280/OD315 of diluted wines": "1.085200446", "Hue": "-0.032683209", "Nonflavanoid phenols": "-0.17609475", "Malic acid": "-0.562249798", "Total phenols": "1.369813437", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.265731304", "Color intensity": "0.463676141", "Proanthocyanins": "1.312488191", "Magnesium": "1.211771811", "Cultivar 1": "1", "Ash": "-0.206588368", "Proline": "0.153195617", "Alcalinity of ash": "-0.98942218", "Alcohol": "0.690985014"}, 
    {"OD280/OD315 of diluted wines": "0.548472176", "Hue": "-0.208176757", "Nonflavanoid phenols": "-0.740141175", "Malic acid": "1.349772702", "Total phenols": "0.248181353", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.653311604", "Color intensity": "-0.336578327", "Proanthocyanins": "-0.194304161", "Magnesium": "-0.683988386", "Cultivar 1": "1", "Ash": "-0.901103141", "Proline": "0.917474115", "Alcalinity of ash": "-0.2086812", "Alcohol": "0.50569527"}, 
    {"OD280/OD315 of diluted wines": "1.339440153", "Hue": "-0.339796919", "Nonflavanoid phenols": "-1.545921781", "Malic acid": "-0.400670432", "Total phenols": "1.530046591", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.536802319", "Color intensity": "0.160877153", "Proanthocyanins": "0.191154347", "Magnesium": "0.088358361", "Cultivar 1": "1", "Ash": "0.816907087", "Proline": "1.108543739", "Alcalinity of ash": "-1.34976417", "Alcohol": "1.086269803"}, 
    {"OD280/OD315 of diluted wines": "0.548472176", "Hue": "-0.603037242", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "1.475445542", "Total phenols": "0.552624347", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.603113268", "Color intensity": "-0.301972728", "Proanthocyanins": "0.121070982", "Magnesium": "0.228785042", "Cultivar 1": "1", "Ash": "-0.279695187", "Proline": "-0.213021163", "Alcalinity of ash": "-0.59905169", "Alcohol": "0.295700226"}, 
    {"OD280/OD315 of diluted wines": "1.042827162", "Hue": "-0.339796919", "Nonflavanoid phenols": "-0.659563114", "Malic acid": "-0.50839001", "Total phenols": "1.129463704", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.974580955", "Color intensity": "-0.00782514", "Proanthocyanins": "0.76934211", "Magnesium": "0.509638405", "Cultivar 1": "1", "Ash": "-0.97420996", "Proline": "0.439800054", "Alcalinity of ash": "-0.749194186", "Alcohol": "0.060999882"}, 
    {"OD280/OD315 of diluted wines": "1.014578305", "Hue": "-0.383670306", "Nonflavanoid phenols": "-0.498406993", "Malic acid": "1.529305331", "Total phenols": "0.889113972", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.623192602", "Color intensity": "0.078688857", "Proanthocyanins": "-0.597283511", "Magnesium": "0.790491768", "Cultivar 1": "1", "Ash": "0.26860595", "Proline": "1.060776333", "Alcalinity of ash": "-0.1786527", "Alcohol": "1.493907242"}, 
    {"OD280/OD315 of diluted wines": "1.169947015", "Hue": "0.362177276", "Nonflavanoid phenols": "-0.740141175", "Malic acid": "1.125356915", "Total phenols": "1.530046591", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.145255298", "Color intensity": "-0.068384938", "Proanthocyanins": "1.049675571", "Magnesium": "0.158571702", "Cultivar 1": "1", "Ash": "-0.316248596", "Proline": "1.013008927", "Alcalinity of ash": "-1.049479178", "Alcohol": "1.703902286"}, 
    {"OD280/OD315 of diluted wines": "1.014578305", "Hue": "-0.208176757", "Nonflavanoid phenols": "-1.223609539", "Malic acid": "-0.589179693", "Total phenols": "1.289696859", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.366127977", "Color intensity": "0.450699042", "Proanthocyanins": "0.962071365", "Magnesium": "0.088358361", "Cultivar 1": "1", "Ash": "-0.901103141", "Proline": "0.758249428", "Alcalinity of ash": "-1.049479178", "Alcohol": "1.110975103"}, 
    {"OD280/OD315 of diluted wines": "0.195361473", "Hue": "0.493797437", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "-0.283974223", "Total phenols": "0.728880817", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.894263617", "Color intensity": "0.49395604", "Proanthocyanins": "1.382571556", "Magnesium": "0.228785042", "Cultivar 1": "1", "Ash": "0.122392314", "Proline": "0.997086458", "Alcalinity of ash": "-0.2086812", "Alcohol": "1.358028096"}, 
    {"OD280/OD315 of diluted wines": "0.689716458", "Hue": "0.713164373", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "-0.544296535", "Total phenols": "0.937183918", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.516722985", "Color intensity": "1.661894994", "Proanthocyanins": "0.856946317", "Magnesium": "0.579851746", "Cultivar 1": "1", "Ash": "-0.352802005", "Proline": "1.633985206", "Alcalinity of ash": "-0.629080189", "Alcohol": "1.160385701"}, 
    {"OD280/OD315 of diluted wines": "0.421352323", "Hue": "0.713164373", "Nonflavanoid phenols": "-1.545921781", "Malic acid": "-0.544296535", "Total phenols": "0.680810871", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.24565197", "Color intensity": "0.926526023", "Proanthocyanins": "2.311176145", "Magnesium": "-0.543561704", "Cultivar 1": "1", "Ash": "-1.193530414", "Proline": "1.283690895", "Alcalinity of ash": "-2.13050515", "Alcohol": "0.060999882"}, 
    {"OD280/OD315 of diluted wines": "1.071076018", "Hue": "1.239645019", "Nonflavanoid phenols": "-1.143031478", "Malic acid": "-0.616109587", "Total phenols": "0.248181353", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.964541288", "Color intensity": "0.234414051", "Proanthocyanins": "1.224883984", "Magnesium": "-0.403135023", "Cultivar 1": "1", "Ash": "0.853460496", "Proline": "1.649907674", "Alcalinity of ash": "-0.689137187", "Alcohol": "1.024506555"}, 
    {"OD280/OD315 of diluted wines": "0.915707308", "Hue": "0.230557114", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "-0.526343273", "Total phenols": "2.539515467", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.717516329", "Color intensity": "0.861640526", "Proanthocyanins": "0.489008649", "Magnesium": "0.790491768", "Cultivar 1": "1", "Ash": "0.195499132", "Proline": "1.411070644", "Alcalinity of ash": "-1.650049163", "Alcohol": "1.012153905"}, 
    {"OD280/OD315 of diluted wines": "0.449601179", "Hue": "0.75703776", "Nonflavanoid phenols": "0.226795553", "Malic acid": "-0.391693801", "Total phenols": "1.129463704", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.763747943", "Color intensity": "0.537213039", "Proanthocyanins": "0.156112665", "Magnesium": "1.07134513", "Cultivar 1": "1", "Ash": "1.145887769", "Proline": "2.000201986", "Alcalinity of ash": "-0.719165687", "Alcohol": "0.950390657"}, 
    {"OD280/OD315 of diluted wines": "0.830960739", "Hue": "-0.16430337", "Nonflavanoid phenols": "-1.223609539", "Malic acid": "-0.598156324", "Total phenols": "0.488531085", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.874184283", "Color intensity": "0.342556546", "Proanthocyanins": "0.050987617", "Magnesium": "1.281985152", "Cultivar 1": "1", "Ash": "-0.425908823", "Proline": "0.997086458", "Alcalinity of ash": "-0.929365181", "Alcohol": "0.913332708"}, 
    {"OD280/OD315 of diluted wines": "0.590845461", "Hue": "0.098936953", "Nonflavanoid phenols": "-1.304187599", "Malic acid": "-0.544296535", "Total phenols": "1.065370442", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.753708276", "Color intensity": "0.515584539", "Proanthocyanins": "1.505217445", "Magnesium": "1.141558471", "Cultivar 1": "1", "Ash": "0.341712768", "Proline": "1.188156082", "Alcalinity of ash": "0.301803287", "Alcohol": "0.690985014"}, 
    {"OD280/OD315 of diluted wines": "0.986329449", "Hue": "-0.076556596", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.57122643", "Total phenols": "1.449930014", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "0.974580955", "Color intensity": "0.571818637", "Proanthocyanins": "0.76934211", "Magnesium": "1.281985152", "Cultivar 1": "1", "Ash": "-0.243141777", "Proline": "0.710482022", "Alcalinity of ash": "-0.95939368", "Alcohol": "1.506259891"}, 
    {"OD280/OD315 of diluted wines": "0.322481326", "Hue": "0.493797437", "Nonflavanoid phenols": "-0.417828932", "Malic acid": "-0.32885738", "Total phenols": "1.129463704", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.205493301", "Color intensity": "0.407442044", "Proanthocyanins": "0.121070982", "Magnesium": "0.158571702", "Cultivar 1": "1", "Ash": "1.145887769", "Proline": "1.665830143", "Alcalinity of ash": "-0.809251184", "Alcohol": "0.357463474"}, 
    {"OD280/OD315 of diluted wines": "0.36485461", "Hue": "-0.295923532", "Nonflavanoid phenols": "-1.38476566", "Malic acid": "-0.813595479", "Total phenols": "1.770396324", "Cultivar 2": "0", "Cultivar 3": "0", "Flavanoids": "1.647238659", "Color intensity": "0.75349803", "Proanthocyanins": "0.786862952", "Magnesium": "0.579851746", "Cultivar 1": "1", "Ash": "0.487926405", "Proline": "1.713597549", "Alcalinity of ash": "-0.839279684", "Alcohol": "0.888627409"}, 
    {"OD280/OD315 of diluted wines": "-1.118210346", "Hue": "0.406050663", "Nonflavanoid phenols": "-0.659563114", "Malic acid": "-1.25345042", "Total phenols": "-0.504914475", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-1.46505818", "Color intensity": "-1.344466387", "Proanthocyanins": "-2.051513339", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-3.679162234", "Proline": "-0.722540161", "Alcalinity of ash": "-2.671018136", "Alcohol": "-0.778980294"}, 
    {"OD280/OD315 of diluted wines": "-1.330076768", "Hue": "1.283518406", "Nonflavanoid phenols": "2.160669008", "Malic acid": "-1.109824317", "Total phenols": "-0.392751267", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.942995485", "Color intensity": "-0.77347401", "Proanthocyanins": "-2.069034181", "Magnesium": "0.088358361", "Cultivar 1": "0", "Ash": "-0.316248596", "Proline": "-0.213021163", "Alcalinity of ash": "-1.049479178", "Alcohol": "-0.828390893"}, 
    {"OD280/OD315 of diluted wines": "-1.443072193", "Hue": "0.098936953", "Nonflavanoid phenols": "1.354888402", "Malic acid": "-0.876431899", "Total phenols": "-0.440821213", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.621726134", "Color intensity": "0.299299548", "Proanthocyanins": "-1.701096513", "Magnesium": "0.018145021", "Cultivar 1": "0", "Ash": "-1.266637233", "Proline": "-0.945454722", "Alcalinity of ash": "-0.809251184", "Alcohol": "-0.445458753"}, 
    {"OD280/OD315 of diluted wines": "-0.214246944", "Hue": "1.195771632", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "-0.975174845", "Total phenols": "-0.312634689", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.240218779", "Color intensity": "-0.544211919", "Proanthocyanins": "-1.508367259", "Magnesium": "-0.403135023", "Cultivar 1": "0", "Ash": "-1.632171324", "Proline": "-0.37224585", "Alcalinity of ash": "-0.448909194", "Alcohol": "0.826864161"}, 
    {"OD280/OD315 of diluted wines": "0.36485461", "Hue": "1.151898245", "Nonflavanoid phenols": "-1.38476566", "Malic acid": "-1.082894423", "Total phenols": "1.930629478", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "1.074977627", "Color intensity": "-0.26304143", "Proanthocyanins": "0.489008649", "Magnesium": "-0.894628408", "Cultivar 1": "0", "Ash": "-0.754889505", "Proline": "-1.040989535", "Alcalinity of ash": "-0.148624201", "Alcohol": "-0.778980294"}, 
    {"OD280/OD315 of diluted wines": "-0.539108791", "Hue": "2.160986149", "Nonflavanoid phenols": "0.710263917", "Malic acid": "-0.795642216", "Total phenols": "-0.649124314", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.280377448", "Color intensity": "-0.911896404", "Proanthocyanins": "-0.98274202", "Magnesium": "0.298998383", "Cultivar 1": "0", "Ash": "0.597586632", "Proline": "-1.247981628", "Alcalinity of ash": "-0.148624201", "Alcohol": "-1.026033287"}, 
    {"OD280/OD315 of diluted wines": "-0.440237794", "Hue": "1.020278083", "Nonflavanoid phenols": "0.065639431", "Malic acid": "-1.011081371", "Total phenols": "0.200111406", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.623192602", "Color intensity": "-0.198155932", "Proanthocyanins": "0.856946317", "Magnesium": "-0.122281661", "Cultivar 1": "0", "Ash": "0.707246859", "Proline": "-0.21939015", "Alcalinity of ash": "-0.418880694", "Alcohol": "-0.778980294"}, 
    {"OD280/OD315 of diluted wines": "0.802711883", "Hue": "0.713164373", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-1.190614", "Total phenols": "1.097417073", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "1.155294965", "Color intensity": "0.104643056", "Proanthocyanins": "1.207363143", "Magnesium": "-1.526548473", "Cultivar 1": "0", "Ash": "-2.436346324", "Proline": "-0.779861048", "Alcalinity of ash": "-1.34976417", "Alcohol": "0.13511578"}, 
    {"OD280/OD315 of diluted wines": "1.226444728", "Hue": "0.713164373", "Nonflavanoid phenols": "-0.740141175", "Malic acid": "-1.046987897", "Total phenols": "-0.296611374", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.029385768", "Color intensity": "-0.163550334", "Proanthocyanins": "-0.965221179", "Magnesium": "-1.526548473", "Cultivar 1": "0", "Ash": "-1.632171324", "Proline": "-0.754385098", "Alcalinity of ash": "0.031546794", "Alcohol": "-0.778980294"}, 
    {"OD280/OD315 of diluted wines": "-0.962841636", "Hue": "0.274430501", "Nonflavanoid phenols": "1.516044523", "Malic acid": "-1.25345042", "Total phenols": "0.376367877", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.732162473", "Color intensity": "-0.816731008", "Proanthocyanins": "-2.051513339", "Magnesium": "0.720278427", "Cultivar 1": "0", "Ash": "-0.023821323", "Proline": "0.009893399", "Alcalinity of ash": "-0.749194186", "Alcohol": "0.419226722"}, 
    {"OD280/OD315 of diluted wines": "0.647343173", "Hue": "1.415138568", "Nonflavanoid phenols": "-1.787655963", "Malic acid": "-1.029034634", "Total phenols": "-0.713217576", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.752241808", "Color intensity": "-0.955153403", "Proanthocyanins": "1.592821651", "Magnesium": "3.599025393", "Cultivar 1": "0", "Ash": "-2.253579279", "Proline": "-0.092010401", "Alcalinity of ash": "-0.809251184", "Alcohol": "-0.976622688"}, 
    {"OD280/OD315 of diluted wines": "-1.118210346", "Hue": "-0.225726112", "Nonflavanoid phenols": "0.065639431", "Malic acid": "-0.652016113", "Total phenols": "-1.914966237", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-1.013273155", "Color intensity": "-0.868639406", "Proanthocyanins": "-0.229345844", "Magnesium": "0.228785042", "Cultivar 1": "0", "Ash": "-0.572122459", "Proline": "0.392032648", "Alcalinity of ash": "0.271774788", "Alcohol": "-0.877801491"}, 
    {"OD280/OD315 of diluted wines": "0.774463027", "Hue": "1.766125665", "Nonflavanoid phenols": "-1.223609539", "Malic acid": "-0.741782427", "Total phenols": "1.049347127", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.834025614", "Color intensity": "-0.725891312", "Proanthocyanins": "0.489008649", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "1.10933436", "Proline": "-1.072834472", "Alcalinity of ash": "1.653085752", "Alcohol": "1.061564504"}, 
    {"OD280/OD315 of diluted wines": "0.237734757", "Hue": "0.098936953", "Nonflavanoid phenols": "-0.740141175", "Malic acid": "-0.607132956", "Total phenols": "-0.66514763", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.190020443", "Color intensity": "-0.570166118", "Proanthocyanins": "-0.98274202", "Magnesium": "-0.894628408", "Cultivar 1": "0", "Ash": "-0.462462232", "Proline": "-0.87539586", "Alcalinity of ash": "1.35280076", "Alcohol": "0.604516467"}, 
    {"OD280/OD315 of diluted wines": "1.254693584", "Hue": "1.546758729", "Nonflavanoid phenols": "-1.223609539", "Malic acid": "-0.598156324", "Total phenols": "1.610163169", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.864144615", "Color intensity": "-0.738868411", "Proanthocyanins": "0.646696221", "Magnesium": "2.756465305", "Cultivar 1": "0", "Ash": "0.853460496", "Proline": "0.758249428", "Alcalinity of ash": "3.154510714", "Alcohol": "-0.013116016"}, 
    {"OD280/OD315 of diluted wines": "0.732089742", "Hue": "0.14281034", "Nonflavanoid phenols": "-1.868234024", "Malic acid": "-1.118800949", "Total phenols": "1.738349693", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.111169574", "Color intensity": "-0.799428209", "Proanthocyanins": "0.103550141", "Magnesium": "0.088358361", "Cultivar 1": "0", "Ash": "-0.243141777", "Proline": "0.442984548", "Alcalinity of ash": "0.451945783", "Alcohol": "-1.28543893"}, 
    {"OD280/OD315 of diluted wines": "-0.666228645", "Hue": "1.195771632", "Nonflavanoid phenols": "-0.17609475", "Malic acid": "-0.409647064", "Total phenols": "-1.097777148", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.461091458", "Color intensity": "-0.544211919", "Proanthocyanins": "-0.772491924", "Magnesium": "-0.192495001", "Cultivar 1": "0", "Ash": "-1.632171324", "Proline": "-1.015513585", "Alcalinity of ash": "-1.049479178", "Alcohol": "-1.656018419"}, 
    {"OD280/OD315 of diluted wines": "-0.185998088", "Hue": "1.020278083", "Nonflavanoid phenols": "-0.981875357", "Malic acid": "-1.289356946", "Total phenols": "-0.552984421", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.000733234", "Color intensity": "-0.198155932", "Proanthocyanins": "-0.229345844", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "-2.399792915", "Proline": "-1.130155359", "Alcalinity of ash": "-1.049479178", "Alcohol": "0.036294583"}, 
    {"OD280/OD315 of diluted wines": "-0.129500375", "Hue": "0.011190179", "Nonflavanoid phenols": "0.549107795", "Malic acid": "0.496992713", "Total phenols": "-0.921520678", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.712083139", "Color intensity": "-1.041667399", "Proanthocyanins": "-1.12290875", "Magnesium": "0.860705108", "Cultivar 1": "0", "Ash": "-0.499015641", "Proline": "-0.786230036", "Alcalinity of ash": "-0.448909194", "Alcohol": "-1.433670725"}, 
    {"OD280/OD315 of diluted wines": "-0.426113366", "Hue": "0.44992405", "Nonflavanoid phenols": "-0.09551669", "Malic acid": "-1.208567263", "Total phenols": "-0.633100999", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.179980776", "Color intensity": "-0.717239912", "Proanthocyanins": "2.048363525", "Magnesium": "2.545825283", "Cultivar 1": "0", "Ash": "-1.522511096", "Proline": "0.009893399", "Alcalinity of ash": "-1.409821169", "Alcohol": "-0.828390893"}, 
    {"OD280/OD315 of diluted wines": "0.732089742", "Hue": "1.020278083", "Nonflavanoid phenols": "0.549107795", "Malic acid": "1.376702596", "Total phenols": "0.857067341", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.52279593", "Color intensity": "-1.076272998", "Proanthocyanins": "0.62917538", "Magnesium": "0.088358361", "Cultivar 1": "0", "Ash": "0.122392314", "Proline": "-0.904056304", "Alcalinity of ash": "1.052515768", "Alcohol": "-0.371342855"}, 
    {"OD280/OD315 of diluted wines": "0.717965314", "Hue": "1.853872439", "Nonflavanoid phenols": "-0.498406993", "Malic acid": "-1.271403683", "Total phenols": "0.200111406", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.23164558", "Color intensity": "-1.106552897", "Proanthocyanins": "-0.281908368", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "-1.339744051", "Proline": "-1.493187646", "Alcalinity of ash": "-0.148624201", "Alcohol": "-1.236028331"}, 
    {"OD280/OD315 of diluted wines": "0.746214171", "Hue": "0.888657922", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.472483484", "Total phenols": "-0.152401534", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.502716595", "Color intensity": "-0.500954921", "Proanthocyanins": "0.313800236", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "-0.608675869", "Proline": "-0.104748376", "Alcalinity of ash": "-0.2086812", "Alcohol": "-0.346637556"}, 
    {"OD280/OD315 of diluted wines": "0.152988188", "Hue": "1.546758729", "Nonflavanoid phenols": "0.307373613", "Malic acid": "-1.082894423", "Total phenols": "-0.472867844", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.451051791", "Color intensity": "-1.236323892", "Proanthocyanins": "-0.334470892", "Magnesium": "-1.526548473", "Cultivar 1": "0", "Ash": "0.524479814", "Proline": "-0.37224585", "Alcalinity of ash": "1.35280076", "Alcohol": "-1.137207134"}, 
    {"OD280/OD315 of diluted wines": "-0.849846211", "Hue": "-0.515290467", "Nonflavanoid phenols": "1.999512887", "Malic acid": "1.367725965", "Total phenols": "-1.033683886", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.441012124", "Color intensity": "-0.111641936", "Proanthocyanins": "0.050987617", "Magnesium": "-1.035055089", "Cultivar 1": "0", "Ash": "-0.170034959", "Proline": "-0.738462629", "Alcalinity of ash": "0.902373272", "Alcohol": "0.060999882"}, 
    {"OD280/OD315 of diluted wines": "0.661467602", "Hue": "-0.734657403", "Nonflavanoid phenols": "-1.143031478", "Malic acid": "-1.298333578", "Total phenols": "-0.152401534", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.181447244", "Color intensity": "-0.868639406", "Proanthocyanins": "1.330009032", "Magnesium": "-0.403135023", "Cultivar 1": "0", "Ash": "0.780353678", "Proline": "-0.722540161", "Alcalinity of ash": "-0.448909194", "Alcohol": "-1.433670725"}, 
    {"OD280/OD315 of diluted wines": "0.774463027", "Hue": "1.195771632", "Nonflavanoid phenols": "-0.498406993", "Malic acid": "-1.217543895", "Total phenols": "-0.152401534", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.089623771", "Color intensity": "-1.054644499", "Proanthocyanins": "-0.229345844", "Magnesium": "-0.05206832", "Cultivar 1": "0", "Ash": "-0.462462232", "Proline": "-0.945454722", "Alcalinity of ash": "-0.448909194", "Alcohol": "-0.408400804"}, 
    {"OD280/OD315 of diluted wines": "-0.496735507", "Hue": "1.634505503", "Nonflavanoid phenols": "0.549107795", "Malic acid": "-0.652016113", "Total phenols": "-0.825380785", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.340615451", "Color intensity": "-1.128181396", "Proanthocyanins": "-0.054137431", "Magnesium": "-0.683988386", "Cultivar 1": "0", "Ash": "-0.206588368", "Proline": "-0.802152504", "Alcalinity of ash": "0.992458769", "Alcohol": "-1.038385937"}, 
    {"OD280/OD315 of diluted wines": "0.845085168", "Hue": "1.766125665", "Nonflavanoid phenols": "0.307373613", "Malic acid": "-0.598156324", "Total phenols": "-0.601054368", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.420932789", "Color intensity": "-1.063295898", "Proanthocyanins": "-0.43959594", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "0.926567314", "Proline": "-0.588791424", "Alcalinity of ash": "1.953370745", "Alcohol": "-1.668371069"}, 
    {"OD280/OD315 of diluted wines": "0.195361473", "Hue": "0.186683727", "Nonflavanoid phenols": "0.951998098", "Malic acid": "-0.248067697", "Total phenols": "-0.552984421", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.340615451", "Color intensity": "-0.976781902", "Proanthocyanins": "-0.422075098", "Magnesium": "-1.105268429", "Cultivar 1": "0", "Ash": "0.341712768", "Proline": "-0.213021163", "Alcalinity of ash": "0.632116779", "Alcohol": "-1.680723718"}, 
    {"OD280/OD315 of diluted wines": "0.845085168", "Hue": "0.493797437", "Nonflavanoid phenols": "0.468529735", "Malic acid": "-0.903361794", "Total phenols": "-0.152401534", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.441012124", "Color intensity": "-1.435306084", "Proanthocyanins": "-0.369512574", "Magnesium": "-2.088255198", "Cultivar 1": "0", "Ash": "-0.243141777", "Proline": "-0.388168318", "Alcalinity of ash": "1.232686763", "Alcohol": "-1.137207134"}, 
    {"OD280/OD315 of diluted wines": "-0.482611079", "Hue": "0.537670824", "Nonflavanoid phenols": "1.274310341", "Malic acid": "-0.454530221", "Total phenols": "-1.113800463", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.531369129", "Color intensity": "-1.149809895", "Proanthocyanins": "0.086029299", "Magnesium": "-1.315908451", "Cultivar 1": "0", "Ash": "-0.170034959", "Proline": "-0.84991991", "Alcalinity of ash": "-0.298766697", "Alcohol": "-1.137207134"}, 
    {"OD280/OD315 of diluted wines": "0.054117191", "Hue": "0.406050663", "Nonflavanoid phenols": "1.11315422", "Malic acid": "-0.741782427", "Total phenols": "-1.354150196", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.782360809", "Color intensity": "-0.630725915", "Proanthocyanins": "0.068508458", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "0.195499132", "Proline": "-0.945454722", "Alcalinity of ash": "0.752230776", "Alcohol": "-1.236028331"}, 
    {"OD280/OD315 of diluted wines": "-0.77922407", "Hue": "0.011190179", "Nonflavanoid phenols": "1.757778705", "Malic acid": "-0.723829165", "Total phenols": "-1.466313404", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.571527798", "Color intensity": "-0.868639406", "Proanthocyanins": "0.050987617", "Magnesium": "-1.386121792", "Cultivar 1": "0", "Ash": "-0.389355414", "Proline": "-0.802152504", "Alcalinity of ash": "0.361860286", "Alcohol": "-0.383695505"}, 
    {"OD280/OD315 of diluted wines": "0.972205021", "Hue": "0.844784535", "Nonflavanoid phenols": "-0.901297296", "Malic acid": "0.443132925", "Total phenols": "0.248181353", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.221605913", "Color intensity": "-1.257952391", "Proanthocyanins": "0.699258745", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-0.53556905", "Proline": "-1.454973721", "Alcalinity of ash": "-0.448909194", "Alcohol": "-0.877801491"}, 
    {"OD280/OD315 of diluted wines": "0.491974464", "Hue": "0.888657922", "Nonflavanoid phenols": "-1.545921781", "Malic acid": "-0.310904118", "Total phenols": "1.161510335", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.23164558", "Color intensity": "-0.782125409", "Proanthocyanins": "-0.422075098", "Magnesium": "-0.122281661", "Cultivar 1": "0", "Ash": "-0.316248596", "Proline": "-1.279826565", "Alcalinity of ash": "-0.448909194", "Alcohol": "-1.705429018"}, 
    {"OD280/OD315 of diluted wines": "0.025868335", "Hue": "0.888657922", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "-0.732805796", "Total phenols": "0.32829793", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.241685247", "Color intensity": "-1.063295898", "Proanthocyanins": "2.959447273", "Magnesium": "4.37137214", "Cultivar 1": "0", "Ash": "-0.608675869", "Proline": "0.605393728", "Alcalinity of ash": "-0.148624201", "Alcohol": "-0.655453797"}, 
    {"OD280/OD315 of diluted wines": "-0.496735507", "Hue": "-0.032683209", "Nonflavanoid phenols": "-1.787655963", "Malic acid": "-0.194207909", "Total phenols": "-1.113800463", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-1.043392157", "Color intensity": "-1.106552897", "Proanthocyanins": "-0.054137431", "Magnesium": "2.405398602", "Cultivar 1": "0", "Ash": "1.365208223", "Proline": "-0.388168318", "Alcalinity of ash": "0.602088279", "Alcohol": "-1.470728674"}, 
    {"OD280/OD315 of diluted wines": "0.181237044", "Hue": "1.195771632", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.831548742", "Total phenols": "0.408414508", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.472597594", "Color intensity": "-0.933524903", "Proanthocyanins": "0.313800236", "Magnesium": "-1.035055089", "Cultivar 1": "0", "Ash": "-1.412850869", "Proline": "-1.015513585", "Alcalinity of ash": "-1.049479178", "Alcohol": "-0.877801491"}, 
    {"OD280/OD315 of diluted wines": "0.223610329", "Hue": "0.362177276", "Nonflavanoid phenols": "-0.981875357", "Malic acid": "-1.136754212", "Total phenols": "1.962676109", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "1.727555997", "Color intensity": "-0.241412931", "Proanthocyanins": "0.62917538", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-0.97420996", "Proline": "-0.276711037", "Alcalinity of ash": "-0.298766697", "Alcohol": "-0.778980294"}, 
    {"OD280/OD315 of diluted wines": "0.308356898", "Hue": "2.029365988", "Nonflavanoid phenols": "0.710263917", "Malic acid": "0.748338394", "Total phenols": "0.889113972", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.964541288", "Color intensity": "-1.193066893", "Proanthocyanins": "2.135967732", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-0.572122459", "Proline": "-1.085572447", "Alcalinity of ash": "-0.448909194", "Alcohol": "-0.877801491"}, 
    {"OD280/OD315 of diluted wines": "0.491974464", "Hue": "1.37126518", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.230114434", "Total phenols": "-0.104331588", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.141288575", "Color intensity": "-0.76049691", "Proanthocyanins": "-0.334470892", "Magnesium": "-0.192495001", "Cultivar 1": "0", "Ash": "-2.436346324", "Proline": "-0.11748635", "Alcalinity of ash": "-0.59905169", "Alcohol": "-1.137207134"}, 
    {"OD280/OD315 of diluted wines": "0.223610329", "Hue": "0.362177276", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.894385162", "Total phenols": "-1.354150196", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.67192447", "Color intensity": "-1.128181396", "Proanthocyanins": "-0.422075098", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-1.705278142", "Proline": "-0.588791424", "Alcalinity of ash": "-0.298766697", "Alcohol": "-0.494869352"}, 
    {"OD280/OD315 of diluted wines": "1.085200446", "Hue": "-0.690784016", "Nonflavanoid phenols": "-0.17609475", "Malic acid": "0.102020929", "Total phenols": "0.424437823", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.081050572", "Color intensity": "-0.976781902", "Proanthocyanins": "-0.492158464", "Magnesium": "-0.122281661", "Cultivar 1": "0", "Ash": "0.341712768", "Proline": "-0.983668647", "Alcalinity of ash": "0.451945783", "Alcohol": "-0.816038243"}, 
    {"OD280/OD315 of diluted wines": "-0.2424958", "Hue": "-0.076556596", "Nonflavanoid phenols": "0.065639431", "Malic acid": "-0.553273167", "Total phenols": "0.32829793", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.390813788", "Color intensity": "-1.296883689", "Proanthocyanins": "-0.299429209", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "-1.77838496", "Proline": "-1.056912003", "Alcalinity of ash": "0.001518295", "Alcohol": "-1.458376025"}, 
    {"OD280/OD315 of diluted wines": "1.353564581", "Hue": "0.362177276", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "-0.544296535", "Total phenols": "-0.152401534", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.109703105", "Color intensity": "-0.916222104", "Proanthocyanins": "-0.194304161", "Magnesium": "-1.035055089", "Cultivar 1": "0", "Ash": "-1.412850869", "Proline": "-0.238497113", "Alcalinity of ash": "0.301803287", "Alcohol": "-0.606043199"}, 
    {"OD280/OD315 of diluted wines": "0.972205021", "Hue": "-0.427543693", "Nonflavanoid phenols": "2.40240319", "Malic acid": "0.191787244", "Total phenols": "-0.985613939", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.190020443", "Color intensity": "-1.0200389", "Proanthocyanins": "-0.299429209", "Magnesium": "-0.683988386", "Cultivar 1": "0", "Ash": "-0.352802005", "Proline": "-1.375361377", "Alcalinity of ash": "0.752230776", "Alcohol": "-0.717217046"}, 
    {"OD280/OD315 of diluted wines": "0.788587455", "Hue": "0.186683727", "Nonflavanoid phenols": "0.065639431", "Malic acid": "-0.544296535", "Total phenols": "-1.033683886", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.000733234", "Color intensity": "-0.717239912", "Proanthocyanins": "0.068508458", "Magnesium": "-1.386121792", "Cultivar 1": "0", "Ash": "-0.901103141", "Proline": "-0.754385098", "Alcalinity of ash": "-0.148624201", "Alcohol": "-0.92721209"}, 
    {"OD280/OD315 of diluted wines": "-0.270744657", "Hue": "-0.339796919", "Nonflavanoid phenols": "0.951998098", "Malic acid": "-0.526343273", "Total phenols": "-1.466313404", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.270337781", "Color intensity": "-0.76049691", "Proanthocyanins": "0.068508458", "Magnesium": "-1.105268429", "Cultivar 1": "0", "Ash": "-0.316248596", "Proline": "-0.82444396", "Alcalinity of ash": "0.902373272", "Alcohol": "-0.346637556"}, 
    {"OD280/OD315 of diluted wines": "0.576721033", "Hue": "-0.427543693", "Nonflavanoid phenols": "0.226795553", "Malic acid": "-0.939268319", "Total phenols": "0.103971513", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.010772901", "Color intensity": "-1.0200389", "Proanthocyanins": "0.856946317", "Magnesium": "-0.543561704", "Cultivar 1": "0", "Ash": "-1.559064506", "Proline": "-1.384914858", "Alcalinity of ash": "-0.148624201", "Alcohol": "-0.964270039"}, 
    {"OD280/OD315 of diluted wines": "0.915707308", "Hue": "0.011190179", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "-0.885408531", "Total phenols": "0.712857502", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.894263617", "Color intensity": "-1.041667399", "Proanthocyanins": "1.57530081", "Magnesium": "-0.403135023", "Cultivar 1": "0", "Ash": "1.218994587", "Proline": "-0.213021163", "Alcalinity of ash": "0.151660791", "Alcohol": "-1.717781667"}, 
    {"OD280/OD315 of diluted wines": "0.280108041", "Hue": "-0.910150952", "Nonflavanoid phenols": "-0.981875357", "Malic acid": "1.260006387", "Total phenols": "1.417883383", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.552914931", "Color intensity": "-0.933524903", "Proanthocyanins": "3.485072512", "Magnesium": "0.509638405", "Cultivar 1": "0", "Ash": "-1.997705415", "Proline": "-0.588791424", "Alcalinity of ash": "0.001518295", "Alcohol": "-1.903071412"}, 
    {"OD280/OD315 of diluted wines": "0.237734757", "Hue": "-0.252050144", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "0.084067667", "Total phenols": "0.408414508", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.241685247", "Color intensity": "-1.322837888", "Proanthocyanins": "-0.649846035", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-0.718336096", "Proline": "-1.34351644", "Alcalinity of ash": "0.451945783", "Alcohol": "-0.593690549"}, 
    {"OD280/OD315 of diluted wines": "-0.157749231", "Hue": "1.195771632", "Nonflavanoid phenols": "1.918934826", "Malic acid": "0.308483453", "Total phenols": "-0.873450731", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.000733234", "Color intensity": "-0.544211919", "Proanthocyanins": "-0.947700337", "Magnesium": "0.228785042", "Cultivar 1": "0", "Ash": "2.023169588", "Proline": "-0.445489206", "Alcalinity of ash": "0.151660791", "Alcohol": "-1.532491923"}, 
    {"OD280/OD315 of diluted wines": "-0.426113366", "Hue": "0.625417599", "Nonflavanoid phenols": "0.468529735", "Malic acid": "-1.43298305", "Total phenols": "0.296251299", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.0193461", "Color intensity": "-0.855662307", "Proanthocyanins": "-0.264387527", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "0.487926405", "Proline": "-0.996406622", "Alcalinity of ash": "0.451945783", "Alcohol": "-1.96483466"}, 
    {"OD280/OD315 of diluted wines": "0.816836311", "Hue": "-0.120429983", "Nonflavanoid phenols": "0.549107795", "Malic acid": "-0.849502005", "Total phenols": "0.424437823", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.261764582", "Color intensity": "-0.933524903", "Proanthocyanins": "-0.965221179", "Magnesium": "-1.105268429", "Cultivar 1": "0", "Ash": "0.487926405", "Proline": "-1.152446816", "Alcalinity of ash": "0.902373272", "Alcohol": "-1.137207134"}, 
    {"OD280/OD315 of diluted wines": "0.36485461", "Hue": "3.301694215", "Nonflavanoid phenols": "1.274310341", "Malic acid": "-0.741782427", "Total phenols": "0.264204668", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.141288575", "Color intensity": "-1.366094886", "Proanthocyanins": "0.734300428", "Magnesium": "-1.035055089", "Cultivar 1": "0", "Ash": "-0.608675869", "Proline": "-1.082387953", "Alcalinity of ash": "0.602088279", "Alcohol": "-2.434235347"}, 
    {"OD280/OD315 of diluted wines": "1.014578305", "Hue": "-0.032683209", "Nonflavanoid phenols": "-0.498406993", "Malic acid": "-0.777688953", "Total phenols": "-0.504914475", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.430972456", "Color intensity": "-1.344466387", "Proanthocyanins": "-0.106699955", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "-1.37629746", "Proline": "-0.802152504", "Alcalinity of ash": "0.391888785", "Alcohol": "-1.458376025"}, 
    {"OD280/OD315 of diluted wines": "0.491974464", "Hue": "0.44992405", "Nonflavanoid phenols": "-0.17609475", "Malic acid": "-0.652016113", "Total phenols": "-0.472867844", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.060971237", "Color intensity": "-1.296883689", "Proanthocyanins": "0.033466776", "Magnesium": "0.579851746", "Cultivar 1": "0", "Ash": "-0.645229278", "Proline": "-1.279826565", "Alcalinity of ash": "0.902373272", "Alcohol": "-0.717217046"}, 
    {"OD280/OD315 of diluted wines": "-0.694477501", "Hue": "-1.129517888", "Nonflavanoid phenols": "0.549107795", "Malic acid": "0.981730812", "Total phenols": "-1.065730517", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.782360809", "Color intensity": "-0.717239912", "Proanthocyanins": "-1.333158846", "Magnesium": "-1.386121792", "Cultivar 1": "0", "Ash": "-1.412850869", "Proline": "-1.193845234", "Alcalinity of ash": "-1.049479178", "Alcohol": "-0.284874308"}, 
    {"OD280/OD315 of diluted wines": "0.619094317", "Hue": "-0.120429983", "Nonflavanoid phenols": "0.065639431", "Malic acid": "0.981730812", "Total phenols": "-0.472867844", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.390813788", "Color intensity": "-1.634288276", "Proanthocyanins": "0.489008649", "Magnesium": "-0.894628408", "Cultivar 1": "0", "Ash": "-1.339744051", "Proline": "-0.582422436", "Alcalinity of ash": "-0.148624201", "Alcohol": "-1.236028331"}, 
    {"OD280/OD315 of diluted wines": "1.099324874", "Hue": "-0.690784016", "Nonflavanoid phenols": "-0.337250872", "Malic acid": "0.057137772", "Total phenols": "0.969230549", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.763747943", "Color intensity": "-0.782125409", "Proanthocyanins": "0.418925284", "Magnesium": "-0.262708342", "Cultivar 1": "0", "Ash": "0.195499132", "Proline": "-0.388168318", "Alcalinity of ash": "0.151660791", "Alcohol": "-1.915424062"}, 
    {"OD280/OD315 of diluted wines": "1.523057719", "Hue": "-0.120429983", "Nonflavanoid phenols": "0.871420038", "Malic acid": "-0.257044329", "Total phenols": "1.417883383", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "3.062831737", "Color intensity": "0.407442044", "Proanthocyanins": "0.489008649", "Magnesium": "1.352198493", "Cultivar 1": "0", "Ash": "3.15632527", "Proline": "-0.897687316", "Alcalinity of ash": "2.704083226", "Alcohol": "-1.779544916"}, 
    {"OD280/OD315 of diluted wines": "0.717965314", "Hue": "-0.16430337", "Nonflavanoid phenols": "0.549107795", "Malic acid": "1.879393958", "Total phenols": "-0.152401534", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.101129906", "Color intensity": "-1.28823229", "Proanthocyanins": "0.208675189", "Magnesium": "0.158571702", "Cultivar 1": "0", "Ash": "1.328654814", "Proline": "-1.21613669", "Alcalinity of ash": "2.103513241", "Alcohol": "-0.717217046"}, 
    {"OD280/OD315 of diluted wines": "0.689716458", "Hue": "-0.997897726", "Nonflavanoid phenols": "-0.498406993", "Malic acid": "3.109192467", "Total phenols": "0.520577716", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.623192602", "Color intensity": "-1.063295898", "Proanthocyanins": "0.734300428", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "-0.864549732", "Proline": "-1.168369284", "Alcalinity of ash": "0.602088279", "Alcohol": "0.060999882"}, 
    {"OD280/OD315 of diluted wines": "1.452435578", "Hue": "-0.910150952", "Nonflavanoid phenols": "-1.223609539", "Malic acid": "1.77167438", "Total phenols": "0.905137288", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "1.004699956", "Color intensity": "-0.976781902", "Proanthocyanins": "2.311176145", "Magnesium": "-1.245695111", "Cultivar 1": "0", "Ash": "0.085838905", "Proline": "-1.168369284", "Alcalinity of ash": "0.451945783", "Alcohol": "-1.396612776"}, 
    {"OD280/OD315 of diluted wines": "0.943956165", "Hue": "-0.427543693", "Nonflavanoid phenols": "0.065639431", "Malic acid": "-0.158301383", "Total phenols": "0.488531085", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.623192602", "Color intensity": "-0.994084701", "Proanthocyanins": "-0.422075098", "Magnesium": "-1.035055089", "Cultivar 1": "0", "Ash": "-0.718336096", "Proline": "-1.174738272", "Alcalinity of ash": "0.451945783", "Alcohol": "-1.149559783"}, 
    {"OD280/OD315 of diluted wines": "0.322481326", "Hue": "-1.173391275", "Nonflavanoid phenols": "0.226795553", "Malic acid": "-0.723829165", "Total phenols": "0.712857502", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "1.125175963", "Color intensity": "-0.483652121", "Proanthocyanins": "0.313800236", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "-0.279695187", "Proline": "-1.257535109", "Alcalinity of ash": "0.602088279", "Alcohol": "-0.704864396"}, 
    {"OD280/OD315 of diluted wines": "-0.2424958", "Hue": "0.055063566", "Nonflavanoid phenols": "1.757778705", "Malic acid": "-0.185231277", "Total phenols": "-0.264564743", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.211566246", "Color intensity": "-0.890267905", "Proanthocyanins": "0.296279395", "Magnesium": "-0.543561704", "Cultivar 1": "0", "Ash": "1.51142186", "Proline": "-0.894502823", "Alcalinity of ash": "2.704083226", "Alcohol": "-1.495433974"}, 
    {"OD280/OD315 of diluted wines": "0.237734757", "Hue": "-0.295923532", "Nonflavanoid phenols": "0.307373613", "Malic acid": "-0.63406285", "Total phenols": "-0.120354903", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "0.422399258", "Color intensity": "-1.27092949", "Proanthocyanins": "0.541571173", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-0.243141777", "Proline": "-1.289380046", "Alcalinity of ash": "1.502943256", "Alcohol": "-0.778980294"}, 
    {"OD280/OD315 of diluted wines": "-0.058878234", "Hue": "-0.734657403", "Nonflavanoid phenols": "0.468529735", "Malic acid": "1.762697749", "Total phenols": "-0.312634689", "Cultivar 2": "1", "Cultivar 3": "0", "Flavanoids": "-0.280377448", "Color intensity": "-1.063295898", "Proanthocyanins": "-0.422075098", "Magnesium": "-1.386121792", "Cultivar 1": "0", "Ash": "0.049285495", "Proline": "-0.531470536", "Alcalinity of ash": "0.752230776", "Alcohol": "-1.186617732"}, 
    {"OD280/OD315 of diluted wines": "-1.866805038", "Hue": "-0.866277565", "Nonflavanoid phenols": "-1.223609539", "Malic acid": "-0.885408531", "Total phenols": "-1.258010303", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.782360809", "Color intensity": "-0.414440924", "Proanthocyanins": "-1.140429592", "Magnesium": "1.562838514", "Cultivar 1": "0", "Ash": "-0.170034959", "Proline": "-0.37224585", "Alcalinity of ash": "-0.448909194", "Alcohol": "-0.173700461"}, 
    {"OD280/OD315 of diluted wines": "-1.683187472", "Hue": "-0.954024339", "Nonflavanoid phenols": "-0.981875357", "Malic acid": "0.586759028", "Total phenols": "-1.594499928", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.812479811", "Color intensity": "0.147900054", "Proanthocyanins": "-1.333158846", "Magnesium": "0.298998383", "Cultivar 1": "0", "Ash": "0.122392314", "Proline": "-0.690695223", "Alcalinity of ash": "0.151660791", "Alcohol": "-0.148995162"}, 
    {"OD280/OD315 of diluted wines": "-1.767934041", "Hue": "-1.305011436", "Nonflavanoid phenols": "-0.740141175", "Malic acid": "-0.023651911", "Total phenols": "-1.83484966", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.942995485", "Color intensity": "0.277671049", "Proanthocyanins": "-1.333158846", "Magnesium": "-0.122281661", "Cultivar 1": "0", "Ash": "0.122392314", "Proline": "-0.595160411", "Alcalinity of ash": "1.35280076", "Alcohol": "-0.235463709"}, 
    {"OD280/OD315 of diluted wines": "-1.866805038", "Hue": "-0.77853079", "Nonflavanoid phenols": "-1.545921781", "Malic acid": "1.08945039", "Total phenols": "-0.953567308", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.832559145", "Color intensity": "-0.025127939", "Proanthocyanins": "-1.315638005", "Magnesium": "0.439425064", "Cultivar 1": "0", "Ash": "-0.023821323", "Proline": "-0.467780662", "Alcalinity of ash": "0.602088279", "Alcohol": "-0.371342855"}, 
    {"OD280/OD315 of diluted wines": "-1.556067618", "Hue": "-0.910150952", "Nonflavanoid phenols": "1.918934826", "Malic acid": "-0.984151477", "Total phenols": "-0.472867844", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.455018513", "Color intensity": "0.169528553", "Proanthocyanins": "-0.597283511", "Magnesium": "-1.035055089", "Cultivar 1": "0", "Ash": "-0.425908823", "Proline": "-0.308555975", "Alcalinity of ash": "-0.59905169", "Alcohol": "-0.606043199"}, 
    {"OD280/OD315 of diluted wines": "-1.457196621", "Hue": "-0.997897726", "Nonflavanoid phenols": "2.160669008", "Malic acid": "0.110997561", "Total phenols": "-1.081753832", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.374701175", "Color intensity": "0.883269025", "Proanthocyanins": "-1.140429592", "Magnesium": "-0.403135023", "Cultivar 1": "0", "Ash": "-0.608675869", "Proline": "-0.165253757", "Alcalinity of ash": "-0.298766697", "Alcohol": "-0.494869352"}, 
    {"OD280/OD315 of diluted wines": "-1.895053894", "Hue": "-0.910150952", "Nonflavanoid phenols": "1.354888402", "Malic acid": "2.13971627", "Total phenols": "-1.466313404", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.565454853", "Color intensity": "-0.52258342", "Proanthocyanins": "-1.38572137", "Magnesium": "-0.754201726", "Cultivar 1": "0", "Ash": "0.634140041", "Proline": "-0.085641413", "Alcalinity of ash": "0.451945783", "Alcohol": "-0.92721209"}, 
    {"OD280/OD315 of diluted wines": "-1.301827912", "Hue": "-0.603037242", "Nonflavanoid phenols": "2.160669008", "Malic acid": "2.848870155", "Total phenols": "-0.809357469", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.434939179", "Color intensity": "-0.025127939", "Proanthocyanins": "-0.860096131", "Magnesium": "-0.262708342", "Cultivar 1": "0", "Ash": "0.999674132", "Proline": "-0.738462629", "Alcalinity of ash": "1.653085752", "Alcohol": "-0.5813379"}, 
    {"OD280/OD315 of diluted wines": "-1.118210346", "Hue": "-0.646910629", "Nonflavanoid phenols": "1.757778705", "Malic acid": "1.125356915", "Total phenols": "-1.081753832", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.555415186", "Color intensity": "0.277671049", "Proanthocyanins": "-1.24555464", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-0.645229278", "Proline": "-0.531470536", "Alcalinity of ash": "0.001518295", "Alcohol": "0.604516467"}, 
    {"OD280/OD315 of diluted wines": "-0.652104217", "Hue": "-0.295923532", "Nonflavanoid phenols": "1.354888402", "Malic acid": "0.559829134", "Total phenols": "0.039878251", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.434939179", "Color intensity": "-0.059733538", "Proanthocyanins": "-1.368200529", "Magnesium": "0.088358361", "Cultivar 1": "0", "Ash": "0.890013905", "Proline": "-0.499625599", "Alcalinity of ash": "1.35280076", "Alcohol": "-0.19840576"}, 
    {"OD280/OD315 of diluted wines": "-0.426113366", "Hue": "-0.822404177", "Nonflavanoid phenols": "1.354888402", "Malic acid": "0.425179662", "Total phenols": "-1.209940356", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.535335851", "Color intensity": "-0.198155932", "Proanthocyanins": "-1.473325576", "Magnesium": "-0.262708342", "Cultivar 1": "0", "Ash": "1.218994587", "Proline": "-0.467780662", "Alcalinity of ash": "0.451945783", "Alcohol": "-0.087231914"}, 
    {"OD280/OD315 of diluted wines": "-0.200122516", "Hue": "-1.129517888", "Nonflavanoid phenols": "0.065639431", "Malic acid": "0.200763875", "Total phenols": "-1.434266773", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.535335851", "Color intensity": "0.234414051", "Proanthocyanins": "-1.666054831", "Magnesium": "-0.754201726", "Cultivar 1": "0", "Ash": "-0.060374732", "Proline": "0.105428211", "Alcalinity of ash": "0.151660791", "Alcohol": "0.443932021"}, 
    {"OD280/OD315 of diluted wines": "-0.77922407", "Hue": "-0.295923532", "Nonflavanoid phenols": "1.11315422", "Malic acid": "0.748338394", "Total phenols": "-1.193917041", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.515256517", "Color intensity": "-0.306298428", "Proanthocyanins": "-1.823742402", "Magnesium": "-0.192495001", "Cultivar 1": "0", "Ash": "1.292101405", "Proline": "-0.722540161", "Alcalinity of ash": "1.202658264", "Alcohol": "0.641574416"}, 
    {"OD280/OD315 of diluted wines": "-0.793348498", "Hue": "-0.208176757", "Nonflavanoid phenols": "0.871420038", "Malic acid": "2.346178793", "Total phenols": "-0.472867844", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.234145834", "Color intensity": "-0.284669929", "Proanthocyanins": "-1.000262861", "Magnesium": "-0.543561704", "Cultivar 1": "0", "Ash": "-0.060374732", "Proline": "-0.627005349", "Alcalinity of ash": "0.151660791", "Alcohol": "0.765100912"}, 
    {"OD280/OD315 of diluted wines": "-0.863970639", "Hue": "-1.348884823", "Nonflavanoid phenols": "-0.578985054", "Malic acid": "1.385679228", "Total phenols": "-1.466313404", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.254225169", "Color intensity": "1.363421706", "Proanthocyanins": "-0.790012766", "Magnesium": "0.860705108", "Cultivar 1": "0", "Ash": "-0.608675869", "Proline": "0.344265242", "Alcalinity of ash": "-0.298766697", "Alcohol": "-0.92721209"}, 
    {"OD280/OD315 of diluted wines": "-1.31595234", "Hue": "-1.568251759", "Nonflavanoid phenols": "0.549107795", "Malic acid": "1.107403652", "Total phenols": "-1.274033618", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.485137515", "Color intensity": "-0.457697922", "Proanthocyanins": "-0.509679305", "Magnesium": "0.158571702", "Cultivar 1": "0", "Ash": "-0.791442914", "Proline": "0.264652898", "Alcalinity of ash": "0.451945783", "Alcohol": "0.196879028"}, 
    {"OD280/OD315 of diluted wines": "-1.810307325", "Hue": "-1.655998533", "Nonflavanoid phenols": "0.307373613", "Malic acid": "2.426968477", "Total phenols": "-2.107246023", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.695970527", "Color intensity": "-0.068384938", "Proanthocyanins": "-1.595971466", "Magnesium": "-1.386121792", "Cultivar 1": "0", "Ash": "-0.499015641", "Proline": "-1.056912003", "Alcalinity of ash": "0.151660791", "Alcohol": "1.086269803"}, 
    {"OD280/OD315 of diluted wines": "-1.061712633", "Hue": "-1.831492082", "Nonflavanoid phenols": "0.871420038", "Malic acid": "2.040973324", "Total phenols": "-0.953567308", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.384740843", "Color intensity": "1.121182516", "Proanthocyanins": "-1.280596322", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "0.414819587", "Proline": "-0.388168318", "Alcalinity of ash": "0.602088279", "Alcohol": "-0.161347811"}, 
    {"OD280/OD315 of diluted wines": "-1.400698909", "Hue": "-1.787618695", "Nonflavanoid phenols": "0.710263917", "Malic acid": "0.811174814", "Total phenols": "-0.585031052", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.274304503", "Color intensity": "1.454261402", "Proanthocyanins": "-0.597283511", "Magnesium": "-0.543561704", "Cultivar 1": "0", "Ash": "0.049285495", "Proline": "-0.308555975", "Alcalinity of ash": "0.602088279", "Alcohol": "0.394521423"}, 
    {"OD280/OD315 of diluted wines": "-1.810307325", "Hue": "-1.699871921", "Nonflavanoid phenols": "-0.17609475", "Malic acid": "1.403632491", "Total phenols": "-1.418243457", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.641805468", "Color intensity": "1.878179986", "Proanthocyanins": "-0.790012766", "Magnesium": "0.930918449", "Cultivar 1": "0", "Ash": "-0.023821323", "Proline": "-0.627005349", "Alcalinity of ash": "0.602088279", "Alcohol": "0.098057831"}, 
    {"OD280/OD315 of diluted wines": "-1.85268061", "Hue": "-1.612125146", "Nonflavanoid phenols": "-1.143031478", "Malic acid": "0.703455237", "Total phenols": "-1.434266773", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.461091458", "Color intensity": "1.532123999", "Proanthocyanins": "-0.597283511", "Magnesium": "1.633051855", "Cultivar 1": "0", "Ash": "0.926567314", "Proline": "-0.786230036", "Alcalinity of ash": "1.35280076", "Alcohol": "0.616869117"}, 
    {"OD280/OD315 of diluted wines": "-1.612565331", "Hue": "-2.094732405", "Nonflavanoid phenols": "-0.981875357", "Malic acid": "0.299506821", "Total phenols": "-1.306080249", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.67192447", "Color intensity": "2.483777962", "Proanthocyanins": "-0.57976267", "Magnesium": "0.860705108", "Cultivar 1": "0", "Ash": "0.414819587", "Proline": "-0.84991991", "Alcalinity of ash": "0.752230776", "Alcohol": "-0.260169009"}, 
    {"OD280/OD315 of diluted wines": "-1.810307325", "Hue": "-1.524378372", "Nonflavanoid phenols": "-0.820719236", "Malic acid": "-0.391693801", "Total phenols": "-0.152401534", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.752241808", "Color intensity": "0.883269025", "Proanthocyanins": "-0.054137431", "Magnesium": "1.141558471", "Cultivar 1": "0", "Ash": "1.401761633", "Proline": "-1.025067066", "Alcalinity of ash": "1.803228249", "Alcohol": "0.13511578"}, 
    {"OD280/OD315 of diluted wines": "-1.556067618", "Hue": "-1.743745308", "Nonflavanoid phenols": "1.999512887", "Malic acid": "0.865034603", "Total phenols": "-0.793334154", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.204026833", "Color intensity": "2.362658367", "Proanthocyanins": "0.489008649", "Magnesium": "-0.122281661", "Cultivar 1": "0", "Ash": "-0.316248596", "Proline": "-0.228943631", "Alcalinity of ash": "-0.298766697", "Alcohol": "0.283347576"}, 
    {"OD280/OD315 of diluted wines": "-1.499569906", "Hue": "-1.655998533", "Nonflavanoid phenols": "1.354888402", "Malic acid": "-0.939268319", "Total phenols": "-1.306080249", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.455018513", "Color intensity": "1.099554016", "Proanthocyanins": "-0.334470892", "Magnesium": "0.228785042", "Cultivar 1": "0", "Ash": "-0.97420996", "Proline": "-0.340400912", "Alcalinity of ash": "0.151660791", "Alcohol": "-0.519574651"}, 
    {"OD280/OD315 of diluted wines": "-1.598440903", "Hue": "-1.568251759", "Nonflavanoid phenols": "1.999512887", "Malic acid": "2.561617948", "Total phenols": "-0.889474047", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.404820177", "Color intensity": "1.229325011", "Proanthocyanins": "-0.071658272", "Magnesium": "-0.473348364", "Cultivar 1": "0", "Ash": "-0.170034959", "Proline": "-0.069718944", "Alcalinity of ash": "0.752230776", "Alcohol": "0.209231678"}, 
    {"OD280/OD315 of diluted wines": "-1.372450052", "Hue": "-1.699871921", "Nonflavanoid phenols": "0.951998098", "Malic acid": "1.601118383", "Total phenols": "-0.793334154", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.204026833", "Color intensity": "1.709477692", "Proanthocyanins": "-0.054137431", "Magnesium": "-0.754201726", "Cultivar 1": "0", "Ash": "0.049285495", "Proline": "-0.84991991", "Alcalinity of ash": "0.001518295", "Alcohol": "1.036859205"}, 
    {"OD280/OD315 of diluted wines": "-1.245330199", "Hue": "-1.261138049", "Nonflavanoid phenols": "2.160669008", "Malic acid": "0.622665554", "Total phenols": "-0.633100999", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.455018513", "Color intensity": "1.056297018", "Proanthocyanins": "-0.790012766", "Magnesium": "-0.192495001", "Cultivar 1": "0", "Ash": "0.999674132", "Proline": "0.423877585", "Alcalinity of ash": "2.253655737", "Alcohol": "-0.680159097"}, 
    {"OD280/OD315 of diluted wines": "-0.920468352", "Hue": "-1.699871921", "Nonflavanoid phenols": "1.354888402", "Malic acid": "-0.589179693", "Total phenols": "0.808997395", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.722122806", "Color intensity": "3.435431924", "Proanthocyanins": "1.943238477", "Magnesium": "-0.122281661", "Cultivar 1": "0", "Ash": "1.218994587", "Proline": "-0.276711037", "Alcalinity of ash": "1.653085752", "Alcohol": "1.654491687"}, 
    {"OD280/OD315 of diluted wines": "-1.174708058", "Hue": "-1.699871921", "Nonflavanoid phenols": "1.274310341", "Malic acid": "-0.598156324", "Total phenols": "0.488531085", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-0.932955818", "Color intensity": "2.894719446", "Proanthocyanins": "1.224883984", "Magnesium": "-0.754201726", "Cultivar 1": "0", "Ash": "0.999674132", "Proline": "-0.404090787", "Alcalinity of ash": "0.902373272", "Alcohol": "0.592163817"}, 
    {"OD280/OD315 of diluted wines": "-1.457196621", "Hue": "-1.743745308", "Nonflavanoid phenols": "1.11315422", "Malic acid": "1.34079607", "Total phenols": "0.00783162", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.113669828", "Color intensity": "1.121182516", "Proanthocyanins": "-0.965221179", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "0.049285495", "Proline": "-0.722540161", "Alcalinity of ash": "0.451945783", "Alcohol": "-0.791332944"}, 
    {"OD280/OD315 of diluted wines": "-1.118210346", "Hue": "0.011190179", "Nonflavanoid phenols": "1.11315422", "Malic acid": "0.829128077", "Total phenols": "-0.745264207", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.475097848", "Color intensity": "0.355533646", "Proanthocyanins": "-1.38572137", "Magnesium": "0.509638405", "Cultivar 1": "0", "Ash": "0.634140041", "Proline": "-0.213021163", "Alcalinity of ash": "0.151660791", "Alcohol": "0.85156946"}, 
    {"OD280/OD315 of diluted wines": "-0.708601929", "Hue": "-0.383670306", "Nonflavanoid phenols": "1.918934826", "Malic acid": "0.838104709", "Total phenols": "-1.033683886", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.434939179", "Color intensity": "0.225762651", "Proanthocyanins": "-1.105387909", "Magnesium": "0.439425064", "Cultivar 1": "0", "Ash": "0.780353678", "Proline": "-0.563315474", "Alcalinity of ash": "0.752230776", "Alcohol": "-0.186053111"}, 
    {"OD280/OD315 of diluted wines": "-1.217081343", "Hue": "-1.217264662", "Nonflavanoid phenols": "0.307373613", "Malic acid": "0.999684075", "Total phenols": "-1.450290088", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.334542507", "Color intensity": "0.095991656", "Proanthocyanins": "-1.140429592", "Magnesium": "0.439425064", "Cultivar 1": "0", "Ash": "-0.060374732", "Proline": "-0.228943631", "Alcalinity of ash": "-0.298766697", "Alcohol": "-0.050173965"}, 
    {"OD280/OD315 of diluted wines": "-1.31595234", "Hue": "-1.129517888", "Nonflavanoid phenols": "0.387951674", "Malic acid": "0.380296505", "Total phenols": "-1.51438335", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.354621841", "Color intensity": "1.956042583", "Proanthocyanins": "-0.98274202", "Magnesium": "-0.683988386", "Cultivar 1": "0", "Ash": "-0.243141777", "Proline": "-0.420013256", "Alcalinity of ash": "0.752230776", "Alcohol": "0.962743307"}, 
    {"OD280/OD315 of diluted wines": "-1.217081343", "Hue": "-0.77853079", "Nonflavanoid phenols": "1.274310341", "Malic acid": "1.816557538", "Total phenols": "-1.626546559", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.565454853", "Color intensity": "0.675635433", "Proanthocyanins": "-0.772491924", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-0.389355414", "Proline": "-0.722540161", "Alcalinity of ash": "0.902373272", "Alcohol": "0.900980058"}, 
    {"OD280/OD315 of diluted wines": "-1.485445478", "Hue": "-0.47141708", "Nonflavanoid phenols": "0.549107795", "Malic acid": "1.224099861", "Total phenols": "-0.953567308", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.113669828", "Color intensity": "2.431869564", "Proanthocyanins": "-0.229345844", "Magnesium": "0.790491768", "Cultivar 1": "0", "Ash": "0.853460496", "Proline": "-0.165253757", "Alcalinity of ash": "1.052515768", "Alcohol": "0.555105868"}, 
    {"OD280/OD315 of diluted wines": "-1.217081343", "Hue": "-1.041771113", "Nonflavanoid phenols": "0.307373613", "Malic acid": "0.927871023", "Total phenols": "-1.306080249", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.374701175", "Color intensity": "2.250190171", "Proanthocyanins": "-1.087867068", "Magnesium": "-0.824415067", "Cultivar 1": "0", "Ash": "-0.243141777", "Proline": "-0.197098694", "Alcalinity of ash": "0.001518295", "Alcohol": "-0.22311106"}, 
    {"OD280/OD315 of diluted wines": "-1.146459202", "Hue": "-0.954024339", "Nonflavanoid phenols": "0.226795553", "Malic acid": "0.218717138", "Total phenols": "-1.193917041", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.193987165", "Color intensity": "1.558078198", "Proanthocyanins": "-0.089179114", "Magnesium": "0.369211724", "Cultivar 1": "0", "Ash": "1.182441178", "Proline": "0.009893399", "Alcalinity of ash": "1.502943256", "Alcohol": "0.715690314"}, 
    {"OD280/OD315 of diluted wines": "-0.976966064", "Hue": "-1.261138049", "Nonflavanoid phenols": "-0.740141175", "Malic acid": "2.031996692", "Total phenols": "-0.504914475", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.073511159", "Color intensity": "1.488867001", "Proanthocyanins": "-0.84257529", "Magnesium": "0.860705108", "Cultivar 1": "0", "Ash": "1.803849133", "Proline": "-0.37224585", "Alcalinity of ash": "1.653085752", "Alcohol": "0.49334262"}, 
    {"OD280/OD315 of diluted wines": "-1.104085918", "Hue": "-1.305011436", "Nonflavanoid phenols": "0.307373613", "Malic acid": "0.622665554", "Total phenols": "-1.674616505", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.545375518", "Color intensity": "0.191157052", "Proanthocyanins": "-1.508367259", "Magnesium": "-0.262708342", "Cultivar 1": "0", "Ash": "-0.170034959", "Proline": "-0.754385098", "Alcalinity of ash": "-0.148624201", "Alcohol": "-0.988975338"}, 
    {"OD280/OD315 of diluted wines": "-1.386574481", "Hue": "-1.699871921", "Nonflavanoid phenols": "0.951998098", "Malic acid": "0.048161141", "Total phenols": "-1.450290088", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.525296184", "Color intensity": "2.094464545", "Proanthocyanins": "-1.666054831", "Magnesium": "-0.964841748", "Cultivar 1": "0", "Ash": "-0.316248596", "Proline": "-0.881764848", "Alcalinity of ash": "0.001518295", "Alcohol": "-0.284874308"}, 
    {"OD280/OD315 of diluted wines": "-1.273579055", "Hue": "-1.480504985", "Nonflavanoid phenols": "0.629685856", "Malic acid": "0.155880718", "Total phenols": "-0.985613939", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.334542507", "Color intensity": "2.007950981", "Proanthocyanins": "-0.614804353", "Magnesium": "-0.613775045", "Cultivar 1": "0", "Ash": "0.414819587", "Proline": "-0.276711037", "Alcalinity of ash": "0.151660791", "Alcohol": "1.432143993"}, 
    {"OD280/OD315 of diluted wines": "-1.231205771", "Hue": "-1.392758211", "Nonflavanoid phenols": "1.274310341", "Malic acid": "2.974542995", "Total phenols": "-0.985613939", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.424899512", "Color intensity": "1.142811015", "Proanthocyanins": "-0.930179496", "Magnesium": "-0.332921683", "Cultivar 1": "0", "Ash": "0.305159359", "Proline": "-0.021951538", "Alcalinity of ash": "0.301803287", "Alcohol": "0.876274759"}, 
    {"OD280/OD315 of diluted wines": "-1.485445478", "Hue": "-1.129517888", "Nonflavanoid phenols": "0.549107795", "Malic acid": "1.412609122", "Total phenols": "-0.793334154", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.28434417", "Color intensity": "0.969783022", "Proanthocyanins": "-0.316950051", "Magnesium": "0.158571702", "Cultivar 1": "0", "Ash": "0.414819587", "Proline": "0.009893399", "Alcalinity of ash": "1.052515768", "Alcohol": "0.49334262"}, 
    {"OD280/OD315 of diluted wines": "-1.485445478", "Hue": "-1.612125146", "Nonflavanoid phenols": "0.549107795", "Malic acid": "1.744744486", "Total phenols": "-1.129823779", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.344582174", "Color intensity": "2.224235972", "Proanthocyanins": "-0.422075098", "Magnesium": "1.422411833", "Cultivar 1": "0", "Ash": "-0.389355414", "Proline": "0.280575367", "Alcalinity of ash": "0.151660791", "Alcohol": "0.332758175"}, 
    {"OD280/OD315 of diluted wines": "-1.400698909", "Hue": "-1.568251759", "Nonflavanoid phenols": "1.354888402", "Malic acid": "0.22769377", "Total phenols": "-1.033683886", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.354621841", "Color intensity": "1.834922987", "Proanthocyanins": "-0.229345844", "Magnesium": "1.422411833", "Cultivar 1": "0", "Ash": "0.012732086", "Proline": "0.296497836", "Alcalinity of ash": "0.151660791", "Alcohol": "0.209231678"}
  ],
  predict: {
    record: {"OD280/OD315 of diluted wines": "-1.428947765", "Hue": "-1.524378372", "Nonflavanoid phenols": "1.596622583", "Malic acid": "1.58316512", "Total phenols": "-0.392751267", "Cultivar 2": "0", "Cultivar 3": "1", "Flavanoids": "-1.274304503", "Color intensity": "1.791665989", "Proanthocyanins": "-0.422075098", "Magnesium": "-0.262708342", "Cultivar 1": "0", "Ash": "1.365208223", "Proline": "-0.595160411", "Alcalinity of ash": "1.502943256", "Alcohol": "1.395086044"}
    rec: [-1.428947765, -1.524378372, 1.596622583, 1.58316512, -0.392751267, -1.274304503, 1.791665989, -0.422075098, -0.262708342, 1.365208223, -0.595160411, 1.502943256, 1.395086044],
    res: "Cultivar 3"
  }
}



# TODO this is only 100 wine rows, have to sign up to get the full 178, and it ony contains mostly cultivar 1 and a few cultivar 2.
# I made up the prediction record above. Should get the full 178 rows, use 1 as a predictor, then use 177 as the wine dataset
###
Alcohol
Malic acid
Ash
Alcalinity of ash
Magnesium
Total phenols
Flavanoids
Nonflavanoid phenols
Proanthocyanins
Color intensity
Hue
OD280/OD315 of diluted wines
Proline
Cultivar 1
Cultivar 2
Cultivar 3
1.518612541	-0.562249798	0.232052541	-1.169593175	1.913905218	0.808997395	1.034818958	-0.659563114	1.224883984	0.25171685	0.362177276	1.847919567	1.013008927	1	0	0
0.246289627	-0.499413378	-0.827996323	-2.490847141	0.018145021	0.568647662	0.733628941	-0.820719236	-0.544720987	-0.293321329	0.406050663	1.113449303	0.965241521	1	0	0
0.196879028	0.021231246	1.10933436	-0.268738198	0.088358361	0.808997395	1.215532968	-0.498406993	2.135967732	0.269019649	0.318303889	0.788587455	1.395148175	1	0	0
1.691549636	-0.346810643	0.487926405	-0.809251184	0.930918449	2.49144552	1.466524649	-0.981875357	1.03215473	1.186068013	-0.427543693	1.184071443	2.334573828	1	0	0
0.295700226	0.22769377	1.840402542	0.451945783	1.281985152	0.808997395	0.663351271	0.226795553	0.401404443	-0.319275528	0.362177276	0.449601179	-0.037874007	1	0	0
1.481554592	-0.517366641	0.305159359	-1.289707172	0.860705108	1.562093222	1.366127977	-0.17609475	0.664217062	0.731869531	0.406050663	0.336605754	2.239039016	1	0	0
1.716254935	-0.418623695	0.305159359	-1.469878167	-0.262708342	0.32829793	0.492676928	-0.498406993	0.681737904	0.083014556	0.274430501	1.367689009	1.729520018	1	0	0
1.308617497	-0.167278014	0.890013905	-0.56902319	1.492625174	0.488531085	0.482637261	-0.417828932	-0.597283511	-0.00349944	0.44992405	1.367689009	1.745442487	1	0	0
2.25977152	-0.625086219	-0.718336096	-1.650049163	-0.192495001	0.808997395	0.95450162	-0.578985054	0.681737904	0.061386057	0.537670824	0.336605754	0.949319052	1	0	0
1.061564504	-0.885408531	-0.352802005	-1.049479178	-0.122281661	1.097417073	1.125175963	-1.143031478	0.453966967	0.935177423	0.230557114	1.325315725	0.949319052	1	0	0
1.358028096	-0.158301383	-0.243141777	-0.448909194	0.369211724	1.049347127	1.295850306	-1.143031478	1.382571556	0.299299548	1.283518406	0.788587455	2.43010864	1	0	0
1.382733395	-0.768712322	-0.170034959	-0.809251184	-0.332921683	-0.152401534	0.402319923	-0.820719236	-0.03661659	-0.025127939	0.932531309	0.29423247	1.697675081	1	0	0
0.925685358	-0.544296535	0.158945723	-1.049479178	-0.754201726	0.488531085	0.733628941	-0.578985054	0.383883602	0.234414051	0.844784535	0.407227895	1.82505483	1	0	0
2.160950323	-0.544296535	0.085838905	-2.430790143	-0.613775045	1.289696859	1.667317993	0.549107795	2.135967732	0.147900054	1.283518406	0.167112616	1.283690895	1	0	0
1.703902286	-0.418623695	0.049285495	-2.250619147	0.158571702	1.610163169	1.617119657	-0.578985054	2.398780351	1.056297018	1.06415147	0.548472176	2.547934909	1	0	0
0.777453562	-0.472483484	1.218994587	-0.689137187	0.860705108	0.889113972	0.88422395	-0.498406993	-0.229345844	0.969783022	1.415138568	0.378979039	1.793209893	1	0	0
1.605081089	-0.373740538	1.292101405	0.151660791	1.422411833	0.808997395	1.115136296	-0.256672811	0.664217062	0.49395604	0.493797437	0.054117191	1.697675081	1	0	0
1.024506555	-0.687922639	0.926567314	0.151660791	1.07134513	1.049347127	1.376167644	0.307373613	0.22619603	0.666984033	0.75703776	-0.058878234	1.22000102	1	0	0
1.469201942	-0.669969376	0.414819587	-0.899336682	0.579851746	1.610163169	1.908270007	-0.337250872	0.471487808	1.575380998	1.195771632	0.29423247	2.971472576	1	0	0
0.789806212	0.685501974	0.707246859	-1.289707172	1.141558471	0.64876424	1.004699956	-1.545921781	0.121070982	0.018129059	0.011190179	1.05695159	0.312420304	1	0	0
1.308617497	-0.63406285	-0.316248596	-1.049479178	1.843691877	1.129463704	1.145255298	-0.981875357	0.891987999	0.25604255	0.581544212	1.551306575	0.105428211	1	0	0
-0.087231914	1.313866176	1.036227541	-0.268738198	0.158571702	0.184088091	0.382240589	-0.901297296	0.681737904	-0.241412931	0.318303889	1.28294244	0.073583274	1	0	0
0.876274759	-0.427600326	-0.023821323	-0.869308183	0.088358361	0.5045544	0.854104948	-0.740141175	0.173633506	-0.544211919	0.669290986	1.960914992	0.917474115	1	0	0
-0.186053111	-0.660992744	0.561033223	-0.508966192	-0.332921683	0.296251299	0.34208192	-0.820719236	-0.229345844	-0.487977821	0.581544212	1.43831115	0.85378424	1	0	0
0.616869117	-0.472483484	0.890013905	0.151660791	-0.262708342	0.376367877	0.583033933	-0.659563114	0.121070982	-0.665331514	0.713164373	1.706675285	0.312420304	1	0	0
0.060999882	-0.257044329	3.119771861	1.653085752	1.703265196	0.536601031	0.653311604	0.871420038	0.576612856	-0.639377315	0.75703776	0.830960739	0.264652898	1	0	0
0.48098997	-0.50839001	0.926567314	-1.019450679	-0.473348364	0.889113972	0.914342951	-0.17609475	-0.246866685	-0.111641936	-0.16430337	0.859209596	1.426993113	1	0	0
0.369816124	-0.553273167	-0.827996323	-0.749194186	-0.403135023	0.168064775	0.16136791	-0.740141175	-0.422075098	-0.479326421	0.274430501	0.223610329	1.713597549	1	0	0
1.073917154	-0.391693801	1.584528678	-0.028510204	0.509638405	1.049347127	0.944461953	0.065639431	0.296279395	-0.241412931	1.283518406	1.113449303	0.535334866	1	0	0
1.259206898	-0.589179693	-0.572122459	-1.049479178	-0.262708342	0.568647662	0.301923251	-0.820719236	0.681737904	-0.154898934	0.362177276	1.381813437	0.917474115	1	0	0
0.900980058	-0.750759059	1.218994587	0.902373272	0.088358361	1.129463704	1.225572635	-0.578985054	1.382571556	0.277671049	1.020278083	0.13886376	1.713597549	1	0	0
0.715690314	-0.607132956	-0.023821323	-0.118595702	0.439425064	0.905137288	1.165334632	-1.143031478	0.62917538	0.796755028	0.581544212	0.378979039	2.446031109	1	0	0
0.83921681	-0.454530221	-0.023821323	-0.689137187	0.298998383	0.200111406	0.663351271	0.468529735	0.664217062	-0.52690912	1.195771632	0.36485461	0.774171896	1	0	0
0.938038007	-0.723829165	1.218994587	0.001518295	2.264971921	1.049347127	0.713549607	1.11315422	-0.422075098	0.147900054	1.283518406	0.548472176	1.554372862	1	0	0
0.629221766	-0.481460115	1.036227541	-0.148624201	0.720278427	0.087948198	0.502716595	-0.578985054	-0.089179114	-0.371183926	0.625417599	0.36485461	1.108543739	1	0	0
0.592163817	-0.472483484	0.158945723	0.301803287	0.018145021	0.64876424	0.95450162	-0.820719236	0.471487808	0.018129059	0.362177276	1.2123203	0.551257335	1	0	0
0.345110824	-0.625086219	1.730742315	-1.199621674	0.720278427	0.488531085	0.653311604	-0.17609475	-0.404554257	-0.198155932	0.581544212	0.237734757	0.423877585	1	0	0
0.060999882	-0.616109587	0.67069345	-0.448909194	-0.122281661	0.248181353	0.402319923	-0.578985054	-0.264387527	-0.349555426	0.713164373	-0.143624803	1.140388676	1	0	0
0.085705182	-0.750759059	-0.97420996	-1.199621674	-0.122281661	0.168064775	0.613152935	-0.659563114	-0.387033416	-0.587468917	0.976404696	0.110614904	0.869706709	1	0	0
1.506259891	1.484422174	0.524479814	-1.890277157	1.984118558	1.129463704	1.014739624	-1.304187599	0.856946317	0.018129059	-0.295923532	1.297066869	0.041738336	1	0	0
0.690985014	-0.562249798	-0.206588368	-0.98942218	1.211771811	1.369813437	1.265731304	-0.17609475	1.312488191	0.463676141	-0.032683209	1.085200446	0.153195617	1	0	0
0.50569527	1.349772702	-0.901103141	-0.2086812	-0.683988386	0.248181353	0.653311604	-0.740141175	-0.194304161	-0.336578327	-0.208176757	0.548472176	0.917474115	1	0	0
1.086269803	-0.400670432	0.816907087	-1.34976417	0.088358361	1.530046591	1.536802319	-1.545921781	0.191154347	0.160877153	-0.339796919	1.339440153	1.108543739	1	0	0
0.295700226	1.475445542	-0.279695187	-0.59905169	0.228785042	0.552624347	0.603113268	-0.337250872	0.121070982	-0.301972728	-0.603037242	0.548472176	-0.213021163	1	0	0
0.060999882	-0.50839001	-0.97420996	-0.749194186	0.509638405	1.129463704	0.974580955	-0.659563114	0.76934211	-0.00782514	-0.339796919	1.042827162	0.439800054	1	0	0
1.493907242	1.529305331	0.26860595	-0.1786527	0.790491768	0.889113972	0.623192602	-0.498406993	-0.597283511	0.078688857	-0.383670306	1.014578305	1.060776333	1	0	0
1.703902286	1.125356915	-0.316248596	-1.049479178	0.158571702	1.530046591	1.145255298	-0.740141175	1.049675571	-0.068384938	0.362177276	1.169947015	1.013008927	1	0	0
1.110975103	-0.589179693	-0.901103141	-1.049479178	0.088358361	1.289696859	1.366127977	-1.223609539	0.962071365	0.450699042	-0.208176757	1.014578305	0.758249428	1	0	0
1.358028096	-0.283974223	0.122392314	-0.2086812	0.228785042	0.728880817	0.894263617	-0.337250872	1.382571556	0.49395604	0.493797437	0.195361473	0.997086458	1	0	0
1.160385701	-0.544296535	-0.352802005	-0.629080189	0.579851746	0.937183918	1.516722985	-0.337250872	0.856946317	1.661894994	0.713164373	0.689716458	1.633985206	1	0	0
0.060999882	-0.544296535	-1.193530414	-2.13050515	-0.543561704	0.680810871	1.24565197	-1.545921781	2.311176145	0.926526023	0.713164373	0.421352323	1.283690895	1	0	0
1.024506555	-0.616109587	0.853460496	-0.689137187	-0.403135023	0.248181353	0.964541288	-1.143031478	1.224883984	0.234414051	1.239645019	1.071076018	1.649907674	1	0	0
1.012153905	-0.526343273	0.195499132	-1.650049163	0.790491768	2.539515467	1.717516329	-0.337250872	0.489008649	0.861640526	0.230557114	0.915707308	1.411070644	1	0	0
0.950390657	-0.391693801	1.145887769	-0.719165687	1.07134513	1.129463704	0.763747943	0.226795553	0.156112665	0.537213039	0.75703776	0.449601179	2.000201986	1	0	0
0.913332708	-0.598156324	-0.425908823	-0.929365181	1.281985152	0.488531085	0.874184283	-1.223609539	0.050987617	0.342556546	-0.16430337	0.830960739	0.997086458	1	0	0
0.690985014	-0.544296535	0.341712768	0.301803287	1.141558471	1.065370442	0.753708276	-1.304187599	1.505217445	0.515584539	0.098936953	0.590845461	1.188156082	1	0	0
1.506259891	-0.57122643	-0.243141777	-0.95939368	1.281985152	1.449930014	0.974580955	-0.820719236	0.76934211	0.571818637	-0.076556596	0.986329449	0.710482022	1	0	0
0.357463474	-0.32885738	1.145887769	-0.809251184	0.158571702	1.129463704	1.205493301	-0.417828932	0.121070982	0.407442044	0.493797437	0.322481326	1.665830143	1	0	0
0.888627409	-0.813595479	0.487926405	-0.839279684	0.579851746	1.770396324	1.647238659	-1.38476566	0.786862952	0.75349803	-0.295923532	0.36485461	1.713597549	1	0	0
-0.778980294	-1.25345042	-3.679162234	-2.671018136	-0.824415067	-0.504914475	-1.46505818	-0.659563114	-2.051513339	-1.344466387	0.406050663	-1.118210346	-0.722540161	0	1	0
-0.828390893	-1.109824317	-0.316248596	-1.049479178	0.088358361	-0.392751267	-0.942995485	2.160669008	-2.069034181	-0.77347401	1.283518406	-1.330076768	-0.213021163	0	1	0
-0.445458753	-0.876431899	-1.266637233	-0.809251184	0.018145021	-0.440821213	-0.621726134	1.354888402	-1.701096513	0.299299548	0.098936953	-1.443072193	-0.945454722	0	1	0
0.826864161	-0.975174845	-1.632171324	-0.448909194	-0.403135023	-0.312634689	-0.240218779	-0.337250872	-1.508367259	-0.544211919	1.195771632	-0.214246944	-0.37224585	0	1	0
-0.778980294	-1.082894423	-0.754889505	-0.148624201	-0.894628408	1.930629478	1.074977627	-1.38476566	0.489008649	-0.26304143	1.151898245	0.36485461	-1.040989535	0	1	0
-1.026033287	-0.795642216	0.597586632	-0.148624201	0.298998383	-0.649124314	-0.280377448	0.710263917	-0.98274202	-0.911896404	2.160986149	-0.539108791	-1.247981628	0	1	0
-0.778980294	-1.011081371	0.707246859	-0.418880694	-0.122281661	0.200111406	0.623192602	0.065639431	0.856946317	-0.198155932	1.020278083	-0.440237794	-0.21939015	0	1	0
0.13511578	-1.190614	-2.436346324	-1.34976417	-1.526548473	1.097417073	1.155294965	-0.820719236	1.207363143	0.104643056	0.713164373	0.802711883	-0.779861048	0	1	0
-0.778980294	-1.046987897	-1.632171324	0.031546794	-1.526548473	-0.296611374	-0.029385768	-0.740141175	-0.965221179	-0.163550334	0.713164373	1.226444728	-0.754385098	0	1	0
0.419226722	-1.25345042	-0.023821323	-0.749194186	0.720278427	0.376367877	-0.732162473	1.516044523	-2.051513339	-0.816731008	0.274430501	-0.962841636	0.009893399	0	1	0
-0.976622688	-1.029034634	-2.253579279	-0.809251184	3.599025393	-0.713217576	-0.752241808	-1.787655963	1.592821651	-0.955153403	1.415138568	0.647343173	-0.092010401	0	1	0
-0.877801491	-0.652016113	-0.572122459	0.271774788	0.228785042	-1.914966237	-1.013273155	0.065639431	-0.229345844	-0.868639406	-0.225726112	-1.118210346	0.392032648	0	1	0
1.061564504	-0.741782427	1.10933436	1.653085752	-0.964841748	1.049347127	0.834025614	-1.223609539	0.489008649	-0.725891312	1.766125665	0.774463027	-1.072834472	0	1	0
0.604516467	-0.607132956	-0.462462232	1.35280076	-0.894628408	-0.66514763	-0.190020443	-0.740141175	-0.98274202	-0.570166118	0.098936953	0.237734757	-0.87539586	0	1	0
-0.013116016	-0.598156324	0.853460496	3.154510714	2.756465305	1.610163169	0.864144615	-1.223609539	0.646696221	-0.738868411	1.546758729	1.254693584	0.758249428	0	1	0
-1.28543893	-1.118800949	-0.243141777	0.451945783	0.088358361	1.738349693	0.111169574	-1.868234024	0.103550141	-0.799428209	0.14281034	0.732089742	0.442984548	0	1	0
-1.656018419	-0.409647064	-1.632171324	-1.049479178	-0.192495001	-1.097777148	-0.461091458	-0.17609475	-0.772491924	-0.544211919	1.195771632	-0.666228645	-1.015513585	0	1	0
0.036294583	-1.289356946	-2.399792915	-1.049479178	-0.964841748	-0.552984421	0.000733234	-0.981875357	-0.229345844	-0.198155932	1.020278083	-0.185998088	-1.130155359	0	1	0
-1.433670725	0.496992713	-0.499015641	-0.448909194	0.860705108	-0.921520678	-0.712083139	0.549107795	-1.12290875	-1.041667399	0.011190179	-0.129500375	-0.786230036	0	1	0
-0.828390893	-1.208567263	-1.522511096	-1.409821169	2.545825283	-0.633100999	-0.179980776	-0.09551669	2.048363525	-0.717239912	0.44992405	-0.426113366	0.009893399	0	1	0
-0.371342855	1.376702596	0.122392314	1.052515768	0.088358361	0.857067341	0.52279593	0.549107795	0.62917538	-1.076272998	1.020278083	0.732089742	-0.904056304	0	1	0
-1.236028331	-1.271403683	-1.339744051	-0.148624201	-0.964841748	0.200111406	0.23164558	-0.498406993	-0.281908368	-1.106552897	1.853872439	0.717965314	-1.493187646	0	1	0
-0.346637556	-0.472483484	-0.608675869	-0.2086812	-0.964841748	-0.152401534	0.502716595	-0.820719236	0.313800236	-0.500954921	0.888657922	0.746214171	-0.104748376	0	1	0
-1.137207134	-1.082894423	0.524479814	1.35280076	-1.526548473	-0.472867844	-0.451051791	0.307373613	-0.334470892	-1.236323892	1.546758729	0.152988188	-0.37224585	0	1	0
0.060999882	1.367725965	-0.170034959	0.902373272	-1.035055089	-1.033683886	-0.441012124	1.999512887	0.050987617	-0.111641936	-0.515290467	-0.849846211	-0.738462629	0	1	0
-1.433670725	-1.298333578	0.780353678	-0.448909194	-0.403135023	-0.152401534	0.181447244	-1.143031478	1.330009032	-0.868639406	-0.734657403	0.661467602	-0.722540161	0	1	0
-0.408400804	-1.217543895	-0.462462232	-0.448909194	-0.05206832	-0.152401534	-0.089623771	-0.498406993	-0.229345844	-1.054644499	1.195771632	0.774463027	-0.945454722	0	1	0
-1.038385937	-0.652016113	-0.206588368	0.992458769	-0.683988386	-0.825380785	-0.340615451	0.549107795	-0.054137431	-1.128181396	1.634505503	-0.496735507	-0.802152504	0	1	0
-1.668371069	-0.598156324	0.926567314	1.953370745	-0.824415067	-0.601054368	-0.420932789	0.307373613	-0.43959594	-1.063295898	1.766125665	0.845085168	-0.588791424	0	1	0
-1.680723718	-0.248067697	0.341712768	0.632116779	-1.105268429	-0.552984421	-0.340615451	0.951998098	-0.422075098	-0.976781902	0.186683727	0.195361473	-0.213021163	0	1	0
-1.137207134	-0.903361794	-0.243141777	1.232686763	-2.088255198	-0.152401534	-0.441012124	0.468529735	-0.369512574	-1.435306084	0.493797437	0.845085168	-0.388168318	0	1	0
-1.137207134	-0.454530221	-0.170034959	-0.298766697	-1.315908451	-1.113800463	-0.531369129	1.274310341	0.086029299	-1.149809895	0.537670824	-0.482611079	-0.84991991	0	1	0
-1.236028331	-0.741782427	0.195499132	0.752230776	-0.964841748	-1.354150196	-0.782360809	1.11315422	0.068508458	-0.630725915	0.406050663	0.054117191	-0.945454722	0	1	0
-0.383695505	-0.723829165	-0.389355414	0.361860286	-1.386121792	-1.466313404	-0.571527798	1.757778705	0.050987617	-0.868639406	0.011190179	-0.77922407	-0.802152504	0	1	0
-0.877801491	0.443132925	-0.53556905	-0.448909194	-0.824415067	0.248181353	0.221605913	-0.901297296	0.699258745	-1.257952391	0.844784535	0.972205021	-1.454973721	0	1	0
-1.705429018	-0.310904118	-0.316248596	-0.448909194	-0.122281661	1.161510335	0.23164558	-1.545921781	-0.422075098	-0.782125409	0.888657922	0.491974464	-1.279826565	0	1	0
-0.655453797	-0.732805796	-0.608675869	-0.148624201	4.37137214	0.32829793	0.241685247	-0.337250872	2.959447273	-1.063295898	0.888657922	0.025868335	0.605393728	0	1	0
-1.470728674	-0.194207909	1.365208223	0.602088279	2.405398602	-1.113800463	-1.043392157	-1.787655963	-0.054137431	-1.106552897	-0.032683209	-0.496735507	-0.388168318	0	1	0
-0.877801491	-0.831548742	-1.412850869	-1.049479178	-1.035055089	0.408414508	0.472597594	-0.578985054	0.313800236	-0.933524903	1.195771632	0.181237044	-1.015513585	0	1	0
-0.778980294	-1.136754212	-0.97420996	-0.298766697	-0.824415067	1.962676109	1.727555997	-0.981875357	0.62917538	-0.241412931	0.362177276	0.223610329	-0.276711037	0	1	0
-0.877801491	0.748338394	-0.572122459	-0.448909194	-0.824415067	0.889113972	0.964541288	0.710263917	2.135967732	-1.193066893	2.029365988	0.308356898	-1.085572447	0	1	0
###