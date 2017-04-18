App = require 'app'
Canvas = require 'canvas'
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

Config = require 'config'
Timer = require 'timer'

CANVAS_RATIO = Config.canvasRatio()
GUESS_TIME = Config.guessTime()
GUESS_SPEED = Config.guessSpeed()
TYPE_TIME = Config.typeTime()

timeDelta = Date.now()-App.time()*1000
getTime = ->
	Date.now()-timeDelta

exports.render = (drawingId, localStorageO) !->
	GUESS_SPEED = Config.guessSpeed()
	poolO = Obs.create {}
	answerO = Obs.create {}
	fields = null
	solutionHash = null
	length = 0 # total number of letters in the answer
	initializedO = Obs.create false
	incorrectO = Obs.create false
	falseNavigationO = Obs.create false
	timer = 0
	pauseStart = 0
	pauseResult = 0
	timeUsedO = Obs.create 0
	letterColorO = Obs.create true
	lockO = Obs.create false
	pauseO = Obs.create false
	steps = false
	cvs = false

	unless drawingId and localStorageO
		log "missing either drawingId and/or localStorageO", drawingId, localStorageO
		Ui.emptyText tr("It seems like you are not supposed to be here.")
		return

	log "Render guessing. DrawingId:", drawingId

	fields = localStorageO.get('fields')
	solutionHash = localStorageO.get('solutionHash')
	length += i for i in fields
	poolO.set localStorageO.get('letters')
	timer = localStorageO.get('startTime')
	pauseStart = Db.personal.peek('pause', drawingId)||0
	if pauseStart
		pauseResult = 10
	log "Timer:", timer, "savedPause:", pauseStart, 'pauseResult:', pauseResult

	Page.setBackConfirm
		title: tr("Are you sure?")
		message: tr("This is your only chance to guess this sketching.")
		cb: !->
			# we cannot predict the word, and predicting the rest will trigger the 'navigation'
			Server.sync 'submitForfeit', drawingId, "user cancelled"

	# drawing steps
	stepWalker = 0
	nrOfSteps = steps.length
	steps = Encoding.decode(localStorageO.get('steps'))
	Obs.interval 10, !-> # 10ms = jiffy
		return if stepWalker >= nrOfSteps
		if not pauseO.peek()
			while steps[stepWalker] and steps[stepWalker].time/GUESS_SPEED < (getTime() - timer - pauseResult)
				cvs.addStep steps[stepWalker]
				stepWalker++


	# main timer
	log "startTime", timer
	Obs.interval 200, !->
		# log "timer", getTime(), timer, getTime()-timer + pauseResult, GUESS_TIME
		return if lockO.peek()
		if pauseO.peek() and pauseStart
			pauseResult = Math.min((getTime() - pauseStart), TYPE_TIME)
			timeUsedO.set pauseResult
		else
			timeUsedO.set Math.min((getTime() - timer - pauseResult), GUESS_TIME)

	# deadline is guess_time + type_time - start_time (+ restored pause)
	Obs.onTime GUESS_TIME+TYPE_TIME-(pauseResult*1000)-(getTime()-timer), !->
		if lockO.peek() or (Db.shared.peek('drawings', drawingId, 'members', App.memberId(), 'time') isnt -1)
			log "already submitted."

			return
		log "Forfeit by timer"
		# we cannot predict the word, and predicting the rest will trigger the 'navigation'
		Server.sync 'submitForfeit', drawingId, "timer expired"

		letterColorO.set 'wrong'

	# initiate type pause by timer
	Obs.onTime GUESS_TIME-(getTime() - timer), !->
		unless pauseStart
			log "Type pause initated by timer"
			pauseStart = getTime()
			timeUsedO.set Math.min((getTime() - pauseStart), TYPE_TIME) # predict time
			Server.sync 'setPause', drawingId, pauseStart, !->
				Db.personal.set 'pause', drawingId, pauseStart
			pauseO.set true # note we have started typing

	# type pause timeout
	Obs.observe !->
		if pauseO.get()
			Obs.onTime TYPE_TIME, !->
				log "type timer expired"
				pauseResult = TYPE_TIME
				timeUsedO.set Math.min((getTime() - timer - pauseResult), TYPE_TIME) # predict timer
				pauseO.set false

	# ----------- DOM setup and render functions ---------

	Dom.style backgroundColor: '#DDD', height: '100%', Box: 'vertical'

	renderTiles = (fromO, toO, inAnswer=false) !->
		for i in [0...fromO.get('count')] then do (i) !->
			currentBG = '#95B6D4'
			Dom.div !->
				Dom.addClass 'tile'
				thisE = Dom.get
				letter = fromO.get(i)
				if letter and not lockO.get() then Dom.onTap !->
					if pauseStart is 0 # pause timer
						pauseStart = getTime()
						timeUsedO.set Math.min((getTime() - pauseStart), TYPE_TIME) # predict time
						Server.sync 'setPause', drawingId, pauseStart, !->
							Db.personal.set 'pause', drawingId, pauseStart
						pauseO.set true # note we have started typing
					moveTile fromO, toO, i, inAnswer
				color = letterColorO.get()

				Dom.div !->
					Dom.addClass 'tileContent'
					bg = '#dc0074'
					ini = '#95B6D4'
					if letter
						Dom.addClass 'letter'
						Dom.removeClass 'empty'
						Dom.text fromO.get(i)[0]
						bg = '#dc0074'
						ini =  '#95B6D4'
					else
						Dom.addClass 'empty'
						Dom.removeClass 'letter'
						Dom.userText "-"
						bg = '#95B6D4'
						ini = '#dc0074'

					if inAnswer
						if color is 'wrong' then bg = '#79070A'
						if color is 'correct' then bg = '#2CAB08'

					if bg isnt currentBG
						Dom.transition
							background: bg
							initial: background: currentBG
						currentBG = bg
					else
						Dom.style background: bg

	moveTile = (from, to, curIndex, inOrder) !->
		if inOrder
			letter = from.peek curIndex
			return unless letter
			to.set [letter[1]], letter
			from.remove curIndex
		else # find next empty spot
			for i in [0...to.peek('count')]
				if not to.peek(i)?
					to.set i, from.peek(curIndex)
					from.remove curIndex
					break

	Timer.render GUESS_TIME, timeUsedO, 4, 4, pauseO, TYPE_TIME

	cvs = Canvas.render null # render canvas

	answerO.set 'count', length

	Obs.observe !-> # We compare to a simple hash so we can work offline.
	# If some Erik breaks this, we'll think of something better >:)
		givenAnswer = answerO.get()
		solution = (givenAnswer[i]?[0] for i in [0...length]).join ''
		log "solution:", solution,":", solution.length, 'vs', length
		if solution.length is length
			if Encoding.simpleHash(solution) is solutionHash
				lockO.set true
				# set timer
				t = (getTime()-timer-pauseResult)
				log "Correct answer! in", t, 'ms'
				letterColorO.set 'correct'
				setTimeout !->
					log "submitting answer:", solution, t
					# we cannot predict the word, and predicting the rest will trigger the 'navigation'
					Server.sync 'submitAnswer', drawingId, solution, t
				, 2000 # delay a bit

				#speed up sketchy replay to see end ending of it.
				pauseO.set false
				GUESS_SPEED = Math.max GUESS_SPEED, (GUESS_TIME-timeUsedO.peek())/2000
				log "Speeding up to (#{GUESS_TIME}-#{timeUsedO.peek()})/2000:", GUESS_SPEED
			else
				incorrectO.set true
				letterColorO.set 'wrong'
		else
			incorrectO.set false
			letterColorO.set true

	# main DOM setup
	Dom.div !->
		padding = if Page.height() > 700 then 6 else 3
		Dom.style background: '#666', margin: 0, position: 'relative'

		Obs.observe !->
			return unless incorrectO.get()
			Dom.div !->
				Dom.style
					position: 'absolute'
					bottom: '10px'
					left: Page.width()/2-67
					top: '-40px'
					height: '23px'
					textAlign: 'center'
					background: 'black'
					color: 'white'
					borderRadius: '2px'
					padding: '4px 8px'
				Dom.text tr("That is incorrect")

		Dom.div !->
			Dom.style
				margin: "0 auto"
				background: '#4E5E7B'
			Dom.div !->
				Dom.addClass 'answer'
				Dom.style
					background: '#28344A'
					padding: '3px 0px'
					width: '100%'
					textAlign: 'center'
				renderTiles answerO, poolO, true

				thisE = Dom.get()

			Dom.div !->
				Dom.style
					Box: 'middle'
					maxWidth: if Page.height() > 700 then "388px" else "333px"
					textAlign: 'center'
					margin: "0 auto"
				Dom.div !->
					Dom.addClass 'pool'
					Dom.style
						Flex: true
						padding: padding
					renderTiles poolO, answerO, false
				Icon.render
					data: 'close' # backspace
					color: 'white'
					size: 18
					style:
						padding: '3px'
						marginRight: '5px'
						border: "1px solid white"
						borderRadius: '2px'
					onTap: !->
						return if lockO.get()
						log "clear!"
						for i in [0...answerO.get('count')] then do (i) !->
							if answerO.peek(i)
								moveTile answerO, poolO, i, true

		Dom.css
			'.tile':
				display: 'inline-block'
				padding: "#{padding}px"
				_userSelect: 'none'

	Dom.css
		'.tileContent':
			_boxSizing: 'border-box'
			width: '32px'
			height: '32px'
			borderRadius: '3px'
			fontSize: '26px'
			lineHeight: '32px'
			textTransform: 'uppercase'
			color: 'white'
			textAlign: 'center'
			fontFamily: "Bree Serif"

		".pool .tile .tileContent.empty":
			color: '#95B6D4'

		'.tap .tileContent.letter':
			background: '#790C46'#'#DADAD9'
