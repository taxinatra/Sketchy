{tr} = require 'i18n'

Config = require 'config'
Letters = require 'letters'
WordList = require 'wordLists'
Encoding = require 'encoding'

# Storage overview
# Personal:
#	<drawingId>: <time guessed>
#	words:
#		<drawingId>: <display word>
#	pause:
#		<drawingId>: <time paused>
#	lastDrawing:
#		id, prefix, word, wordId, time

# Shared:
#	language: <EN|NL|..>
#	outOfWords: <true|false>
#	dataVersion: <int>
#	roundId: <id>
#	roundEndDate: <epoch>
#	rounds:
#		<roundId>:
#			endDate: <epoch>
#			sketches: <nr of sketches>
#			winners: [ids]
#			scores:
#				<memberId>: <score>
#	drawingCount: <index for the next new drawing>
#	drawings:
#		<drawingId>:
#			_comments: <comments store>
#			wordId: <en1_123>
#			memberId: <artist Id>
#			time: <epoch sketch submitted>
#			members: (people who guessed it)
#				<memberId>:
#					time: <time they needed to guess in ms>
#					posted: <timestamp when time was submitted>
#	scores:
#		<memberId>:
#			<drawingId>: <score>

# Backend:
#	sketches:
#		<drawingId>:
#			word: <fence>
#			prefix: <a/an/"">
#			steps: <encoded drawing data>
#	archive:
#		<roundId>:
#			<drawingId>:
#				<same as drawings storage>

setLanguage = (lang) !->
	lang ||= Db.shared.get('language')
	if lang not in ['EN', 'NL', 'ES', 'FR', 'DE', 'IT']
		lang = 'EN'
	Db.shared.set 'language', lang
	log "Words language set to", lang

exports.onConfig = (config) !->
	# allowing language switching after app install is troublesome
	# Db.shared.set 'wordList', config['wordList']

exports.onInstall = (config) !->
	setLanguage config.language
	Db.shared.set 'dataversion', 4
	Db.shared.set 'roundId', 1
	scheduleRoundClose()

exports.onUpgrade = !->
	# check if we have words available
	wordObj = WordList.getRndWord()
	Db.shared.set "outOfWords", !wordObj

	# --------- one time only upgrade paths below --------
	# fix roundId issue
	if !Db.shared.isHash('rounds', 2) and Db.backend.isHash('archive', 2, 'drawings')
		round2 = {}
		scores = {}
		winners = []
		winningScore = 0
		for u in App.memberIds()
			t = 0
			t += s for d, s of Db.backend.get('archive', 2, 'scores', u)
			scores[u] = t
			continue if t is 0
			if t > winningScore
				winningScore = t
				winners = [u]
			else if t is winningScore
				winners.push u

		lastDate = 0
		for i, s of Db.backend.get('archive', 2, 'drawings')
			if s.time > lastDate
				lastDate = s.time

		round2.scores = scores
		round2.winners = winners
		round2.endDate = lastDate
		round2.sketches = Object.keys(Db.backend.get('archive', 2, 'drawings')||{}).length
		log "rebuilding round 2 meta"
		Db.shared.set 'rounds', 2, round2

	# fix sketches count
	for i, r of Db.shared.get('rounds')
		sketches = Object.keys(Db.backend.get('archive', i, 'drawings')||{}).length
		log "counting round", i, ":", sketches
		Db.shared.set 'rounds', i, 'sketches', sketches

	# if Db.shared.get('dataversion') < 5
	#   Db.shared.set 'dataversion', 5


assign = (obj, path) !->
	value = path.pop()
	for p, i in path
		obj[p] = {} unless obj[p] instanceof Object
		if i is path.length-1
			obj[p] = value # assign
		else
			obj = obj[p]

setPoints = (drawingId) !->
	drawing = Db.shared.ref 'drawings', drawingId
	# first, order members by reverse time
	members = []
	drawing.forEach 'members', (member) !->
		members.push {id: member.key(), time: member.get('time')}
	members.sort (a, b) ->
		if +b.time < 0 then return 9999
		if +a.time < 0 then return -9999
		b.time - a.time # inverse

	scoresPatch = {} # we use this to batch the db writes to a single merge
	artistPoints = 0 # artist get points equal to smart people
	# set points according to their place in the sorted array
	for member, i in members
		if member.time >=0
			assign scoresPatch, [member.id, drawingId, i+1]
			artistPoints++ # points for ppl guessed
		else
			assign scoresPatch, [member.id, drawingId, 0]
	assign scoresPatch, [drawing.get('memberId'), drawingId, artistPoints]

	Db.shared.merge 'scores', scoresPatch

getScoresAndWinners = ->
	scores = {}
	winners = []
	winningScore = 0
	for u in App.memberIds()
		t = 0
		t += s for d, s of Db.shared.get('scores', u)
		scores[u] = t
		continue if t is 0
		if t > winningScore
			winningScore = t
			winners = [u]
		else if t is winningScore
			winners.push u
	[winners, scores]

exports.client_seenNudge = (nr) !->
	Db.personal().set 'seen', 'nudge'+nr, true

exports.client_scheduleNewRound = !->
	now = App.time()
	return if Db.shared.get('roundStartDate') and Db.shared.get('roundStartDate')< now
	nextDayStart = ( Math.floor(now/86400) + 1 )*86400 + ((new Date).getTimezoneOffset() * 60) # to UTC time
	startDate = nextDayStart + (10*3600) + Math.floor(Math.random()*(4*3600)) # between 10:00 and 14:00
	Timer.cancel('remindRound')
	Timer.cancel('closeRound')
	Timer.cancel('newRound')
	Timer.set 0|((startDate-now)*1000), 'newRound' # a day in advance
	Db.shared.set 'roundStartDate', startDate
	log "(#{App.userId()}) Next round scheduled to begin at", startDate

exports.remindRound = !->
	# filter on active users
	lastWeek = 0|(App.time() - 3*24*3600) # well, three days...
	activeMembers = Object.keys(Db.shared.get('scores') || {}) # just the users who did anything this round
	log "sending round reminders"
	roundId = Db.shared.get('roundId')
	Comments.post
		lowPrio: 'none'
		highPrio: activeMembers
		s: 'roundReminder'
		v: roundId
		pushText: tr("Round %1 will close in a day!", roundId)
		path: '/?comments'

exports.client_closeRound = (password) !-> # for tests
	if Encoding.simpleHash(password) is -1898985179
		exports.closeRound()

exports.closeRound  = !->
	thisRound = Db.shared.get('roundId') || 1
	log "round", thisRound, "is now closed"

	# close round
	Db.shared.set "roundClosed", true

	# filter on active users and winners
	[winners, scores] = getScoresAndWinners()
	activeMembers = []
	lastWeek = 0|(App.time() - 3*24*3600) # well, three days...
	for k, activeTime of Db.backend.get 'lastActive'
		activeMembers.push(k) if activeTime > lastWeek

	if winners.length is 0
		names = "no one"
	else if winners.length is App.memberIds().length
		names = 'everyone' # yeah, that could happen
	else
		names = (App.memberName(id) for id in winners)
		names = names.join(', ')
		names = names.replace /, (?=\w+$)/, ' and '

	Comments.post
		lowPrio: 'none'
		highPrio: activeMembers
		s: 'roundClosed'
		v: Db.shared.get('roundId')
		names: names
		pushText: "#{names} won this round!"
		path: '/?comments'

	# note in rounds
	Db.shared.set 'rounds', thisRound,
		winners: winners
		scores: scores
		endDate: Db.shared.get('roundEndDate')
		sketches: Object.keys(Db.shared.get('drawings')||{}).length

exports.client_newRound = (password) !-> # for tests
	if Encoding.simpleHash(password) is -1898985179
		exports.newRound()

exports.newRound = !->
	lastRound = Db.shared.get('roundId') || 1
	thisRound = lastRound + 1
	Db.shared.set 'roundId', thisRound
	log "round", thisRound, "is upon us"

	# move drawings store to archive
	Db.backend.set 'archive', lastRound, 'drawings', (Db.shared.get('drawings')||{})
	Db.backend.set 'archive', lastRound, 'scores', Db.shared.get('scores')
	Db.backend.iterate 'archive', lastRound, 'drawings', (a) !->
		prefix = Db.backend.get 'sketches', a.key(), 'prefix'
		word = Db.backend.get 'sketches', a.key(), 'word'
		if prefix then word = prefix + ' ' + word
		a.set 'word', word

	# trash data
	log "trashing all old shared and personal data"
	Db.shared.remove 'drawings'
	Db.shared.remove 'scores'
	Db.shared.remove 'outOfWords'
	Db.backend.remove 'inUse'
	Db.personal(u).set(null) for u in App.memberIds()

	Db.shared.set "roundClosed", false
	Db.shared.set "roundStartDate", false

	scheduleRoundClose()

	roundId = Db.shared.get('roundId')
	Comments.post
		s: 'roundNew'
		v: roundId
		pushText: tr("Round %1 has started!", roundId)
		path: '/?comments'
		highPrio: true

scheduleRoundClose = (duration=Config.roundtime()) !->
	# schedule round closing
	now = App.time()
	nextDayStart = ( Math.floor(now/86400) + Math.max(1, duration) )*86400 + ((new Date).getTimezoneOffset() * 60) # to UTC time
	endDate = nextDayStart + (10*3600) + Math.floor(Math.random()*(12*3600)) # between 10 am and 10 pm
	Timer.cancel('remindRound')
	Timer.cancel('closeRound')
	Timer.cancel('newRound')
	Timer.set 0|((endDate-now-(24*3600))*1000), 'remindRound' # a day in advance
	Timer.set 0|((endDate-now)*1000), 'closeRound'
	Db.shared.set 'roundEndDate', endDate
	log "Round will close at:", endDate

addWordToPersonal = (memberId, drawingId) !->
	# Db.backend.get 'words', drawingId
	wordId = Db.shared.get 'drawings', drawingId, 'wordId'
	word = Db.backend.get 'sketches', drawingId, 'word'
	prefix = Db.backend.get 'sketches', drawingId, 'prefix'
	value = if prefix then prefix + " " + word else word
	Db.personal(memberId).set('words', drawingId, value)

setLastActive = (memberId) !->
	Db.backend.set 'lastActive', memberId, 0|App.time()

considerCriticalMass = (id, artistId = 0) !->
	# count last active
	if id then artistId = Db.shared.get 'drawings', id, 'memberId'
	lastWeek = 0|(App.time() - 3*24*3600) # well, three days...
	activeMembers = 0
	for k, activeTime of Db.backend.get 'lastActive'
		activeMembers++ if activeTime > lastWeek
	if activeMembers <2 then activeMembers = 2 # at least two. (you and future members)

	#if number of people guessed this drawing is 2/3 or more
	if id?
		m = Object.keys(Db.shared.get('drawings', id, 'members')||{}).length
		m++ # we count the artist as well
	else
		m = 1
	if m > activeMembers*Config.guessRatio()
		Db.personal(artistId).set 'wait', 0
		Db.personal(artistId).set 'waitGuessed', 0
	else
		Db.personal(artistId).set 'waitGuessed', m = Math.ceil(activeMembers*Config.guessRatio()-m)
	# log artistId, ".", m, '/',activeMembers,"members have guessed."

exports.client_startDrawing = (cb) !->
	if Db.shared.get 'roundClosed'
		cb.reply false
	personalDb = Db.personal App.memberId()
	lastDrawing = personalDb.get('lastDrawing')||false

	if !lastDrawing or personalDb.get('wait')+Config.cooldown() < App.time() # first or at least 12 hours ago

		wordObj = WordList.getRndWord()
		log "#{App.memberId()}: startDrawing", JSON.stringify(wordObj)
		if not wordObj
			Db.shared.set "outOfWords", true
			cb.reply "out of words"
			return

		id = Db.shared.get('drawingCount')||0

		lastDrawing = wordObj
		lastDrawing.id = id
		lastDrawing.time = 0|App.time()
		personalDb.set 'lastDrawing', lastDrawing
		if Db.shared.peek('drawings') # the first sketch is time free
			personalDb.set 'wait', lastDrawing.time
			considerCriticalMass null, App.memberId()

		Db.backend.set('inUse', lastDrawing.wordId, 0|App.time())

		cb.reply lastDrawing
	else
		cb.reply false # no no no, you don't get to try again.

exports.client_addDrawing = (id, steps, time) !->
	personalDb = Db.personal App.memberId()
	log "#{App.memberId()}: addDrawing (#{id}):", time
	unless id? and steps and time # we need these
		log "No id, steps and/or time!"
		return
	unless 0|(personalDb.get 'lastDrawing', 'id') is 0|id
		log "lastDrawing id != id: ", (personalDb.get 'lastDrawing', 'id'), 'vs', id
		return

	currentDrawing = personalDb.get 'lastDrawing'
	wordId = currentDrawing.wordId
	id = Db.shared.incr('drawingCount') - 1

	# test steps
	if not Encoding.test(steps)
		log "Sketch did not pass the test"
		personalDb.set 'wait', 0 # give the author his time back
		return # don't write it to the db

	# finished drawing, so let's get it out of the personal db and into the shared!
	Db.shared.set 'drawings', id,
		memberId: App.memberId()
		wordId: wordId
		time: time
	Db.backend.set 'sketches', id,
		'word': WordList.getWord(wordId)
		'prefix': WordList.getPrefix(wordId)
		'steps': steps

	Db.backend.remove('inUse', wordId)

	addWordToPersonal App.memberId(), id
	personalDb.set 'wait', 0|App.time()

	# notify
	high = 'all'
	low = null
	if id > 1 # not the first drawing
		high = []
		low = []
		# include members who are up to date with the sketches
		for member in App.memberIds()
			if Object.keys(Db.shared.get('drawings')).length-1 is Object.keys(Db.shared.get('scores', member)||[]).length
				high.push member
			else
				low.push member
	Event.create
		text: App.userName() + " added a new sketch"
		path: '/'
		lowPrio: true
		highPrio: high

exports.client_requestDrawing = (cb, requestOnly) !-> # request to guess
	memberId = App.memberId()
	drawings = []

	# check if not currently guessing
	if cId = Db.personal(memberId).get('lastGuessed')
		if Db.shared.get('drawings', cId, 'members', memberId) is -1
			log "#{memberId}: requestDrawing, continuing with", cId
			cb.reply cId # continue with guessing
			return

	if Db.shared.get 'roundClosed'
		cb.reply null

	Db.shared.forEach 'drawings', (drawing) !->
		unless (drawing.get('memberId') is memberId) or drawing.get('members', memberId)
			# skip drawings made or guessed by user
			drawings.push
				id: drawing.key()
				count: Object.keys((drawing.get('members')||{})).length

	drawings.sort (a, b) ->
		if a.count is b.count
			return a.time - b.time # take oldest
		return a.count - b.count # take lowest

	# makes this a function to check whether any more drawings are available
	# (as the function name would actually suggest...)
	if requestOnly
		cb.reply !!drawings.length
		return

	if drawings.length # got a drawing to guess!
		log "#{memberId}: requestDrawing (" + drawings.length + "):", drawings[0].id
		# note down that the user started guessing. But don't note the time yet. that is done with getLetters.
		Db.personal(memberId).set 'lastGuessed', drawings[0].id
		Db.shared.set 'drawings', drawings[0].id, 'members', memberId,
			time: -1
			posted: Date.now()

		cb.reply drawings[0].id
	else # out of drawings!
		log "#{memberId}: requestDrawing (" + drawings.length + "): none left!"
		# in this case, the words in personal storage doesn't match up with entrees in the shared.drawings.id.members
		# this could be the case if you start guessing a sketch, leave, and never return. (in the old style)
		Db.shared.forEach 'drawings', (drawing) !->
			if (drawing.get('memberId') is memberId) or drawing.get('members', memberId)
				# skip drawings made or guessed by user
				addWordToPersonal memberId, drawing.key()
		cb.reply null

exports.client_startGuessing = (drawingId, time, cb) !->
	unless cb # we really need a callback
		return
	unless drawingId and time # we need these as well
		cb.reply null
		return null
	unless Db.shared.get 'drawings', drawingId, 'wordId' # drawing exists?
		cb.reply null
		return null

	wordId = Db.shared.get 'drawings', drawingId, 'wordId'
	word = Db.backend.get 'sketches', drawingId, 'word'
	word = WordList.process word
	memberId = App.memberId()
	timestamp = Date.now()

	# Timelords not allowed.
	storedTime = Db.personal(memberId).get(drawingId)
	# startTime = storedTime||time # either old startTime or current
	startTime = storedTime||timestamp # either old startTime or current server time
	log "#{memberId}: startGuessing (" + drawingId + "): personal time:", storedTime||'null',", givenTime:", time, ", serverTime:", timestamp, ", delta:", timestamp-startTime
	if timestamp < startTime and timestamp > startTime + Config.guessTime()*2
		submitForfeit drawingId, "start guessing time out of bounds"
		cb.reply "time"
		return null
	unless word # we need a word
		cb.reply null
		return null
	# already submitted an answer
	if (Db.shared.get('drawings', drawingId, 'members', memberId, 'time')||-1) isnt -1
		log "#{memberId}: already submitted (" + drawingId + ")"
		cb.reply null
		return null

	# write down when a user has started guessing
	Db.personal(memberId).set drawingId, startTime
	Db.personal(memberId).set 'lastGuessed', +drawingId
	Db.shared.set 'drawings', drawingId, 'members', memberId,
		time: -1
		posted: Date.now()
	# set failed score. You can better this by providing the correct answer
	Db.shared.set 'scores', memberId, drawingId, 0

	# some random letters
	letters = Letters.getRandom 14-word.length
	letters.push c for c in word
	scrambledLetters = {}
	for letter, i in letters.sort()
		scrambledLetters[i] = [letter, i]
	scrambledLetters.count = letters.length

	# We won't send the word, but an array of word lengths and a hash of it
	hash = Encoding.simpleHash(word)
	# fields = WordList.getFields(wordId) # we no longer have multiple words in one answer
	fields = [word.length]
	steps = Db.backend.get 'sketches', drawingId, 'steps'

	setLastActive memberId

	cb.reply fields, hash, scrambledLetters, steps, Encoding.simpleHash(steps), storedTime

exports.client_submitAnswer = (drawingId, answer, time) !->
	memberId = App.memberId()
	return unless drawingId and answer and time # we need these
	return unless Db.shared.get('drawings', drawingId) # if the sketch exists

	# Timelords not allowed.
	duration = Date.now() - Db.personal(memberId).get drawingId||0
	log "#{memberId}: submit answer (" + drawingId + ") answer:", answer, ", time:", time, ", duration:", duration
	if duration < 0 or duration > Config.guessTime()*4
		submitForfeit drawingId, "answer submit time out of bounds"
		return

	drawing = Db.shared.ref 'drawings', drawingId
	word = Db.backend.get 'sketches', drawingId, 'word'

	if WordList.process(word) is WordList.process(answer) # correct!
		drawing.set 'members', memberId,
			time: time
			posted: Date.now()
		addWordToPersonal memberId, drawingId

		setPoints drawingId

		Event.create
			path: [drawingId]
			text: 'none'
			lowPrio: drawing.get('memberId')

	else # incorrect
		log "answer was not correct",  word, 'vs', answer.replace(/\s/g, '')
		submitForfeit drawingId, "incorrect answer given"

	Db.personal(memberId).remove 'pause'

	setLastActive memberId
	considerCriticalMass drawingId

exports.client_submitForfeit = submitForfeit = (drawingId, reason="no reason given") !->
	memberId = App.memberId()
	log "#{memberId}: submit forfeit:", drawingId, ":", reason
	Db.shared.set 'drawings', drawingId, 'members', memberId,
		time: -2
		posted: Date.now()
	setPoints drawingId
	addWordToPersonal memberId, drawingId

	# generate sysMessage
	# log "generate sysMessage: failed"
	# Comments.post # no push notification
	# 	store: ['drawings', drawingId, 'comments']
	# 	u: memberId
	# 	s: 'failed'

	Db.personal(memberId).remove 'pause'

	setLastActive memberId
	considerCriticalMass drawingId

exports.client_setPause = (drawingId, pauseTime) !->
	Db.personal(App.memberId()).set 'pause', drawingId, pauseTime

exports.client_getWord = (drawingId, cb) !->
	drawingR = Db.shared.ref 'drawings', drawingId
	artist = drawingR.get 'memberId'
	time = drawingR.get 'members', App.memberId(), 'time'
	if (artist is App.memberId()) or (time and time isnt -1) # -1 is 'currently guessing'
		word = Db.backend.get 'sketches', drawingId, 'word'
		cb.reply word
	else # you haven't even guessed! no word for you.
		cb.reply false

exports.client_getSteps = (drawingId, cb) !->
	drawingR = Db.shared.ref 'drawings', drawingId
	artist = drawingR.get 'memberId'
	time = drawingR.get 'members', App.memberId(), 'time'
	if (artist is App.memberId()) or time
		cb.reply (Db.backend.get 'sketches', drawingId, 'steps')
	else # you haven't done anything with this sketch. no steps for you.
		cb.reply false

# getSteps checks if the users has the right to obtain the info. For archived steps we simply test if it is archived.
exports.client_getArchivedSteps = (drawingId, archiveRound, cb) !->
	if Db.backend.isHash 'archive', archiveRound, 'drawings', drawingId
		cb.reply (Db.backend.get 'sketches', drawingId, 'steps')
	else
		log "Sketch not found in the archive"
		cb.reply false

exports.client_getArchive = (roundId, cb) !->
	if roundId? and a = Db.backend.get('archive', roundId)
		log "client_getArchive called with", roundId
		cb.reply a
