App = require 'app'
Comments = require 'comments'
Db = require 'db'
{tr} = require 'i18n'

Config = require 'config'
Letters = require 'letters'
WordList = require 'wordLists'

# Storage overview
# Personal:
#	<drawingId>: <time guessed>

# Shared:
#	<drawingId>:
#		Stuff about time and author
#		steps: <data in string>
#		members:
#			<memberId>: <time they needed to guess in sec>

#	scores:
#		<memberId>:
#			<drawingId>: <score>

exports.client_addDrawing = (id, steps, time) !->
	personalDb = Db.personal App.memberId()
	#return if (personalDb.get 'currentDrawing') isnt id

	currentDrawing = personalDb.get 'lastDrawing'
	# finished drawing, so let's get it out of the personal db and into the shared!
	Db.shared.set 'drawings', id,
		memberId: App.memberId()
		wordId: currentDrawing.wordId
		steps: steps
		time: time

	# notify
	Comments.post
		s: 'new'
		pushText: App.userName() + " added a new drawing"
		path: '/'


exports.client_startDrawing = (cb) !->
	personalDb = Db.personal App.memberId()
	lastDrawing = personalDb.get('lastDrawing')||false

	if !lastDrawing or lastDrawing.time+(Config.cooldown()) < Date.now()*.001 # first or at least 4 hours ago

		wordObj = WordList.getObject null, false
		id = Db.shared.get('drawingCount')||0
		Db.shared.incr 'drawingCount'

		lastDrawing = wordObj
		lastDrawing.id = id
		lastDrawing.time = 0|Date.now()*.001
		Db.personal(App.memberId()).set 'lastDrawing', lastDrawing
		cb.reply lastDrawing
	else
		cb.reply false # no no no, you don't get to try again.


exports.client_getLetters = (drawingId, cb) !->
	wordId = Db.shared.get 'drawings', drawingId, 'wordId'
	word = WordList.getWord wordId
	memberId = App.memberId()

	if Db.personal(memberId).get drawingId # already started
		cb.reply null
		return null
	unless word # we need a word
		cb.reply null
		return null

	# write down when a user has started guessing
	Db.personal(memberId).set drawingId, Date.now()
	# set failed score. You can better this by providing the correct answer :)
	Db.shared.set 'drawings', drawingId, 'members', memberId, -1
	Db.shared.set 'scores', memberId, drawingId, 0

	# some random letters
	letters = Letters.getRandom Math.min(8, Math.max(5, word.length))

	(if c isnt ' ' then letters.push c) for c in word

	count = 0
	scrambledLetters = {}
	scrambledLetters[i] = letter for letter, i in letters.sort()
	scrambledLetters.count = letters.length

	# We won't send the word, but an array of word lengths and a hash of it
	hash = Config.simpleHash(word)
	fields = WordList.getFields(wordId)

	cb.reply fields, hash, scrambledLetters

exports.client_submitAnswer = (drawingId, answer, time) !->
	memberId = App.memberId()
	log "submitAnswer by", memberId, ":", drawingId, answer, time
	startTime = Db.personal(memberId).get drawingId
	return if Date.now() < startTime # Timelords not allowed.
	# We cannot set a timeframe, for the user might be without internet while guessing.

	drawing = Db.shared.ref 'drawings', drawingId
	word = WordList.getWord drawing.get('wordId')
	if word is answer.replace(/\s/g,'') # correct!
		# set artist's score if we have the highest
		best = true
		drawing.iterate 'members', (member) !->
			best = false if time > member.get() and member.get()>=0 # skip -1/-2 timings
		if best
			log "we're the best. so score:", drawing.get('memberId'), Config.timeToScore(time)
			Db.shared.set 'scores', drawing.get('memberId'), drawingId, Config.timeToScore(time)

		# write own time and score
		drawing.merge('members', {}) # make sure path exists
		drawing.set('members', memberId, time)
		Db.shared.set 'scores', memberId, drawingId, Config.timeToScore(time)
	else
		log "answer was not correct",  word, 'vs', answer.replace(/\s/g, '')

exports.client_submitForfeit = (drawingId) !->
	memberId = App.memberId()
	log "submitForfeit by", memberId, ":", drawingId
	Db.shared.set 'drawings', drawingId, 'members', memberId, -2
	Db.shared.set 'scores', memberId, drawingId, 0

exports.client_getWord = (drawingId, cb) !->
	if Db.shared.get 'drawings', drawingId, 'members', App.memberId()
		wordId = Db.shared.get 'drawings', drawingId, 'wordId'
		word = WordList.getWord wordId, false
		cb.reply word
	else # you haven't even guessed! no word for you.
		cb.reply false