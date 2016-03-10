App = require 'app'
Comments = require 'comments'
Db = require 'db'
Event = require 'event'
{tr} = require 'i18n'

Config = require 'config'
Letters = require 'letters'
WordList = require 'wordLists'

# Storage overview
# Personal:
#	<drawingId>: <time guessed>
#	words:
#		<drawingId>: <display word>

# Shared:
#	drawings:
#		<drawingId>:
#			Stuff about time and author
#			steps: <data in string>
#			members:
#				<memberId>: <time they needed to guess in sec>

#	scores:
#		<memberId>:
#			<drawingId>: <score>

exports.onUpgrade = !->
	wordObj = WordList.getRndWordObjects 1, false # get one word
	if wordObj
		Db.shared.set "outOfWords", false
		log "update: we have words available"
	else
		Db.shared.set "outOfWords", true
		log "update: still out of words"

addWordToPersonal = (memberId, drawingId) !->
	wordId = Db.shared.get 'drawings', drawingId, 'wordId'
	word = WordList.getWord wordId, false
	prefix = WordList.getPrefix(wordId)
	value = if prefix then prefix + " " + word else word
	Db.personal(memberId).set('words', drawingId, value)

membersToNotify = (id) ->
	return 'all' if id <= 1
	r = [Db.shared.get('drawings', id, 'memberId')] # add the artist
	lastMembers = Db.shared.get('drawings', id, 'members')||false
	return r if lastMembers is false
	# include members who guessed last drawing
	((r.push id) if id of lastMembers) for id in App.memberIds()
	return r

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

	addWordToPersonal App.memberId(), id

	# notify
	f = membersToNotify id-1
	if f isnt 'none'
		Event.create
			text: App.userName() + " added a new drawing"
			path: '/'
			for: f

	# silent notify the rest
	return if f is 'all'
	if f is 'none'
		f = 'all'
	else
		f = (-v for v in f) # inverse the array
	Event.create
		push: false # silent
		text: ''
		for: f

exports.client_startDrawing = (cb) !->
	personalDb = Db.personal App.memberId()
	lastDrawing = personalDb.get('lastDrawing')||false

	if !lastDrawing or lastDrawing.time+(Config.cooldown()) < Date.now()*.001 # first or at least 4 hours ago

		wordObj = WordList.getRndWordObjects 1, false # get one word
		if not wordObj
			Db.shared.set "outOfWords", true
			cb.reply "out of words"
			return

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
	letters = Letters.getRandom 14-word.length
	letters.push c for c in word
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
	wordId = drawing.get('wordId')
	word = WordList.getWord wordId
	if word is answer.replace(/\s/g,'') # correct!
		# set artist's score if we have the highest
		best = true
		drawing.iterate 'members', (member) !->
			# log "comparing my", time, "to", member.get(), ":", (time > member.get() and member.get()>=0)
			best = false if time > member.get() and member.get()>=0 # skip -1/-2 timings
		if best
			log "we're the best. so score:", drawing.get('memberId'), Config.timeToScore(time)
			Db.shared.set 'scores', drawing.get('memberId'), drawingId, Config.timeToScore(time)

		# write own time and score
		drawing.merge('members', {}) # make sure path exists
		drawing.set('members', memberId, time)
		Db.shared.set 'scores', memberId, drawingId, Config.timeToScore(time)
		addWordToPersonal memberId, drawingId

		# notify artist
		if best
			word = WordList.getWord wordId, false
			prefix = WordList.getPrefix(wordId)
			word = if prefix then prefix + " " + word else word
			Event.create
				path: "/#{drawingId}"
				text: tr("%1 guessed your drawing of %2 the fastest with %3 seconds.", App.memberName(memberId), word, time)
				for: [drawing.get('memberId')]
	else
		log "answer was not correct",  word, 'vs', answer.replace(/\s/g, '')
		submitForfeit (drawingId)

	# add notice to the comments thread

exports.client_submitForfeit = submitForfeit = (drawingId) !->
	memberId = App.memberId()
	log "submitForfeit by", memberId, ":", drawingId
	Db.shared.set 'drawings', drawingId, 'members', memberId, -2
	Db.shared.set 'scores', memberId, drawingId, 0
	addWordToPersonal memberId, drawingId

exports.client_getWord = (drawingId, cb) !->
	time = Db.shared.get 'drawings', drawingId, 'members', App.memberId()
	if time and time isnt -1 # -1 is 'currently guessing'
		wordId = Db.shared.get 'drawings', drawingId, 'wordId'
		word = WordList.getWord wordId, false
		cb.reply word
	else # you haven't even guessed! no word for you.
		cb.reply false

exports.client_post = (comment) !->
	drawingId = comment.store[1]
	f = [Db.shared.get 'drawings', drawingId, 'memberId'] # artist
	for k,v of Db.shared.get 'drawings', drawingId, 'members'
		f.push 0|k if v isnt -1
	comment.path = "/#{drawingId}?comments"
	comment.pushFor = f
	Comments.post comment