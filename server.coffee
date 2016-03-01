App = require 'app'
Db = require 'db'
WordLists = require 'wordLists'
Letters = require 'letters'

Config = require 'config'

exports.client_addDrawing = (id, steps, time) !->
	personalDb = Db.personal App.memberId()
	#return if (personalDb.get 'currentDrawing') isnt id

	currentDrawing = personalDb.get 'currentDrawing'
	# finished drawing, so let's get it out of the personal db and into the shared!
	Db.shared.set 'drawings', id,
		userId: App.memberId()
		wordId: currentDrawing.wordId
		steps: steps
		time: time

	personalDb.remove 'currentDrawing'

exports.client_startDrawing = (cb) !->
	personalDb = Db.personal App.memberId()
	currentDrawing = personalDb.get 'currentDrawing'

	if not currentDrawing
		wordList = WordLists.wordList()

		word = wordList[166]
		# word = wordList[Math.floor(Math.random() * wordList.length)]

		id = Db.shared.get('drawingCount')||0
		Db.shared.incr 'drawingCount'

		currentDrawing =
			id: id
			wordId: word[0]
			word: word[1]
			prefix: word[2]
		Db.personal(App.memberId()).set 'currentDrawing', currentDrawing

	cb.reply currentDrawing

exports.client_getLetters = (drawingId, cb) !->
	wordId = Db.shared.get 'drawings', drawingId, 'wordId'
	log "getLetters from", drawingId, wordId
	word = WordLists.wordList()[wordId][1]
	log "getLetters word:", word

	return null unless word

	# write down when a user has started guessing
	Db.personal(App.memberId()).set drawingId, Date.now()

	# some random letters
	letters = Letters.getRandom Math.min(8, Math.max(5, word.length))

	(if c isnt ' ' then letters.push c) for c in word

	count = 0
	scrambledLetters = {}
	while letters.length
		index = Math.floor(Math.random() * letters.length)
		scrambledLetters[count] = letters.splice index, 1
		count++
	scrambledLetters.count = count

	# We won't send the word, but an array of word lengths and a hash of it
	hash = Config.simpleHash(word.replace(/\s/g,''))
	word = (i.length for i in word.split(" "))

	cb.reply word, hash, scrambledLetters

exports.client_submitAnswer = (drawingId, answer) !->
	log "submitAnswer", drawingId
	startTime = Db.personal(App.memberId()).get drawingId
	return if Date.now() < startTime # Timelords not allowed.
	# We cannot set a timeframe, for the user might be without internet while guessing.

	drawing = Db.shared.ref 'drawings', drawingId
	word = WordLists.wordList()[drawing.get('wordId')][1]
	if word is answer # correct!
		# drawing.merge('members', {})
		drawing.set('members', App.memberId(), true)

