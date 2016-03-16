App = require 'app'
Comments = require 'comments'
Db = require 'db'
Event = require 'event'
{tr} = require 'i18n'

Config = require 'config'
Letters = require 'letters'
WordList = require 'wordLists'

jiffy = 10

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

decodeOld = (data) ->
	decodeStep = (step) ->
		r = {} #TXXXYYYttttt
		type = 0|step[0]
		r.type = ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'][type] # first char
		if r.type in ['move', 'draw', 'dot']
			r.x = 0|step.substr(1,3)
			r.y = 0|step.substr(4,3)
			lastX = r.x
			lastY = r.y
		else if r.type is 'col'
			r.col = '#' + step.substr(1,6)
		else if r.type is 'brush'
			r.size = 0|step.substr(1,6)
		if type > 4 # clear or undo
			r.time = (0|step.substr(1,5))
		else
			r.time = (0|step.substr(7,5))

		return r

	r = []
	data = data.split(';')
	for step in data
		r.push decodeStep(step)
	return r

encode = (data) ->
	lastTime = 0
	lastX = 338 # never change these!
	lastY = 434 # never change these!

	# Draw encoding is the following:
	# A datapoint has 3-7 characters. We use the charcodes -32 (first 32 are not handy to use)
	# First char charcode (32-126) if the delta time since last datapoint.
	# Second char for the deltaX.
	#	if that char is 136 (~) the value is 47 (or -47) plus the next char.
	#	same for the possible next char (with +94)
	#	the last char is signed with -47 for negative values.
	# Then the same for the deltaY.

	# Example 1: !aC decodes to:
	#	! = 33-32 (actii offset) = 1 delta time (times jiffy is 10ms)
	#	a = 97-32 (ascii offset) = 65 -47 (signing) = 18
	#	C = 43-32 (ascii offset) = 11 -47 (signing) = -36

	# Example 2: H~~G~p decodes to:
	#	H = 72-32 = 40 delta time (times jiffy is 400ms)
	#	~ = add 47 to next value
	#	~ = add 47 to next value
	#	G = 71-32 = 39 -47 (signing) = -8. -8-47-47 = -102
	#	~ = add 47 to next value
	#	p = 112-32 = 80 -47 (signing) = 33. 33+47 = 80
	encodeStep = (step) -> # draw is done more efficient
		r = ""
		# log step, lastTime
		deltaTime = step.time-lastTime
		deltaX = Math.round(step.x) - lastX
		deltaY = Math.round(step.y) - lastY

		# if time, or coordinates are too big (or too small) use normal encoding
		if deltaTime >= 931 # too big deltaTime!
			doOther = true
		if deltaX >= 141 or deltaX <= -141# too big or small deltaX!
			doOther = true
		if deltaY >= 141 or deltaY <= -141# too big or small deltaX!
			doOther = true
		if doOther # do that
			return encodeOther (step)

		r += String.fromCharCode(Math.ceil(deltaTime/jiffy)+32) # write time

		# if a coordinate is to big (or too small) use the next char.
		x = Math.abs(deltaX)
		while x>47
			r += '~' # 126
			x -= 47
		r+=String.fromCharCode((deltaX%47)+47+32)

		y = Math.abs(deltaY)
		while y>47
			r += '~' # 126
			y -= 47
		r+=String.fromCharCode((deltaY%47)+47+32)

		# encode drawing
		# log "draw:", deltaTime, deltaX, deltaY, "(", lastX, lastY, ")"

		lastX += deltaX
		lastY += deltaY
		lastTime = step.time

		return r

	encodeOther = (step) -> # anything else
		deltaTime = step.time-lastTime
		r = ""
		r += String.fromCharCode(94+32) # max time flags 'other'

		# type
		r += ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'].indexOf(step.type)
		# value
		if step.x
			r += ("000" + Math.round(step.x)).substr(-3)
			lastX = Math.round(step.x)
		if step.y
			r += ("000" + Math.round(step.y)).substr(-3)
			lastY = Math.round(step.y)
		if step.size then r += ("000000" + step.size).substr(-6)
		if step.col then r += (""+step.col).substr(1) # skip the hash of colors
		# time
		r += ("00000" + Math.ceil(deltaTime/jiffy)).substr(-5) # 5 chars is enough.

		lastTime = step.time
		# log step.time, ": ", r
		return r

	r = ""
	for step in data
		if step.type is 'draw'
			r += encodeStep(step)
		else
			r += encodeOther(step)
	return r

exports.onUpgrade = !->
	wordObj = WordList.getRndWordObjects 1, false # get one word
	if wordObj
		Db.shared.set "outOfWords", false
		log "update: we have words available"
	else
		Db.shared.set "outOfWords", true
		log "update: still out of words"

	log "re-encoding sketches"
	Db.shared.iterate 'drawings', (drawing) !->
		data = drawing.get 'steps'
		return unless data[12] is ';' # only old stuff has seperators
		data = decodeOld(data)
		data = encode(data)
		drawing.set 'steps', data
		log "converted", drawing.key()



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
	log "add Drawing called by:", App.memberId(), ":", id, time, "lastDrawing:", (personalDb.get 'lastDrawing', 'id')
	return unless id and steps and time # we need these
	return unless 0|(personalDb.get 'lastDrawing', 'id') is 0|id

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