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

nav = !->
	log "nav away"

timeDelta = Date.now()-App.time()*1000
getTime = ->
	Date.now()-timeDelta

exports.render = !->
	drawingId = Page.state.get(0)
	poolO = Obs.create {}
	answerO = Obs.create {}
	fields = null
	solutionHash = null
	length = 0 # total number of letters in the answer
	initializedO = Obs.create false
	incorrectO = Obs.create false
	falseNavigationO = Obs.create false
	timer = 0
	timeUsedO = Obs.create 0
	flashO = Obs.create false # flash tiles in a color

	Obs.observe !->
		if falseNavigationO.get()
			Ui.emptyText tr("It seems like you are not suppose to be here.")

	unless drawingId # if we have no id, error
		falseNavigationO.set true
		return

	# ask the server for the info we need. The server will also note down the member started guessing.
	drawingR = Db.shared.ref('drawings', drawingId)
	unless drawingR.get('steps') # if we have no steps, error
		falseNavigationO.set true
		return

	now = getTime()
	Server.call 'getLetters', drawingId, (_fields, _solutionHash, _letters) !->
		log "gotLetters"
		if _fields is "time"
			log "Your time is up"
			flashO.set 'wrong'
			nav()
			return
		unless _fields
			log "got null from server. word is either illegal or we already guessed this sketching"
			falseNavigationO.set true
			return
		fields = _fields
		solutionHash = _solutionHash
		length += i for i in fields
		poolO.set _letters
		timer = Db.personal.peek(drawingId)||now
		log "savedTimer:", Db.personal.peek(drawingId), "now:", now, "timer:", timer
		initializedO.set true

	Dom.div !-> # do in obs scope for cleanup
		if initializedO.get()
			Page.setBackConfirm
				title: tr("Are you sure?")
				message: tr("This is your only chance to guess this sketching.")
				cb: !->
					Server.sync 'submitForfeit', drawingId, !->
						Db.shared.set 'drawings', drawingId, 'members', App.memberId(), -2
						Db.shared.set 'scores', App.memberId(), drawingId, 0

			Obs.interval 200, !->
				# log "timer", getTime(), timer, getTime()-timer, GUESS_TIME
				timeUsedO.set Math.min((getTime() - timer), GUESS_TIME)

			Obs.onTime GUESS_TIME-(getTime() - timer), !->
				if Db.shared.peek('drawings', drawingId, 'members', App.memberId()) isnt -1
					log "already submitted."
					nav()
					return
				log "Forfeit by timer"
				Server.sync 'submitForfeit', drawingId, !->
					Db.shared.set 'drawings', drawingId, 'members', App.memberId(), -2
					Db.shared.set 'scores', App.memberId(), drawingId, 0
				flashO.set 'wrong'
				nav()

	Dom.style backgroundColor: '#DDD', height: '100%', Box: 'vertical'

	renderTiles = (fromO, toO, inAnswer=false) !->
		for i in [0...fromO.get('count')] then do (i) !->
			Dom.div !->
				Dom.addClass 'tile'
				thisE = Dom.get
				letter = fromO.get(i)
				if letter then Dom.onTap !-> moveTile fromO, toO, i, inAnswer
				Dom.div !->
					Dom.addClass 'tileContent'
					if letter
						Dom.addClass 'letter'
						Dom.removeClass 'empty'
						Dom.text fromO.get(i)[0]
						Dom.transition
							background: '#BA1A6E'
							initial: background: '#95B6D4'
					else
						Dom.addClass 'empty'
						Dom.removeClass 'letter'
						Dom.userText "-"
						Dom.transition
							background: '#95B6D4'
							initial: background: '#BA1A6E'

	moveTile = (from, to, curIndex, inOrder) !->
		if inOrder
			letter = from.peek curIndex
			to.set [letter[1]], letter
			from.remove curIndex
		else # find next empty spot
			for i in [0...to.peek('count')]
				if not to.peek(i)?
					to.set i, from.peek(curIndex)
					from.remove curIndex
					break

	Obs.observe !->
		unless initializedO.get()
			Ui.emptyText tr("Loading ...")
			return

		Timer.render GUESS_TIME, timeUsedO

		cvs = Canvas.render null # render canvas

		log "startTime", timer, getTime()
		steps = drawingR.get('steps')
		return unless steps
		steps = steps.split(';')
		for data in steps then do (data) !->
			step = Canvas.decode(data)
			now = getTime() - timer
			if step.time > now
				Obs.onTime (step.time - now), !->
					cvs.addStep step
			else
				cvs.addStep step

		answerO.set 'count', length

		Obs.observe !-> # We compare to a simple hash so we can work offline.
		# If some Erik breaks this, we'll think of something better >:)
			givenAnswer = answerO.get()
			solution = (givenAnswer[i]?[0] for i in [0...length]).join ''
			log "solution:", solution,":", solution.length, 'vs', length
			if solution.length is length
				if Config.simpleHash(solution) is solutionHash
					# set timer
					timer = Math.round((getTime()-timer)*.001)
					log "Correct answer! in", timer, 'sec'
					flashO.set 'correct'
					Obs.onTime 1400, !->
						Server.sync 'submitAnswer', drawingId, solution, timer, !->
							Db.shared.set 'drawings', drawingId, 'members', App.memberId(), timer
							Db.shared.set 'scores', App.memberId(), drawingId, Config.timeToScore(timer)
					nav()
				else
					incorrectO.set true
					flashO.set 'flashWrong'
			else
				incorrectO.set false
				flashO.set false

		# ---------- set the dom --------
		padding = if Page.height() > 700 then 6 else 3

		Dom.div !->
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
					Obs.observe !->
						if flash = flashO.get()
							log "flash:", flash
							if flash is 'flashWrong'
								thisE.transition
									background: '#28344A'
									initial: background: '#79070A'
									time: 600
							else if flash is 'wrong'
								thisE.transition
									background: '#79070A'
									time: 600
							else if flash is 'correct'
								thisE.transition
									background: '#2CAB08'
									time: 600
							else
								thisE.style background: '28344A'

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
							log "clear!"
							for i in [0...answerO.get('count')] then do (i) !->
								if answerO.peek(i)
									moveTile answerO, poolO, i, true

		Dom.css
			'.tile':
				display: 'inline-block'
				padding: "#{padding}px"
				_userSelect: 'none'

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
				# _transition: 'background 1s'

			# '.tileContent.empty':
				# background: '#95B6D4'
				# boxShadow: 'none'

			# '.tileContent.letter':
				# border: '1px solid white'

			# ".tile .tileContent.letter":
				# background: '#BA1A6E'
				# color: 'white'
				# boxShadow: "black 1px 1px"

			".pool .tile .tileContent.empty":
				color: '#95B6D4'

			# ".tile .tileContent.empty":
				# background: '#BA1A6E'
				# border: "2px solid white"

			# ".tile .tileContent.letter":
			# 	border: "2px solid #BA1A6E"
			# 	background: 'white'
			# 	color: 'black'
			# 	boxShadow: "black 1px 1px"

			'.tap .tileContent.letter':
				background: '#790C46'#'#DADAD9'
