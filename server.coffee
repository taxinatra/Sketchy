Db = require 'db'
Plugin = require 'plugin'
WordLists = require 'wordLists'

exports.client_addDrawing = (id, steps) !->
	personalDb = Db.personal Plugin.userId()
	#return if (personalDb.get 'currentDrawing') isnt id

	currentDrawing = personalDb.get 'currentDrawing'
	# finished drawing, so let's get it out of the personal db and into the shared!
	Db.shared.set 'drawings', id, {userId: Plugin.userId(), wordId: currentDrawing.wordId, steps: steps}

	personalDb.set 'currentDrawing', null

exports.client_startDrawing = (cb) !->
	personalDb = Db.personal Plugin.userId()
	currentDrawing = personalDb.get 'currentDrawing'

	if not currentDrawing
		wordList = WordLists.wordList()

		word = wordList[Math.floor(Math.random() * wordList.length)]

		id = Db.shared.get('drawingCount') ? 0
		Db.shared.incr 'drawingCount'

		currentDrawing = {id: id, wordId: word[0], word: word[1]}
		Db.personal(Plugin.userId()).set 'currentDrawing', currentDrawing

	cb.reply currentDrawing

exports.client_getLetters = (drawingId, cb) !->
	drawing = Db.shared.get 'drawings', drawingId
	word = WordLists.wordList()[drawing.wordId]
	cb.reply word[1]