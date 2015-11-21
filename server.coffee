Db = require 'db'
Plugin = require 'plugin'
WordLists = require 'wordLists'

exports.client_addDrawing = (id, drawing) !->
	Db.shared.set 'drawings', id, drawing

exports.client_startDrawing = (cb) !->
	wordList = WordLists.wordList()

	word = wordList[Math.floor(Math.random() * wordList.length)]

	id = Db.shared.get('drawingCount') ? 0
	Db.shared.set 'drawings', id, {userId: Plugin.userId(), wordId: word[0]}
	Db.shared.incr 'drawingCount'

	Db.personal(Plugin.userId()).set 'currentDrawing', {id: id, word: word}

	cb.reply id, word
