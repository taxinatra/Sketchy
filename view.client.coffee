App = require 'app'
Canvas = require 'canvas'
Comments = require 'comments'
Db = require 'db'
Dom = require 'dom'
Icon = require 'icon'
Modal = require 'modal'
Obs = require 'obs'
Page = require 'page'
Server = require 'server'
Time = require 'time'
Ui = require 'ui'
{tr} = require 'i18n'
Photo = require 'photo'

Config = require 'config'
Guess = require 'guess'

CANVAS_RATIO = Config.canvasRatio()

exports.renderPoints = renderPoints = (points, size, style=null) !->
	Dom.div !->
		Dom.style
			background: '#7b02ff'
			borderRadius: '50%'
			fontSize: (if points < 100 then (size*.5) else if points < 1000 then (size*.4) else (size*.3)) + 'px'
			textAlign: 'center'
			width: size+'px'
			height: size+'px'
			color: 'white'
			Box: 'middle center'
		if style then Dom.style style
		Dom.text points

exports.render = (sketchData = false, scoresData = false) !->
	falseNavigationO = Obs.create false
	Obs.observe !->
		if falseNavigationO.get()
			Ui.emptyText tr("It seems like you are not supposed to be here.")

	drawingId = Page.state.get(0)
	archiveMode = !!Page.state.get('round')
	log "render view, id", drawingId, "archive:", archiveMode, "sketchData", sketchData

	unless drawingId # if we have no id, error
		log 'No drawing Id'
		return
	# our data is a local Obs in archive mode or a ref to Db.share in normal mode.
	drawingR = if sketchData then Obs.create(sketchData) else Db.shared.ref('drawings', drawingId)
	scoresR = if scoresData then Obs.create(scoresData) else Db.shared.ref('scores')

	unless drawingR.peek('wordId')
		log "sketch no longer exists. darn."
		falseNavigationO.set true
		return
	myId = App.memberId()
	guessO = Obs.create false

	Page.setTitle tr("Sketch by %1", App.userName(drawingR.peek('memberId')))

	Dom.style minHeight: '100%'
	if archiveMode
		Dom.div !-> # dom obs
			Dom.style margin: 0, minHeight: '100%'
			log "renderResult in archive mode"
			renderResult(drawingId, drawingR, scoresR, drawingR.peek('word'))
		return # don't do any guessing state observing in archive mode.

	Obs.observe !->
		myTime = drawingR.get('members', myId, 'time')

		# score view is defined here. Guessing in guess.client.coffee
		log "main shared drawing (#{drawingId}) obs. me:", myId, "artist:", drawingR.get('memberId'), "myTime:", myTime
		# not my own drawing. not guessed, or busy guessing
		if myId isnt drawingR.get('memberId') and (!myTime? or myTime is -1)
			log "guessO set to true"
			guessO.set true
		else
			log "guessO set to false"
			guessO.set false

	Dom.div !-> # dom obs
		Dom.style margin: 0, minHeight: '100%'
		if guessO.get()
			preGuessing(drawingId)
		else
			renderResult(drawingId, drawingR, scoresR)

preGuessing = (drawingId) !->
	log "preGuessing. drawingId", drawingId
	falseNavigationO = Obs.create false
	Obs.observe !->
		if falseNavigationO.get()
			Ui.emptyText tr("It seems like you are not supposed to be here.")

	getTime = ->
		Date.now()-(Date.now()-App.time()*1000)
	now = getTime()

	localStorageO = Db.local.ref('currentlyGuessing')
	# have we already started or so we need to call the server?
	if (localStorageO.peek('id') is drawingId) and localStorageO.peek('startTime')
		log "Already got the goods, drawing guess screen"
		Guess.render(drawingId, localStorageO)
		return
	# if the time is too old, we can call for a forfeit here and predict that...

	# we have to observe the PS and call the server
	Obs.observe !->
		localStorageO.get()
		log "localStorageO obs", localStorageO.get('id'), localStorageO.get('startTime')
		if (localStorageO.get('id') is drawingId) and localStorageO.get('startTime')
			log "Got the goods, drawing guess screen"
			Guess.render(drawingId, localStorageO)

	getInfoRetryO = Obs.create 0
	Obs.observe !->
		getInfoRetryO.get() # trigger
		Server.sync 'startGuessing', drawingId, now, (_fields, _solutionHash, _letters, _steps, _stepsHash, _storedTime) !->
			log "startGuessing returned with time:", _storedTime
			if _fields is "time"
				# this is a state where we don't want to be. The server will have called a forfeit for us.
				log "Your time is up"
				return
			unless _fields
				log "got null/false from server. Word is either illegal, sketch no longer exists or we already guessed this sketching"
				falseNavigationO.set true
				return

			# state is good. continue
			myHash = Encoding.simpleHash(_steps)
			if myHash is _stepsHash
				log "steps check out! we're good to guess!", drawingId
				# set the time to now, so we can begin. This time is the true starting time. The server time is a window of opportunity.
				localStorageO.set
					'id': drawingId
					'startTime': _storedTime||getTime() # setting this means we have now started guessing.
						# we either continue with the time the server has given us (continue from other device) or set our new time.
						# note that the storedTime is the time we send the startGuessing RPC. So that will be before we would normally set the time here.
						# In other words: switching device while guessing gives a slight time penalty
					'fields': _fields
					'solutionHash': _solutionHash
					'letters': _letters
					'steps': _steps
			else
				log "stepsHash is not correct! Retry.", myHash, 'vs', _stepsHash
				if getInfoRetryO.peek() >= 3
					log "tried to many times. Steps is seriously corrupted server-side. Forfeiting this sketch"
					Server.call('submitForfeit', drawingId, "stepsHash invalid")
				else
					getInfoRetryO.incr()
		, !-> # sync
			log "waiting for rpc..."

renderResult = (drawingId, drawingR, scoresR, archiveWord=false) !->
	log "renderResult", drawingId, drawingR.peek(), scoresR.peek()
	myId = App.memberId()
	myTime = drawingR.get('members', myId, 'time')
	falseNavigationO = Obs.create false
	word = if archiveWord then archiveWord else Db.personal.get 'words', drawingId
	if word
		word = (/^([a-z]*\s)?(.*)$/i.exec word)[2]
	else
		log "You haven't guessed this question, but requested the answer. That's not very nice."
		falseNavigationO.set true
		return

	Db.personal.get 'words', drawingId # obs
	log "renderResult2", myTime, 'word:', Db.personal.peek 'words', drawingId

	# --- result screen ---

	backgroundO = Obs.create ""

	Obs.observe !->
		if falseNavigationO.get()
			Ui.emptyText tr("It seems like you are not supposed to be here.")

	Dom.style minHeight: '100%', background: "rgba(255, 255, 255, 1)", height: ''

	Dom.style
		Box: 'vertical center'
		textAlign: 'center'

	state = 0

	renderTop = (opts) !->
		Dom.div !->
			Dom.style minHeight: '72px', marginTop: '12px'
			Dom.h1 opts.header if opts.header
			Dom.text opts.content if opts.content
			if opts.content2
				Dom.br()
				Dom.br()
				Dom.text opts.content2

	renderAnswer = (drawingId) !->
		Dom.div !->
			Dom.style
				position: 'relative'
				width: '100%'
			Dom.h2 !->
				Dom.style
					fontSize: '28px'
					textTransform: 'uppercase'
					fontFamily: "Bree Serif"
					letterSpacing: '2px'
				Dom.text word

			Icon.render
				data: 'repeat'
				size: 28
				style:
					position: 'absolute'
					top: '3px'
					right: '6px'
					padding: '6px'
					_borderRadius: '50%'
				onTap: !->
					archiveRound = Page.state.peek('round')
					Page.nav !->
						Page.setTitle tr("Replay")
						stepsO = Obs.create false
						if archiveWord
							Server.call 'getArchivedSteps', drawingId, archiveRound, (steps) !->
								stepsO.set steps
						else
							Server.call 'getSteps', drawingId, (steps) !->
								stepsO.set steps
						Dom.div !->
							Dom.style
								margin: 0
								height: '100%'
								width: '100%'
								Box: "center midden"
								background: '#DDD'

							cvs = Canvas.render null # render canvas
							steps = stepsO.get()
							if not steps
								Ui.emptyText tr("Loading...")
								return

							steps = Encoding.decode(steps)
							startTime = Date.now()
							for step in steps then do (step) !->
								now = (Date.now() - startTime)
								if step.time > now
									Obs.onTime (step.time - now)/6, !->
										cvs.addStep step
								else
									cvs.addStep step

	renderScore = (drawingId) !->
		points = scoresR.get myId, drawingId
		Dom.div !->
			points = Db.shared.get('scores', myId, drawingId)
			Dom.style Box: 'vertical center', minHeight: '116px'
			Dom.text tr("This earned you")
			if points
				renderPoints(points, 60, {margin:'12px 12px 4px'}) # points, size, style
			Dom.text if points>1 then tr("points") else tr("point")

	Obs.observe !->
		if drawingR.get('memberId') is myId # my drawing
			arr = (v for k, v of drawingR.get('members'))
			points = scoresR.get myId, drawingId
			if arr.length and (arr[0].time||0) isnt -1
				if points is 0
					renderTop
						header: tr("Your sketch")
						content: tr("has not been successfully guessed yet")
					renderAnswer drawingId
				else if points is 1
					renderTop
						header: tr("Your sketch")
						content: tr("has been guessed by %1 person", points)
					renderAnswer drawingId
					renderScore drawingId
				else
					renderTop
						header: tr("Your sketch")
						content: tr("has been guessed by %1 people", points)
					renderAnswer drawingId
					renderScore drawingId
			else
				renderTop
					header: tr("Your sketch")
					content: tr("has not been guessed yet")
				renderAnswer drawingId
		else # you have guessed
			unless myTime # if we have no time, error
				falseNavigationO.set true
				return
			if myTime >= 0
				renderTop
					header: tr("Nice!")
					content: tr("It took you %1 seconds to guess:",
					(myTime*.001).toFixed(1))
				renderAnswer drawingId
				renderScore drawingId
			else # failed to guess
				renderTop
					header: tr("Too bad")
					content: tr("You have not guessed it correctly.")
					content2: tr("The correct answer was:")
				renderAnswer drawingId

	Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill
	Dom.div !->
		Dom.style textAlign: 'left', width:'100%', margin: 0, flexShrink: 0
		rendered = false
		drawingR.iterate 'members', (member) !->
			time = member.get('time')
			posted = member.get('posted')
			memberId = member.key()
			return if time is -1 # skip members who are currently guessing
			Dom.div !->
				if isNew = Event.isNew(posted*.001)
					Dom.style color: '#19b500'
				Ui.item
					prefix: !-> renderPoints(scoresR.get(memberId, drawingId)||0, 40, {marginRight:'12px'})
					avatar: App.memberAvatar(memberId)||'#ccc'
					content: App.memberName(memberId)
					afterIcon: !-> Dom.div !->
						Dom.style
							border: '1px solid #999'
							_borderRadius: '2px'
							padding: "4px 8px"
						if time >= 0
							Dom.text tr("%1 sec", (time*.001).toFixed(1))
						else
							Dom.text "failed"
					onTap: !->
						App.showMemberInfo(memberId)
				# if myTime > 0 and myTime < time and time >= 0 # If I beat you
				# 	Dom.transition
				# 		initial:
				# 			_transform: "translateY(-50px)"
				# 		_transform: "translateY(0px)"
				# 		time: 600
				# TODO: would be cool if older beaten scores move down to make space.
				return unless isNew
				Dom.transition
					initial:
						_transform: "translateX(-200px)"
						opacity: 0
					_transform: "translateX(0px)"
					opacity: 1
					time: 600
		, (member) ->
			s = member.peek('time')
			if s <0 then s = 999999
			return s
		rendered = true
	Dom.div !->	Dom.style Flex: true, minHeight: '16px' # fill

	Dom.div !->
		Dom.style width: '100%', textAlign: 'left', _boxSizing: 'border-box', ChildMargin: 12, margin: 0

		Comments.inline
			store: if archiveWord then ['comments'] else ['drawings', drawingId, 'comments']
			path: "/#{drawingId}?comments"
			seenBy: false
			messages:
				correct: (c) -> tr("%1 guessed this sketch in %2 seconds!", c.user, c.value)
				failed: (c) -> tr("%1 failed to guess this sketch", c.user)
			onSend: (comment) !->
				f = [Db.shared.peek 'drawings', drawingId, 'memberId'] # artist
				for k,v of Db.shared.peek 'drawings', drawingId, 'members'
					f.push 0|k if v.time isnt -1
				comment.lowPrio = false # don't send any noti to members who didn't guess it yet
				comment.normalPrio = f
			readStore: drawingR.ref() if archiveWord

		# am I currently guessing?
		curDrawingId = Db.personal.peek('lastGuessed')
		return if curDrawingId? and not Db.personal.peek('words', curDrawingId)?

		moreDrawingsO = Obs.create false
		Server.call 'requestDrawing', moreDrawingsO.func(), true # only checks if a drawing is available

		Obs.observe !->
			return if Page.keyboardHeight()
			Dom.div !->
				Dom.style height: '44px', paddingTop: '6px', margin: 0
				return if !moreDrawingsO.get() or drawingR.get('memberId') is myId

				Ui.lightButton !->
					Dom.style textAlign: 'right', margin: 0
					Dom.text tr("Guess next sketch")
				, !->
					Server.call 'requestDrawing', (drawingId) !->
						if drawingId is null
							Modal.show tr("No more sketches"), tr("It turns out, you seem to have run out of sketches to guess.")
						else
							App.trackActivity()
							Page.nav {0:drawingId}

	Obs.observe !->
		bg = backgroundO.get()
		if bg
			Page.setBackground "#CCC no-repeat 50% 50%/cover url(" + bg + ")"
			Dom.transition background: "rgba(255, 255, 255, 0.9)"

	# invisible canvas
	cvs = Canvas.render null, true, false # render canvas in stealth mode
	stepsO = Obs.create false
	if archiveWord
		Server.call 'getArchivedSteps', drawingId, Page.state.peek('round'), (steps) !->
			stepsO.set steps
	else
		Server.call 'getSteps', drawingId, (steps) !->
			stepsO.set steps
	Dom.div !-> # obs scope for onClean
		Dom.style margin:0
		steps = stepsO.get()
		return unless steps
		keepDrawing = true

		Obs.onClean !->
			keepDrawing = false

		# draw the image slightly delayed so the main interface is rendered beforehand
		Obs.onTime 500, !->
			return unless steps
			steps = Encoding.decode(steps)

			# use timeouts during drawing to keep the interface somewhat responsive
			i = 0
			drawStep = !->
				if not keepDrawing
					return
				for j in [0..20]
					if !steps[i]
						log "Drawn. Canvas to png."
						backgroundO.set cvs.dom.toDataUrl()
						return
					cvs.addStep steps[i++]
				setTimeout drawStep, 1
			drawStep()
