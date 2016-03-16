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
#			wordId: <en1_123>
#			members:
#				<memberId>: <time they needed to guess in sec>
#	scores:
#		<memberId>:
#			<drawingId>: <score>

# Backend:
#	words:
#		<drawingId>:
#			word: <fence>
#			prefix: <a/an/"">

exports.onUpgrade = !->
	wordObj = WordList.getRndWordObjects 1, false # get one word
	if wordObj
		Db.shared.set "outOfWords", false
		log "update: we have words available"
	else
		Db.shared.set "outOfWords", true
		log "update: still out of words"

	# reset words in personal storage
	# for memberId in App.memberIds()
	# 	log "adding words", memberId
	# 	for drawingId, word of Db.personal(memberId).get('words')
	# 		addWordToPersonal memberId, drawingId

exports.onConfig = exports.onInstall = (config) !->
	Db.shared.set 'wordList', config['wordList']

addWordToPersonal = (memberId, drawingId) !->
	# Db.backend.get 'words', drawingId
	wordId = Db.shared.get 'drawings', drawingId, 'wordId'
	word = Db.backend.get 'words', drawingId, 'word'
	prefix = Db.backend.get 'words', drawingId, 'prefix'
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

setLastActive = (memberId) !->
	Db.shared.set 'lastActive', memberId, 0|Date.now()*.001

considerCriticalMass = (id, artistId = 0) !->
	# count last active
	if id then artistId = Db.shared.get 'drawings', id, 'memberId'
	lastWeek = 0|(Date.now()*.001 - 7*24*3600)
	activeMembers = 0
	for k, activeTime of Db.shared.get 'lastActive'
		activeMembers++ if activeTime > lastWeek
	if activeMembers <2 then activeMembers = 2 # at least two. (you and future members)

	#if number of people guessed this drawing is 2/3 or more
	if id?
		m = Object.keys(Db.shared.get 'drawings', id, 'members').length
		m++ # we count the artist as well
	else
		m = 1
	if m > activeMembers*Config.guessRatio()
		Db.personal(artistId).set 'wait', 0
		Db.personal(artistId).set 'waitGuessed', 0
	else
		Db.personal(artistId).set 'waitGuessed', m = Math.ceil(activeMembers*Config.guessRatio()-m)
	log artistId, ".", m, '/',activeMembers,"members have guessed."

exports.client_addDrawing = (id, steps, time) !->
	personalDb = Db.personal App.memberId()
	#return if (personalDb.get 'currentDrawing') isnt id

	currentDrawing = personalDb.get 'lastDrawing'
	wordId = currentDrawing.wordId

	log "add Drawing", App.memberId(), wordId

	# finished drawing, so let's get it out of the personal db and into the shared!
	Db.shared.set 'drawings', id,
		memberId: App.memberId()
		wordId: wordId
		steps: steps
		time: time
	Db.backend.set 'words', id, 'word', WordList.getWord(wordId, false)
	Db.backend.set 'words', id, 'prefix', WordList.getPrefix(wordId)

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


	if !lastDrawing or personalDb.get('wait')+Config.cooldown() < Date.now()*.001 # first or at least 4 hours ago

		wordObj = WordList.getRndWordObjects 1, false # get one word
		log "start Drawing", App.memberId(), JSON.stringify(wordObj)
		if not wordObj
			Db.shared.set "outOfWords", true
			cb.reply "out of words"
			return

		id = Db.shared.get('drawingCount')||0
		Db.shared.incr 'drawingCount'

		lastDrawing = wordObj
		lastDrawing.id = id
		lastDrawing.time = 0|Date.now()*.001
		personalDb.set 'lastDrawing', lastDrawing
		personalDb.set 'wait', lastDrawing.time
		considerCriticalMass null, App.memberId()
		cb.reply lastDrawing
	else
		cb.reply false # no no no, you don't get to try again.


exports.client_getLetters = (drawingId, cb) !->
	wordId = Db.shared.get 'drawings', drawingId, 'wordId'
	word = Db.backend.get 'words', drawingId, 'word'
	word = WordList.process word
	memberId = App.memberId()
	timestamp = Date.now()

	# Timelords not allowed.
	startTime = Db.personal(memberId).get(drawingId)||timestamp # either old startTime or current
	log "get letters for",drawingId,"by",memberId,": personal time:", Db.personal(memberId).get(drawingId),"now:", timestamp, " - ", 0, timestamp-startTime, Config.guessTime()*2
	if timestamp < startTime and timestamp > startTime + Config.guessTime()*2
		submitForfeit (drawingId)
		cb.reply "time"
		return null
	unless word # we need a word
		cb.reply null
		return null
	# already submitted an answer
	if (Db.shared.get('drawings', drawingId, 'members', memberId)||-1) isnt -1
		log "member", memberId, "already submitted", drawingId
		cb.reply null
		return null

	# write down when a user has started guessing
	Db.personal(memberId).set drawingId, startTime
	# set failed score. You can better this by providing the correct answer
	Db.shared.set 'drawings', drawingId, 'members', memberId, -1
	Db.shared.set 'scores', memberId, drawingId, 0

	# some random letters
	letters = Letters.getRandom 14-word.length
	letters.push c for c in word
	scrambledLetters = {}
	for letter, i in letters.sort()
		scrambledLetters[i] = [letter, i]
	scrambledLetters.count = letters.length

	# We won't send the word, but an array of word lengths and a hash of it
	hash = Config.simpleHash(word)
	fields = WordList.getFields(wordId)

	setLastActive memberId

	cb.reply fields, hash, scrambledLetters

exports.client_submitAnswer = (drawingId, answer, time) !->
	memberId = App.memberId()
	return unless drawingId and answer and time # we need these

	# Timelords not allowed.
	duration = Date.now() - Db.personal(memberId).get drawingId||0
	log "submitAnswer by", memberId, ":", drawingId, answer, time, duration
	if duration < 0 or duration > Config.guessTime()*2
		submitForfeit (drawingId)
		return

	drawing = Db.shared.ref 'drawings', drawingId
	word = Db.backend.get 'words', drawingId, 'word'
	if WordList.process(word) is WordList.process(answer) # correct!
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
		addWordToPersonal memberId, drawingId

		# notify artist
		if best
			prefix = Db.backend.get 'words', drawingId, 'prefix'
			word = if prefix then prefix + " " + word else word
			Event.create
				path: "/#{drawingId}?comments"
				text: tr("%1 guessed your drawing of %2 the fastest with %3 seconds.", App.memberName(memberId), word, time)
				for: [drawing.get('memberId')]

		# generate sysMessage
		Comments.post # no push notification
			store: ['drawings', drawingId, 'comments']
			u: memberId
			s: 'correct'
			value: time
	else
		log "answer was not correct",  word, 'vs', answer.replace(/\s/g, '')
		submitForfeit (drawingId)

	setLastActive memberId
	considerCriticalMass drawingId

exports.client_submitForfeit = submitForfeit = (drawingId) !->
	memberId = App.memberId()
	log "submitForfeit by", memberId, ":", drawingId
	Db.shared.set 'drawings', drawingId, 'members', memberId, -2
	Db.shared.set 'scores', memberId, drawingId, 0
	addWordToPersonal memberId, drawingId

	# generate sysMessage
	log "generate sysMessage: failed"
	Comments.post # no push notification
		store: ['drawings', drawingId, 'comments']
		u: memberId
		s: 'failed'

	setLastActive memberId
	considerCriticalMass drawingId

exports.client_getWord = (drawingId, cb) !->
	drawingR = Db.shared.ref 'drawings', drawingId
	artist = drawingR.get 'memberId'
	time = drawingR.get 'members', App.memberId()
	if (artist is App.memberId()) or (time and time isnt -1) # -1 is 'currently guessing'
		word = Db.backend.get 'words', drawingId, 'word'
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