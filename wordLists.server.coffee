Db = require 'db'

WordlistEN1 = require 'wordlistEN1'
WordlistNL1 = require 'wordlistNL1'

listIndex = Db.shared.get('wordList')||'en1'
wordLists = {}
wordLists['en1'] = WordlistEN1.wordList()
wordLists['nl1'] = WordlistNL1.wordList()

exports.process = process = (word) ->
	word = word.replace(/\s/g,'') # remove spaces
	word = word.toLowerCase() # force lower case
	return word

exports.getRndWordObjects = (amount, process = true) ->
	word = rndWord()[0]
	return false if not word
	if process
		word[1] = word.replace(/\s/g,'') # remove spaces
		word[1] = word.toLowerCase() # force lower case
	return {
		wordId: listIndex + '_' + word[0]
		word: word[1]
		prefix: word[2]
	}

exports.getWord = (id, process = true) ->
	wordId = null
	if id
		r = /^(.*)?_(.*)$/i.exec id
		listId = r[1]
		wordId = 0|r[2]
	log "get word", listId, wordId
	if wordId is null
		word = rndWord()[0][1]
	else
		word = wordLists[listId][wordId][1] # get word
	if process then word = process(word)
	return word

exports.getPrefix = (id) ->
	r = /^(.*)?_(.*)$/i.exec id
	listId = r[1]
	wordId = 0|r[2]
	return wordLists[listId][wordId][2]

exports.getFields = (id) ->
	r = /^(.*)?_(.*)$/i.exec id
	listId = r[1]
	wordId = 0|r[2]
	word = wordLists[listId][wordId][1] # get word
	return (i.length for i in word.split(" "))

rndWord = (amount = 1) ->
	# form an sorted array with id's we already used
	used = []
	Db.shared.forEach 'drawings', (item) !->
		r = /^(.*)?_(.*)$/i.exec item.get('wordId')
		listId = r[1]
		wordId = 0|r[2]
		if listId is listIndex # same list?
			used.push wordId
	used.sort (a,b) -> a - b # sort on value

	# form an sorted array with possible words
	words = []
	for w in wordLists[listIndex]
		words.push(w) if w[4] # if not disabled

	# pick x numbers that will be available
	usedLen = used.length
	limit = words.length - usedLen

	if limit <= 0
		log "Out of words"
		return false
	if limit is 1
		log "Wordlist: this is the last word"
		Db.shared.set "outOfWords", true

	pick = []
	for i in [0...amount]
		a = Math.floor(Math.random()*limit)
		pick.push a
	pick = pick.sort (a,b) -> a - b # sort on value

	# walk though the available list, splicing the used and picking along the way
	# the idea is that only have to walk each array once. because of sorting
	r = []
	usedWalker = 0
	rWalker = 0
	i = 0
	while i < words.length
		word = words[i]
		word[0] = 0|word[0] #parse to int

		# check if the word is already used
		while usedWalker < usedLen and used[usedWalker] <= word[0]
			# log "walk",i,  usedWalker, ":", used[usedWalker], word[0]
			if (used[usedWalker]) is (word[0]) # if so, splice
				# log "slice", i, 1
				words.splice i, 1
				i--
				break
			usedWalker++
		# if index is what we picked, write to return
		if i is (pick[rWalker])
			# log "picking", i, pick[rWalker], word
			r[rWalker] = word
			rWalker++
			break if rWalker >= pick.length # we're done here
		i++
	return r