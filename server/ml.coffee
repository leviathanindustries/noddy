
API.ml = {}

# TODO have a look at machinelearn.js
# https://github.com/machinelearnjs/machinelearnjs

# written with much help from https://github.com/Philmod/node-kmeans
# because weird problems with doing image manipulation of certain SVGs converted to PNGs
# was causing a meteor fiber error seemingly clashing between the nexttick operation
# of the async kmeans implementation and the pngjs code that was trying to process the
# converted png. So here it is in non-callback form...
# note also maybe these problems no longer manifest now that svg2img is not being used...
class Group
	constructor: () ->
		this.centroidMoved = true

	initCluster: () ->
		this.cluster = []
		this.clusterInd = []

	defineCentroid: (self) ->
		this.centroidOld = this.centroid ? []
		if this.centroid and this.cluster.length > 0
			this.calculateCentroid()
		else
			i = Math.floor(Math.random() * self.indexes.length)
			this.centroidIndex = self.indexes[i]
			self.indexes.splice(i, 1)
			this.centroid = []
			if not _.isArray(self.v[this.centroidIndex])
				this.centroid[0] = self.v[this.centroidIndex]
			else
				for j of self.v[this.centroidIndex]
					this.centroid[j] = self.v[this.centroidIndex][j]
		this.centroidMoved = not _.isEqual(this.centroid, this.centroidOld)
		return this

	calculateCentroid: () ->
		this.centroid = []
		for i of this.cluster
			for j of this.cluster[i]
				this.centroid[j] = if this.centroid[j] then this.centroid[j] + this.cluster[i][j] else this.cluster[i][j]
		for k of this.centroid
			this.centroid[k] = this.centroid[k] / this.cluster.length
		return this

	distanceObjects: (self) ->
		this.distances ?= []
		for i of self.v
			d = 0.0
			for n of this.centroid
				d += Math.pow((this.centroid[n] - self.v[i][n]), 2)
			this.distances[i] = Math.sqrt d
		return this

API.ml.kmeans = (vector,clusters=3) ->
	this.v = vector
	this.k = clusters
	this.groups = []
	while this.groups.length < this.k
		this.groups.push new Group(this)
	this.indexes = []
	i = 0
	while this.indexes.length < this.v.length
		this.indexes.push i
		i += 1
	moved = -1

	while moved isnt 0
		moved = 0
		for i of this.groups
			this.groups[i].defineCentroid(this)
			this.groups[i].distanceObjects(this)
		j.initCluster() for j in this.groups
		for vc of this.v
			min = this.groups[0].distances[vc]
			indexGroup = 0
			for g of this.groups
				if this.groups[g].distances[vc] < min
					min = this.groups[g].distances[vc]
					indexGroup = g
			this.groups[indexGroup].cluster.push this.v[vc]
			this.groups[indexGroup].clusterInd.push vc
		for j of this.groups
			if this.groups[j].centroidMoved
				moved++

	cbs = {}
	sizes = []
	for g in this.groups
		# could return 'cluster' too, to get the actual rows from the vector. But clusterInd gives their row numbers
		# for now just return the centroids in ascending order, and add their sizes too
		sizes.push g.clusterInd.length
		cbs[g.clusterInd.length] = g.centroid
	sizes.sort (a,b) -> return a - b
	results = []
	for sz in sizes
		results.push {centroid: cbs[sz], size: sz}
	return results

