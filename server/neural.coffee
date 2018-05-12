
# Building a profile of subjective well-being for social media users (chen)
# http://journals.plos.org/plosone/article?id=10.1371/journal.pone.0187278

# Epistemic Public Reason: A Formal Model of Strategic Communication and Deliberative Democracy
# https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2862013

# Comparative efficacy and acceptability of 21 antidepressant drugs for the acute treatment of adults with major depressive disorder: a systematic review and network meta-analysis
# https://www.thelancet.com/journals/lancet/article/PIIS0140-6736(17)32802-7/fulltext

# Edinburgh clinical psychology doctorate materials
# https://www.ed.ac.uk/health/clinical-psychology/studying/resources/doctorate-resources

# What’s True, and Fake, About the Facebook Effect
# http://behavioralscientist.org/whats-true-and-fake-about-the-facebook-effect/

# https://github.com/roytseng-tw/Detectron.pytorch

# https://medium.freecodecamp.org/building-a-3-layer-neural-network-from-scratch-99239c4af5d3

# https://towardsdatascience.com/activation-functions-and-its-types-which-is-better-a9a5310cc8f

# https://stats.stackexchange.com/questions/181/how-to-choose-the-number-of-hidden-layers-and-nodes-in-a-feedforward-neural-netw

# making a neural network
# one input nodes layer, with as many nodes as keys in the data objects
# one (or could go two, but mostly unnecessary) hidden layer, which should probably use leaky relu (any differentiable function to activate)
# hidden layer should have amount of nodes somewhere between input and output. More nodes is useful if doing pruning of nodes nearing 0 on each pass
# but too many nodes will just "memorise" the training set and not get anywhere with new unseen inputs
# one output nodes layer, which should have one node unless classifying things, in which case as many nodes as there are classes
# need to pass in the inputs, and run through many times (epochs)
# after each epoch, run back and rebalance assumptions
# once a network has been trained on a dataset, should work on new objects shown to it
# so the trained configuration could do with being stored (just needing to know the value of the nodes when it works)

# and remember the problem - will this be any better for finding if one image contains another?
# maybe not, but may be useful for other things anyway

# https://cs.stackexchange.com/questions/14717/object-recognition-given-an-image-does-it-contain-a-particular-3d-object-of-i
# https://www.pyimagesearch.com/2017/11/27/image-hashing-opencv-python/

# and for what I am probably doing (finding logos in pdfs) need to extract pdf to image first
# and probably best to throw out all text first if possible, or extract all images, rather than turning the whole doc into an image
# and if it would be possible to know how many pages to bother checking, that could reduce the search space
# e.g if no logo in the first few pages, it probably won't turn up on page 100

# pdf.js (which is used a bit in the old api code too) may be useful
# https://www.npmjs.com/package/pdfjs-dist
# http://mozilla.github.io/pdf.js/examples/index.html#interactive-examples


