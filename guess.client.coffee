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

exports.render = !->
	drawingId = Page.state.get('?drawing')
	lettersO = Obs.create false
	fields = null
	solutionHash = null
	length = 0 # total number of letters in the answer
	initializedO = Obs.create false
	incorrectO = Obs.create false
	timer = 0
	timeUsedO = Obs.create 0

	# ask the server for the info we need. The server will also note down the member started guessing.
	drawingR = Db.shared.ref('drawings', drawingId)
	return unless drawingR.get('steps') # check if we have steps

	Server.call 'getLetters', drawingId, (_fields, _solutionHash, _letters) !->
		unless _fields
			log "got null from server. word is either illegal or we already guessed this sketching"
			Page.up()
			return
		fields = _fields
		solutionHash = _solutionHash
		length += i for i in fields
		lettersO.set _letters
		timer = Date.now()
		initializedO.set true

		Obs.interval 200, !->
			timeUsedO.set Math.min((Date.now() - timer), GUESS_TIME)

		Obs.onTime GUESS_TIME, !->
			log "guesstimer expired"
			if Db.shared.peek('drawings', drawingId, 'members', App.memberId()) isnt -1
				log "already submitted."
				return
			log "Forfeit by timer"
			Server.sync 'submitForfeit', drawingId, !->
				Db.shared.set 'drawings', drawingId, 'members', App.memberId(), -2
				Db.shared.set 'scores', App.memberId(), drawingId, 0
			Page.nav {0:'view', '?drawing':drawingId}

	Obs.observe !->
		if initializedO.get()
			Page.setBackConfirm
				title: tr("Are you sure?")
				message: tr("This is your only chance to guess this sketching.")
				cb: !->
					Server.sync 'submitForfeit', drawingId, !->
						Db.shared.set 'drawings', drawingId, 'members', App.memberId(), -2
						Db.shared.set 'scores', App.memberId(), drawingId, 0

	Dom.style backgroundColor: '#DDD', height: '100%', Box: 'vertical'

	Obs.observe !->
		if initializedO.get()
			Timer.render GUESS_TIME, timeUsedO

			cvs = null

			Dom.div !->
				Dom.style
					position: 'relative'
					margin: "0 auto"
					Flex: true
					overflow: 'hidden'
				size = 296
				containerE = Dom.get()
				Obs.observe !->
					# observe window size
					Page.width()
					Page.height()
					Obs.nextTick !-> # set size
						width = containerE.width()
						height = containerE.height()
						size = if height<(width*CANVAS_RATIO) then height/CANVAS_RATIO else width
						containerE.style
							width: size+'px'
							height: size*CANVAS_RATIO+'px'
							Flex: false
							margin: "auto auto"
				cvs = Canvas.render null # render canvas

				Obs.observe !->
					return unless incorrectO.get()
					Dom.div !->
						Dom.style
							position: 'absolute'
							bottom: '10px'
							left: size/2-67
							textAlign: 'center'
							background: 'black'
							color: 'white'
							borderRadius: '2px'
							padding: '4px 8px'
						Dom.text tr("That is incorrect")

			startTime = Date.now()
			steps = drawingR.get('steps')
			return unless steps
			steps = steps.split(';')
			for data in steps then do (data) !->
				step = Canvas.decode(data)
				now = Date.now() - startTime
				if step.time > now
					Obs.onTime (step.time - now), !->
						cvs.addStep step
				else
					cvs.addStep step

			chosenLettersO = Obs.create({count: length})

			Obs.observe !-> # We compare to a simple hash so we can work offline.
			# If some Erik breaks this, we'll think of something better >:)
				solution = (chosenLettersO.get(i) for i in [0...length]).join ''
				log "solution:", solution, solution.length, 'vs', length
				if solution.length is length
					if Config.simpleHash(solution) is solutionHash
						# set timer
						timer = Math.round((Date.now()-timer)*.001)
						log "Correct answer! in", timer, 'sec'
						Server.sync 'submitAnswer', drawingId, solution, timer, !->
							Db.shared.set 'drawings', drawingId, 'members', App.memberId(), timer
							Db.shared.set 'scores', App.memberId(), drawingId

						Page.nav {0:'view', '?drawing':drawingId}
					else
						incorrectO.set true
				else
					incorrectO.set false

			Dom.div !->
				Dom.style background: '#666', margin: 0
				Dom.div !->
					Dom.style
						margin: "0 auto"
						# maxWidth: '388px'
					renderGuessing chosenLettersO, lettersO
		else
			Ui.emptyText tr("Loading ...")

	moveTile = (from, to, curIndex) !->
		# find next empty spot
		for i in [0...to.get('count')]
			if not to.get(i)?
				to.set i, from.get(curIndex)
				from.set curIndex, null
				break

	renderGuessing = (chosenLettersO, remainingLettersO) !->
		renderTiles = (fromO, toO, format=false) !->
			# if format
			# 	l = 0
			# 	for i in fields
			# 		Dom.div !->
			# 			Dom.style
			# 				display: 'inline-block'
			# 				margin: "0 6px"
			# 			for j in [0...i] then do (l, j) !->
			# 				Dom.div !->
			# 					Dom.addClass 'tile'
			# 					k = l+j
			# 					letter = fromO.get(k)
			# 					if letter then Dom.onTap !-> moveTile fromO, toO, k
			# 					Dom.div !->
			# 						Dom.addClass 'tileContent'
			# 						Obs.observe !->
			# 							if letter
			# 								Dom.addClass 'letter'
			# 								Dom.removeClass 'empty'
			# 								Dom.text fromO.get(k)
			# 							else
			# 								Dom.addClass 'empty'
			# 								Dom.removeClass 'letter'
			# 								Dom.text '-'
			# 			l+=i
			# else
			for i in [0...fromO.get('count')] then do (i) !->
				Dom.div !->
					Dom.addClass 'tile'
					letter = fromO.get(i)
					if letter then Dom.onTap !-> moveTile fromO, toO, i
					Dom.div !->
						Dom.addClass 'tileContent'
						if letter
							Dom.addClass 'letter'
							Dom.removeClass 'empty'
							Dom.text fromO.get(i)
						else
							Dom.addClass 'empty'
							Dom.removeClass 'letter'
							Dom.userText "&nbsp;"
		padding = if Page.height() > 700 then 6 else 3
		Dom.div !->
			Dom.style
				background: '#444'
				padding: '3px 0px'
				width: '100%'
				textAlign: 'center'
			renderTiles chosenLettersO, remainingLettersO, true
		Dom.div !->
			Dom.style
				Box: 'middle'
				maxWidth: if Page.height() > 700 then "388px" else "333px"
				textAlign: 'center'
				margin: "0 auto"
			Dom.div !->
				Dom.style
					Flex: true
					padding: padding
				renderTiles remainingLettersO, chosenLettersO, false
			Icon.render
				data: 'close' # backspace
				color: 'white'
				size: 18
				style:
					padding: '3px'
					# margin: "0 5px #{2+padding}px 0"
					marginRight: '5px'
					border: "1px solid white"
					borderRadius: '2px'
				onTap: !->
					log "clear!"
					for i in [0...chosenLettersO.get('count')] then do (i) !->
						moveTile chosenLettersO, lettersO, i

		Dom.css
			'.tile':
				display: 'inline-block'
				padding: "#{padding}px"

			'.tileContent':
				width: '32px'
				height: '32px'
				borderRadius: '3px'
				border: '1px solid grey'
				fontSize: '26px'
				lineHeight: '32px'
				textTransform: 'uppercase'
				color: 'grey'
				textAlign: 'center'

			'.tileContent.empty':
				background: 'white'
				boxShadow: 'none'

			'.tileContent.letter':
				background: 'beige'
				boxShadow: "black 1px 1px"

			'.tap .tileContent.letter':
				background: '#DADAD9'
