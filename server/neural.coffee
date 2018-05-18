
import nj from 'numjs'
#import ops from 'ndarray-ops'

nj.fill = (shape,val) ->
  # shape is like [2,3] - can shape have more dimensions than 2? presumably yes, given it is meant to work on n-dimensional arrays
  # val is what val to put on each place
  empt = nj.empty(shape)
  empt[i][j] = val for j in empt[i] for i in empt
  return empt

nj.maximum = (a1,a2) ->
  # Compare two arrays and returns a new array containing the element-wise maxima. If one of the elements being compared is a NaN, 
  # then that element is returned. If both elements are NaNs then the first is returned. The latter distinction is important for 
  # complex NaNs, which are defined as at least one of the real or imaginary parts being a NaN. The net effect is that NaNs are propagated.
  # e.g. np.maximum([2, 3, 4], [1, 5, 2]) = array([2, 5, 4])
  # what about complex numbers? does numjs handle them at all?
  # should this work on arrays of arrays? If so, what counts as the largest one?
  arr = []
  arr.push(if isNaN(a1[k]) then a1[k] else if isNaN(a2[k]) then as[k] else if a1[k] > a2[k] then a1[k] else a2[k]) for k of a1
  return arr
  
###nj.add = (x, copy) ->
  copy = true if arguments.length is 1
  arr = if copy then this.clone() else this
  if _.isNumber x
    ops.addseq arr.selection, x
    return arr
  else
    x = createArray x, this.dtype
    try
      ops.addeq arr.selection, x.selection
    catch err
      ops.adds arr.selection, x.selection
    return arr###

neural_config = new API.collection index: API.settings.es.index + "_neural", type: "config"

API.add 'neural/train', get: () -> return API.neural.train()

# Building a profile of subjective well-being for social media users (chen)
# http://journals.plos.org/plosone/article?id=10.1371/journal.pone.0187278

# Epistemic Public Reason: A Formal Model of Strategic Communication and Deliberative Democracy
# https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2862013

# Comparative efficacy and acceptability of 21 antidepressant drugs for the acute treatment of adults with major depressive disorder: a systematic review and network meta-analysis
# https://www.thelancet.com/journals/lancet/article/PIIS0140-6736(17)32802-7/fulltext

# What’s True, and Fake, About the Facebook Effect
# http://behavioralscientist.org/whats-true-and-fake-about-the-facebook-effect/

API.neural = {}
an = API.neural # short convenience

API.neural.range = (start, stop, step) ->
  if typeof stop is 'undefined'
    stop = start
    start = 0
  step = 1 if typeof step is 'undefined'

  return [] if (step > 0 and start >= stop) or (step < 0 and start <= stop)

  result = []
  i = start
  if step > 0
    while i < stop
      result.push(i)
      i += step
  else
    while i > stop
      result.push(i)
      i += step
  return result

API.neural.transpose = (array) ->
  return _.zip.apply(_, array)

API.neural.hash = (v) ->
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

API.neural.forward = (rec,config) ->
  console.log rec
  if typeof config is 'string'
    # lookup a previously calculated config to do a prediction on a new record
    # this could hvae a cache, so if using saved config, also check to see if already calculated this record for this config
    config = neural_config.get config
  config.weights ?= []
  config.biases ?= []
  if not config.nodes?
    config.nodes = [[]]
    config.nodes[0].push API.neural.hash(rec[k]) for k of rec
    config.nodes[0] = nj.array(config.nodes[0])
  layer = 0
  while layer < config.hidden+1
    current_size = if config.weights.length then config.weights[layer-1].length else if _.isArray(rec) then rec.length else _.keys(rec).length
    next_size = if layer is config.hidden then config.classes.length else Math.ceil((current_size - config.classes.length)/2)
    config.hidden = layer if next_size <= config.classes.length
    config.weights.push(0.01 * nj.random(current_size,next_size)) if config.weights.length < layer+1
    config.biases.push(nj.zeros([1,next_size])) if config.biases.length < layer+1
    if layer is config.hidden
      console.log config.nodes[layer]
      console.log config.weights[layer]
      config.nodes[layer+1] = nj.dot(config.nodes[layer], config.weights[layer]) + config.biases[layer] # this is softmax final output layer
    else
      config.nodes[layer+1] = nj.maximum(0, nj.dot(X, config.weights[layer]) + config.biases[layer]) # this is relu but want to change to leaky or make configurable
    layer++
  config.result = config.classes[config.nodes[config.nodes.length-1].indexOf(Math.max(config.nodes[config.nodes.length-1]))]
  return config

# https://stats.stackexchange.com/questions/181/how-to-choose-the-number-of-hidden-layers-and-nodes-in-a-feedforward-neural-netw
# http://cs231n.github.io/neural-networks-case-study/#net
# https://towardsdatascience.com/activation-functions-and-its-types-which-is-better-a9a5310cc8f
# https://medium.freecodecamp.org/building-a-3-layer-neural-network-from-scratch-99239c4af5d3
###API.neural.train = (recs, answers, classes=[0,1], rate=0.1, reg=0.003, iterations=4000, hidden=1) ->
  recs = API.neural.test._examples.recs
  answers = API.neural.test._examples.answers
  classes = [0,1,2]
  config = {classes: classes, rate: rate, hidden: hidden, sampled: recs.length}

  h = 100 # this should be the number of nodes I want to use in the hidden layer, some function related to number of input recs, and number of things in each rec

  iteration = 0
  while iteration < iterations # or could be while error is greater than acceptable, or until convergence appears
    iteration++
    #for r of recs
    #  config = API.neural.forward recs[r], config
    config.weights = []
    config.biases = []
    config.weights[0] = nj.random([2, h]).multiply(nj.fill([2, h],0.01),false) # 2 is number of things in each incoming rec
    #console.log config.weights[0]
    config.biases[0] = nj.zeros([1,h])
    config.weights[1] = 0.01 * nj.random([h,config.classes.length])
    config.biases[1] = nj.zeros([1,config.classes.length])
    config.nodes = []
    arecs = nj.array(recs)
    #console.log arecs
    config.nodes[0] = nj.max(0, nj.dot(arecs, config.weights[0]) + config.biases[0]) # relu activation, should change to lrelu, maybe make configurable
    config.nodes[1] = nj.dot(config.nodes[0], config.weights[1]) + config.biases[1]
    # compute the class probabilities

    # add pruning step once pruning is implemented

    exp_scores = nj.exp config.nodes[config.nodes.length-1]
    probs = exp_scores.divide(nj.fill(exp_scores.shape, nj.sum(exp_scores, axis=1, keepdims=true)), false)
    cl = []
    cl.push(probs[p][answers[p]]) for p of probs
    correct_logprobs = -nj.log(nj.array(cl))
    data_loss = nj.sum(correct_logprobs)/recs.length
    reg_loss = 0
    for w in config.weights
      reg_loss += 0.5*reg*nj.sum(w*w) # what is reg?
    loss = data_loss + reg_loss
    if iteration % 1000 is 0
      console.log "iteration " + iteration + ": loss" + loss

    dscores = []
    dscores.push(probs[p][answers[p]]) for p of probs
    console.log dscores
    dscores = nj.array(dscores)
    console.log(dscores)
    dscores.subtract(nj.ones([recs.length]),false)
    #dscores = probs
    #dscores([range(recs.length),answers]).subtract(nj.ones([recs.length]),false)
    dscores /= recs.length
    ws = config.weights.length-1
    while ws >= 0
      if ws is config.weights.length-1
        # first step back, rewind the softmax
        # alter the weights and biases at this layer with the updated values
        dw = nj.dot(config.nodes[ws].T, dscores) + reg*config.weights[ws]
        db = nj.sum(dscores, axis=0, keepdims=True)
      else
        # rewind the activation functions performed at each hidden layer
        # alter the weights and biases at this layer with the updated values
        dh = nj.dot(config.weights[ws+1], config.weights[ws].T)
        dh[config.nodes[ws] <= 0] = 0 # this is for relu, will need to be different for other activation functions
        dw = nj.dot(config.nodes[ws].T, dh) + reg*config.weights[ws]
        db = nj.sum(dh, axis=0, keepdims=True)
      config.weights[ws] += -rate * dw
      config.biases[ws] = -rate * db
      ws--

  # could try multiple times with different rates, iterations, layers, pruning, node functions if results are not yet good enough
  
  # save the config so it can be used for later identifications - need to know what to call it
  #neural_config.insert config
  return config###
    





API.neural.train = (recs,answers,config={}) ->
  config.rate ?= 0.1 # step_size
  config.reg ?= 0.003
  config.iterations ?= 4000
  config.hidden ?= 1
  config.nodes = []
  config.weights = []
  config.biases = []
  config.classes = [0,1,2] # all the different possible answer types K is length of this
  
  recs = API.neural.test._examples.recs # list of records to train on D is length of rec keys / list
  answers = API.neural.test._examples.answers # the answers that the records must match to

  config.sampled = recs.length
  
  # num_examples X.shape
  K = config.classes.length
  D = 2
  h = 100 # this should be the number of nodes I want to use in the hidden layer, some function related to number of input recs, and number of things in each rec

  W = [[],[]]
  W[i][j] = Math.random() * 0.01 for j of W[i] for i of W
  b = []
  b.push(0) for i in an.range(h)
  W2 = []
  W2.push([]) while W2.length < h
  W2[i][j] = Math.random() * 0.01 for j of W2[i] for i of W2
  b2 = []
  b2.push(0) for i in an.range(K)

  for i in an.range(10000) # or could be while error is greater than acceptable, or until convergence appears
    #for r of recs
    #  config = API.neural.forward recs[r], config
    config.nodes[0] = [[],[]]
    config.nodes[0][k].push(if lr = recs[j][k] * W[j][k] + b[j] > 0 then lr else 0) for k of recs[j] for j of recs # relu hidden layer
    config.nodes[1] = [[],[]]
    config.nodes[1][k].push(config.nodes[j][k] * W2[j][k] + b2[j]) for k of config.nodes[0][j] for j of config.nodes[0]



    # add pruning step once pruning is implemented

    ###exp_scores = nj.exp config.nodes[config.nodes.length-1]
    probs = exp_scores.divide(nj.fill(exp_scores.shape, nj.sum(exp_scores, axis=1, keepdims=true)), false)
    correct_logprobs = []
    correct_logprobs.push(-Math.log(probs[p][answers[p]])) for p of probs

    data_loss = nj.sum(correct_logprobs)/recs.length
    reg_loss = 0
    for w in config.weights
      reg_loss += 0.5*reg*nj.sum(w*w) # what is reg?
    loss = data_loss + reg_loss
    if iteration % 1000 is 0
      console.log "iteration " + iteration + ": loss" + loss

    dscores = []
    dscores.push((probs[p][answers[p]]-1)/recs.length) for p of probs
    console.log dscores
    dscores = nj.array(dscores)
    console.log(dscores)
    dscores.subtract(nj.ones([recs.length]),false)
    dscores /= recs.length
    ws = config.weights.length-1
    while ws >= 0
      if ws is config.weights.length-1
        # first step back, rewind the softmax
        # alter the weights and biases at this layer with the updated values
        dw = nj.dot(config.nodes[ws].T, dscores) + reg*config.weights[ws]
        db = nj.sum(dscores, axis=0, keepdims=True)
      else
        # rewind the activation functions performed at each hidden layer
        # alter the weights and biases at this layer with the updated values
        dh = nj.dot(config.weights[ws+1], config.weights[ws].T)
        dh[config.nodes[ws] <= 0] = 0 # this is for relu, will need to be different for other activation functions
        dw = nj.dot(config.nodes[ws].T, dh) + reg*config.weights[ws]
        db = nj.sum(dh, axis=0, keepdims=True)
      config.weights[ws] += -rate * dw
      config.biases[ws] = -rate * db
      ws--###

  # could try multiple times with different rates, iterations, layers, pruning, node functions if results are not yet good enough
  
  # save the config so it can be used for later identifications - need to know what to call it
  #neural_config.insert config
  return config


###API.neural.train = () ->
  N = 100
  D = 2
  K = 3
  X = API.neural.test._examples.recs
  y = API.neural.test._examples.answers
  h = 100
  W = [[],[]]
  W[i][j] = Math.random() * 0.01 for j of W[i] for i of W
  b = []
  b.push(0) for i in range(0,h)
  W2 = []
  W2.push([]) while W2.length < h
  W2[i][j] = Math.random() * 0.01 for j of W2[i] for i of W2
  b2 = []
  b2.push(0) for i in range(0,K)
  step_size = 1e-0
  reg = 1e-3
  num_examples = X.length
  for i in range(10000)
    hidden_layer = [[],[]]
    hidden_layer[k].push(if lr = X[j][k] * W[j][k] + b[j] > 0 then lr else 0) for k of X[j] for j of X
    exp_scores = [[],[]]
    exp_scores[k].push(Math.exp(hidden_layer[j][k] * W2[j][k] + b2[j])) for k of hidden_layer[j] for j of hidden_layer
    probs = [[],[]]
    probs[k].push(exp_scores[j][k]/exp_scores[j].reduce((acc, val) -> return acc + val)) for k of probs[j] for j of probs
    
    correct_logprobs = []
    correct_logprobs.push(-Math.log(probs[p][y[p]])) for p of probs
    data_loss = correct_logprobs[j].reduce((acc, val) -> return acc + val)/num_examples
    reg_loss = 0.5*reg*W.multiply(W,false).reduce((acc, val) -> return acc + val) + 0.5*reg*W2.multiply(W2,false).reduce((acc, val) -> return acc + val)
    # TODO replace W and W2 multiply
    loss = data_loss + reg_loss
    if i % 1000 is 0
      console.log "iteration " + i + ": loss " + loss
    
    dscores = []
    dscores.push((probs[p][y[p]]-1)/num_examples) for p of probs

    dW2 = []
    zhl = _.zip.apply(_, hidden_layer)
    dW2.push(zhl[j][k] * dscores[j][k] + reg * W2[j][k]) for k of zhl[j] for j of zhl

    db2 = dscores[0].reduce((acc, val) -> return acc + val)
    dhidden = []
    zdh = _.zip.apply(_, W2)
    dhidden.push(zdh[j][k] * dscores[j][k]) for k of zdh[j] for j of zdh
    #dhidden[hidden_layer <= 0] = 0

    dW = []
    xhl = _.zip.apply(_, X)
    dW.push(xhl[j][k] * dhidden[j][k] + reg * W[j][k]) for k of xhl[j] for j of xhl

    db= dhidden[0].reduce((acc, val) -> return acc + val)

    W[j][k] += -step_size * dW[j][k] for k of dW[j] for j of dW
    b[j] += -step_size * db[j] for j of db
    W2[j][k] += -step_size * dW2[j][k] for k of dW2[j] for j of dW2
    b2[j] += -step_size * db2[j] for j of db2

  return scores###

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







###
# initialize parameters randomly
h = 100 # size of hidden layer
W = 0.01 * np.random.randn(D,h)
b = np.zeros((1,h))
W2 = 0.01 * np.random.randn(h,K)
b2 = np.zeros((1,K))

# some hyperparameters
step_size = 1e-0
reg = 1e-3 # regularization strength

# gradient descent loop
num_examples = X.shape[0]
for i in xrange(10000):
  
  # evaluate class scores, [N x K]
  hidden_layer = np.maximum(0, np.dot(X, W) + b) # note, ReLU activation
  scores = np.dot(hidden_layer, W2) + b2
  
  # compute the class probabilities
  exp_scores = np.exp(scores)
  probs = exp_scores / np.sum(exp_scores, axis=1, keepdims=True) # [N x K]
  
  # compute the loss: average cross-entropy loss and regularization
  correct_logprobs = -np.log(probs[range(num_examples),y])
  data_loss = np.sum(correct_logprobs)/num_examples
  reg_loss = 0.5*reg*np.sum(W*W) + 0.5*reg*np.sum(W2*W2)
  loss = data_loss + reg_loss
  if i % 1000 == 0:
    print "iteration %d: loss %f" % (i, loss)
  
  # compute the gradient on scores
  dscores = probs
  dscores[range(num_examples),y] -= 1
  dscores /= num_examples
  
  # backpropate the gradient to the parameters
  # first backprop into parameters W2 and b2
  dW2 = np.dot(hidden_layer.T, dscores)
  db2 = np.sum(dscores, axis=0, keepdims=True)
  # next backprop into hidden layer
  dhidden = np.dot(dscores, W2.T)
  # backprop the ReLU non-linearity
  dhidden[hidden_layer <= 0] = 0
  # finally into W,b
  dW = np.dot(X.T, dhidden)
  db = np.sum(dhidden, axis=0, keepdims=True)
  
  # add regularization gradient contribution
  dW2 += reg * W2
  dW += reg * W
  
  # perform a parameter update
  W += -step_size * dW
  b += -step_size * db
  W2 += -step_size * dW2
  b2 += -step_size * db2
###


API.neural.test = {} # this can become the usual test function eventually
API.neural.test._examples = {
  recs: [
    [0.00000000e+00,0.00000000e+00],
    [-4.23708671e-03,9.16937845e-03],
    [4.86593277e-03,1.96072517e-02],
    [5.27460182e-03,2.98404461e-02],
    [-1.23668002e-02,3.84649026e-02],
    [2.13217197e-02,4.57836695e-02],
    [1.93537084e-02,5.74328177e-02],
    [-1.91772153e-02,6.80567723e-02],
    [1.21100808e-02,7.98955059e-02],
    [1.76281756e-02,8.91835760e-02],
    [4.95784574e-02,8.80057786e-02],
    [5.52812805e-02,9.63828773e-02],
    [4.61544595e-02,1.12080972e-01],
    [4.82141941e-02,1.22141434e-01],
    [1.27645000e-02,1.40836881e-01],
    [1.26174047e-01,8.38865367e-02],
    [7.75981862e-02,1.41768492e-01],
    [1.16479985e-01,1.26171312e-01],
    [1.55781239e-01,9.37553021e-02],
    [1.12162455e-01,1.55732334e-01],
    [1.79745934e-01,9.22147551e-02],
    [1.83857229e-01,1.05791908e-01],
    [1.58543668e-01,1.55713266e-01],
    [2.02182743e-01,1.14438729e-01],
    [1.58562711e-01,1.83377698e-01],
    [2.15376004e-01,1.31841495e-01],
    [2.25771074e-01,1.34163990e-01],
    [2.56513306e-01,9.26341673e-02],
    [2.73845426e-01,7.07143584e-02],
    [2.80434567e-01,8.46405583e-02],
    [2.88841117e-01,9.16415487e-02],
    [1.80350240e-01,2.55978535e-01],
    [3.22470754e-01,2.21753864e-02],
    [2.94779874e-01,1.55614707e-01],
    [3.31458714e-01,8.99014431e-02],
    [3.42265107e-01,8.85541789e-02],
    [3.43811815e-01,1.18426521e-01],
    [3.73734787e-01,-1.39045023e-03],
    [3.82851096e-01,2.75125954e-02],
    [3.91154272e-01,-4.67608960e-02],
    [3.85046921e-01,1.22423512e-01],
    [3.99012334e-01,-1.10915591e-01],
    [4.15367649e-01,-8.63212085e-02],
    [3.70117267e-01,-2.27304702e-01],
    [4.27501943e-01,-1.21544037e-01],
    [3.96228137e-01,-2.22743875e-01],
    [4.52711091e-01,-1.04637494e-01],
    [3.84479970e-01,-2.78496531e-01],
    [3.93744775e-01,-2.82918903e-01],
    [4.19058584e-01,-2.63372182e-01],
    [4.14729436e-01,-2.88228221e-01],
    [4.59569700e-01,-2.32759047e-01],
    [4.37765591e-01,-2.90261094e-01],
    [4.17628819e-01,-3.34947127e-01],
    [5.31892721e-01,-1.20875121e-01],
    [3.77536708e-01,-4.07563503e-01],
    [4.70370114e-01,-3.14196285e-01],
    [4.89950121e-01,-3.02399843e-01],
    [4.75834954e-01,-3.41776797e-01],
    [4.55664196e-01,-3.84106730e-01],
    [3.70246457e-01,-4.79819778e-01],
    [4.22899406e-01,-4.48119660e-01],
    [4.54156936e-01,-4.31214975e-01],
    [2.29134195e-01,-5.93680216e-01],
    [4.47543767e-01,-4.66498785e-01],
    [3.74825653e-01,-5.39058616e-01],
    [2.94883210e-01,-5.97903284e-01],
    [7.83182321e-02,-6.72220755e-01],
    [-1.78626076e-02,-6.86636381e-01],
    [3.09995616e-01,-6.24235113e-01],
    [2.73978454e-01,-6.51831874e-01],
    [2.76904047e-01,-6.61558327e-01],
    [9.49923115e-02,-7.21042357e-01],
    [1.91115845e-01,-7.12176075e-01],
    [8.20741475e-02,-7.42955135e-01],
    [2.30419926e-01,-7.21683924e-01],
    [1.60757942e-01,-7.50656049e-01],
    [-4.65068899e-02,-7.76386103e-01],
    [-1.21555209e-02,-7.87785014e-01],
    [-1.63958107e-01,-7.80954222e-01],
    [-2.00092982e-01,-7.82915954e-01],
    [1.10454247e-01,-8.10691894e-01],
    [6.42003100e-02,-8.25790993e-01],
    [-4.32846843e-01,-7.18004924e-01],
    [-8.22039124e-02,-8.44493372e-01],
    [-2.94434760e-01,-8.06522069e-01],
    [-3.73026579e-01,-7.84517716e-01],
    [-4.20195344e-01,-7.71818637e-01],
    [-3.51091570e-01,-8.16613841e-01],
    [-6.16268940e-02,-8.96875111e-01],
    [-4.65836964e-01,-7.80667793e-01],
    [-8.79615363e-01,-2.66815661e-01],
    [-5.53187955e-01,-7.46705052e-01],
    [-6.19746959e-01,-7.05956571e-01],
    [-3.53045706e-01,-8.81418963e-01],
    [-6.47982150e-01,-7.07773649e-01],
    [-7.59905888e-01,-6.02374680e-01],
    [-7.28106216e-01,-6.55641228e-01],
    [-6.34274249e-01,-7.59997492e-01],
    [-6.55306324e-01,-7.55363239e-01],
    [-0.00000000e+00,-0.00000000e+00],
    [-8.23942366e-03,-5.84314152e-03],
    [-1.81149153e-02,-8.94267646e-03],
    [-2.97612736e-02,-5.70440510e-03],
    [-3.22796768e-02,-2.43003899e-02],
    [-4.76614481e-02,-1.67076777e-02],
    [-4.54019836e-02,-4.01466619e-02],
    [-6.13682745e-02,-3.51201471e-02],
    [-7.61988825e-02,-2.69012310e-02],
    [-8.80986494e-02,-2.24296855e-02],
    [-9.53604540e-02,-3.33080219e-02],
    [-1.11102125e-01,1.41305482e-03],
    [-1.21209317e-01,-8.24460486e-04],
    [-1.30659862e-01,-1.30820028e-02],
    [-1.41124439e-01,9.04721026e-03],
    [-1.50667515e-01,1.60044030e-02],
    [-1.60417667e-01,1.96457564e-02],
    [-1.68665766e-01,3.22280369e-02],
    [-1.81355332e-01,1.29651376e-02],
    [-1.90404577e-01,2.40639443e-02],
    [-2.01527830e-01,1.40959473e-02],
    [-2.07293142e-01,4.49995746e-02],
    [-2.19292379e-01,-3.59662123e-02],
    [-2.29672488e-01,3.49947520e-02],
    [-2.40253931e-01,3.23660597e-02],
    [-2.20845419e-01,1.22459398e-01],
    [-2.11316342e-01,1.55942160e-01],
    [-2.54723441e-01,-9.74481093e-02],
    [-2.51611011e-01,1.29165540e-01],
    [-2.67289055e-01,1.19850455e-01],
    [-2.92315170e-01,7.98699309e-02],
    [-3.10372698e-01,4.14729757e-02],
    [-2.59479848e-01,1.92741650e-01],
    [-2.03423782e-01,2.64064151e-01],
    [-2.29071576e-01,2.55877629e-01],
    [-2.23422926e-01,2.73988033e-01],
    [-2.59563037e-01,2.54673192e-01],
    [-2.28759704e-01,2.95548003e-01],
    [-3.45760001e-01,1.66679113e-01],
    [-2.10391740e-01,3.33051890e-01],
    [-3.21531313e-01,2.44675832e-01],
    [-2.51951024e-01,3.28684944e-01],
    [-2.70213356e-01,3.27057146e-01],
    [-2.65039473e-01,3.44105066e-01],
    [-2.65754811e-01,3.56237624e-01],
    [-7.94053011e-02,4.47555995e-01],
    [-1.87366424e-01,4.25194262e-01],
    [-1.31426607e-01,4.56193174e-01],
    [-2.27992447e-01,4.27898934e-01],
    [-4.44335775e-02,4.92950971e-01],
    [2.10479672e-01,4.59101645e-01],
    [-1.66112947e-01,4.87634671e-01],
    [-1.42876201e-01,5.05446937e-01],
    [-2.42694872e-01,4.77181943e-01],
    [-1.18537588e-01,5.32418540e-01],
    [4.49012887e-02,5.53738069e-01],
    [-5.08105400e-02,5.63369896e-01],
    [-7.76437631e-04,5.75757052e-01],
    [-1.65073330e-01,5.62121943e-01],
    [3.32470484e-02,5.95031490e-01],
    [3.98655256e-02,6.04748045e-01],
    [9.87638397e-02,6.08194740e-01],
    [1.17040458e-01,6.15228745e-01],
    [1.72233290e-01,6.12612742e-01],
    [2.05802690e-01,6.12830965e-01],
    [2.55813549e-01,6.04679989e-01],
    [1.83543899e-01,6.40902552e-01],
    [3.83087985e-01,5.57905085e-01],
    [2.38207448e-01,6.44240487e-01],
    [3.66852742e-01,5.92609335e-01],
    [3.69446327e-01,6.02875108e-01],
    [4.51136563e-01,5.57504326e-01],
    [2.43613390e-01,6.85257715e-01],
    [4.60034514e-01,5.76271008e-01],
    [4.24187730e-01,6.15453709e-01],
    [4.32437980e-01,6.22027670e-01],
    [5.84808874e-01,4.97319013e-01],
    [6.50639740e-01,4.26152789e-01],
    [5.66474701e-01,5.47594190e-01],
    [6.68012761e-01,4.36498235e-01],
    [6.74484325e-01,4.45045489e-01],
    [6.05691351e-01,5.50054065e-01],
    [6.60323063e-01,5.00025895e-01],
    [7.20097077e-01,4.29357263e-01],
    [7.08210472e-01,4.67294837e-01],
    [7.16070256e-01,4.73722561e-01],
    [8.03177320e-01,3.30942697e-01],
    [8.16955142e-01,3.23809253e-01],
    [8.87268950e-01,5.36401593e-02],
    [8.03286710e-01,4.03625198e-01],
    [8.67502187e-01,2.71820228e-01],
    [9.11073926e-01,1.21893746e-01],
    [9.28674721e-01,-3.38911760e-02],
    [9.26017267e-01,1.57965168e-01],
    [9.45105863e-01,9.11897340e-02],
    [9.56767002e-01,-7.36295377e-02],
    [9.65840708e-01,-8.63940949e-02],
    [9.45129469e-01,-2.58329959e-01],
    [9.39724374e-01,-3.11156087e-01],
    [9.96752513e-01,-8.05259476e-02],
    [0.00000000e+00,-0.00000000e+00],
    [1.00956925e-02,-3.27717548e-04],
    [2.00842766e-02,-2.17794711e-03],
    [2.90662217e-02,-8.56903737e-03],
    [3.90931876e-02,-1.02082889e-02],
    [3.96382194e-02,-3.12981100e-02],
    [5.72075622e-02,-2.00097329e-02],
    [6.87989468e-02,-1.63154764e-02],
    [7.04441520e-02,-3.95925167e-02],
    [8.41506969e-02,-3.43965555e-02],
    [8.30610963e-02,-5.74795162e-02],
    [8.45387038e-02,-7.21033049e-02],
    [9.30286167e-02,-7.77049214e-02],
    [8.72209605e-02,-9.81613086e-02],
    [1.25539610e-01,-6.50981230e-02],
    [9.60047671e-02,-1.17217430e-01],
    [9.50075359e-02,-1.30741546e-01],
    [1.20616695e-01,-1.22222747e-01],
    [9.17506973e-02,-1.56970254e-01],
    [1.33795989e-01,-1.37592185e-01],
    [1.37636635e-01,-1.47879406e-01],
    [7.38717261e-02,-1.98842593e-01],
    [5.04816645e-02,-2.16412379e-01],
    [4.34408672e-03,-2.32282615e-01],
    [8.93145855e-02,-2.25371733e-01],
    [1.44337272e-01,-2.07209447e-01],
    [1.07391043e-01,-2.39665846e-01],
    [1.46581980e-01,-2.29986714e-01],
    [9.08349764e-02,-2.67844814e-01],
    [2.84722888e-02,-2.91542277e-01],
    [8.00521687e-02,-2.92265316e-01],
    [-1.66537846e-02,-3.12688137e-01],
    [9.74908601e-02,-3.08179602e-01],
    [1.09753441e-01,-3.14746395e-01],
    [-2.95339704e-02,-3.42162086e-01],
    [-3.99780620e-02,-3.51267705e-01],
    [1.24573106e-01,-3.41632765e-01],
    [6.51151013e-02,-3.68021260e-01],
    [-5.13537795e-02,-3.80387558e-01],
    [-7.70657008e-02,-3.86327742e-01],
    [2.80752589e-02,-4.03063801e-01],
    [-9.39582115e-02,-4.03342244e-01],
    [-9.42187038e-02,-4.13647761e-01],
    [-1.70656330e-01,-3.99412864e-01],
    [5.10506982e-02,-4.41502764e-01],
    [-8.38342042e-02,-4.46747576e-01],
    [-1.87257850e-01,-4.25242090e-01],
    [-1.53136083e-01,-4.49371233e-01],
    [-2.05856083e-01,-4.38977592e-01],
    [-2.30426149e-01,-4.38039716e-01],
    [-2.11519254e-01,-4.58623613e-01],
    [-4.23184521e-01,-2.93761714e-01],
    [-3.57899297e-01,-3.84445456e-01],
    [-2.73597832e-01,-4.60160444e-01],
    [-4.05152417e-01,-3.65201561e-01],
    [-4.56646832e-01,-3.16410566e-01],
    [-4.14288022e-01,-3.85139956e-01],
    [-5.52114759e-01,-1.63297516e-01],
    [-4.70779119e-01,-3.48708050e-01],
    [-4.78311427e-01,-3.55508114e-01],
    [-5.19119724e-01,-3.12768558e-01],
    [-4.02869314e-01,-4.66209666e-01],
    [-5.35926950e-01,-3.24017254e-01],
    [-6.30973900e-01,-8.26475377e-02],
    [-6.11024534e-01,-2.11105562e-01],
    [-5.75630795e-01,-3.15796849e-01],
    [-6.47512822e-01,-1.58655568e-01],
    [-6.62719618e-01,-1.37175784e-01],
    [-6.84098875e-01,-6.16224118e-02],
    [-6.92422306e-01,-7.94865302e-02],
    [-7.02235702e-01,-8.25469758e-02],
    [-7.16687032e-01,-2.63622898e-02],
    [-7.08031648e-01,-1.66183047e-01],
    [-7.37313923e-01,-9.39188860e-03],
    [-7.43541641e-01,7.65788887e-02],
    [-7.50766763e-01,-1.01342467e-01],
    [-6.86972823e-01,-3.42630938e-01],
    [-7.63379461e-01,1.48963320e-01],
    [-7.62835739e-01,1.97065015e-01],
    [-7.96392420e-01,5.03077672e-02],
    [-8.07058941e-01,4.06258317e-02],
    [-7.56691805e-01,3.11189653e-01],
    [-7.97057776e-01,2.25280591e-01],
    [-7.81415386e-01,3.03772046e-01],
    [-8.36369156e-01,-1.42874675e-01],
    [-8.49120508e-01,1.27137877e-01],
    [-7.04233740e-01,5.08597793e-01],
    [-8.61311815e-01,1.74384898e-01],
    [-7.49268003e-01,4.78247756e-01],
    [-8.26794088e-01,3.52979284e-01],
    [-7.43538781e-01,5.23064396e-01],
    [-6.92416572e-01,6.04543692e-01],
    [-7.14528099e-01,5.94167438e-01],
    [-7.55134995e-01,5.58777338e-01],
    [-7.48550178e-01,5.84134650e-01],
    [-6.18485050e-01,7.33689749e-01],
    [-4.22400513e-01,8.72863116e-01],
    [-3.47921122e-01,9.15944853e-01],
    [-5.85088773e-01,7.98480518e-01],
    [-4.59191376e-01,8.88337368e-01]
  ],
  answers: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
}