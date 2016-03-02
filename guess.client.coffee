App = require 'app'
Canvas = require 'canvas'
Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Page = require 'page'
Server = require 'server'
Time = require 'time'
Ui = require 'ui'
{tr} = require 'i18n'

Config = require 'config'

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
	Server.call 'getLetters', drawingId, (_fields, _solutionHash, _letters) !->
		unless _fields
			log "got null from server. word is either illegal or we already guessed this drawing"
			Page.up()
			return
		fields = _fields
		solutionHash = _solutionHash
		length += i for i in fields
		lettersO.set _letters
		timer = Date.now()
		initializedO.set true

		Obs.interval 1000, !->
			timeUsedO.set Math.min((Date.now() - timer), GUESS_TIME)

		Obs.onTime GUESS_TIME, !->
			log "guesstimer expired"
			if Db.shared.peek('drawings', drawingId, 'members', App.memberId())
				log "already submitted."
				return
			log "Forfeit by timer"
			Server.sync 'submitForfeit', drawingId, !->
				Db.shared.set 'drawings', drawingId, 'members', App.memberId(), -1
				Db.shared.set 'scores', App.memberId(), drawingId, 0
			Page.nav {0:'view', '?drawing':drawingId}

	Obs.observe !->
		if initializedO.get()
			Page.setBackAction
				icon: 'cancel'
				tap: !->
					Modal.confirm tr("Are you sure?"), tr("This is your only change to guess this drawing."), !->
						Server.sync 'submitForfeit', drawingId, !->
							Db.shared.set 'drawings', drawingId, 'members', App.memberId(), -1
							Db.shared.set 'scores', App.memberId(), drawingId, 0
						Page.up()

	drawingR = Db.shared.ref('drawings', drawingId)

	Dom.style minHeight: '100%'

	overlay = (cb) !->
		Dom.style
			position: 'absolute'
			top: 0
			width: '100%'
			height: '100%'
			margin: 0
			ChildMargin: 16
			Box: 'middle center'
			background: "rgba(255, 255, 255, 0.9)"
			color: 'black'
		cb()

	Obs.observe !->
		if initializedO.get()
			Dom.div !-> # timer
				Dom.style
					float: 'left'
					position: 'absolute'
					width: '50px'
					height: '50px'
					top: '26px'
					margin: '0 auto'
					borderRadius: '50%'
					zIndex: 99
					left: Page.width()/2-25+'px'
					opacity: '0.75'
					pointerEvents: 'none' # don't be tappable
				Obs.observe !->
					remaining = GUESS_TIME - timeUsedO.get()
					proc = 360/GUESS_TIME*remaining
					if proc > 180
						nextdeg = 90 - proc
						Dom.style
							backgroundImage: "linear-gradient(90deg, #0077CF 50%, transparent 50%, transparent), linear-gradient(#{nextdeg}deg, white 50%, #0077CF 50%, #0077CF)"
					else
						nextdeg = -90 - (proc-180)
						Dom.style
							backgroundImage: "linear-gradient(#{nextdeg}deg, white 50%, transparent 50%, transparent), linear-gradient(270deg, white 50%, #0077CF 50%, #0077CF)"
				Dom.div !->
					Dom.style
						position: 'absolute'
						width: '30px'
						height: '30px'
						backgroundColor: 'white'
						borderRadius: '50%'
						marginLeft: '10px'
						marginTop: '10px'
						textAlign: 'center'
						lineHeight: '30px'
						fontSize: '16px'
					Obs.observe !->
						remaining = GUESS_TIME - timeUsedO.get()
						Dom.text (remaining * .001).toFixed(0)

			cvs = null

			Dom.div !->
				Dom.style
					position: 'relative'
					margin: '0 auto'
				size = 296
				Obs.observe !-> # set size
					width = Page.width()-24 # margin
					height = Page.height()-5-156 # margin, guessing
					size = if height<(width*CANVAS_RATIO) then height/CANVAS_RATIO else width
					Dom.style width: size+'px', height: size*CANVAS_RATIO+'px'
				cvs = Canvas.render size, null # render canvas

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
			for step in steps then do (step) !->
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

			renderGuessing chosenLettersO, lettersO

		else
			Ui.emptyText tr("Loading ...")

	renderGuessing = (chosenLettersO, remainingLettersO) !->
		moveTile = (from, to, curIndex) !->
			# find next empty spot
			for i in [0...to.get('count')]
				if not to.get(i)?
					to.set i, from.get(curIndex)
					from.set curIndex, null
					break

		renderTiles = (fromO, toO, format=false) !->	Dom.div !->
			Dom.style
				textAlign: 'center'
			if format
				l = 0
				for i in fields
					Dom.div !->
						Dom.style
							display: 'inline-block'
							margin: "0 6px"
						for j in [0...i]
							Dom.div !->
								k = l+j
								Dom.addClass 'tile'
								Obs.observe !->
									if fromO.get(k)
										Dom.addClass 'letter'
										Dom.removeClass 'empty'
										Dom.text fromO.get(k)
										Dom.onTap !-> moveTile fromO, toO, k
									else
										Dom.addClass 'empty'
										Dom.removeClass 'letter'
										Dom.text '-'
						l+=i
			else
				for i in [0...fromO.get('count')] then do (i) !->
					Dom.div !->
						Dom.addClass 'tile'
						if not fromO.get(i)?
							Dom.addClass 'empty'
							Dom.removeClass 'letter'
							Dom.text ' '
						else
							Dom.addClass 'letter'
							Dom.removeClass 'empty'
							Dom.text fromO.get(i)
							Dom.onTap !-> moveTile fromO, toO, i

		renderTiles chosenLettersO, remainingLettersO, true
		renderTiles remainingLettersO, chosenLettersO, false

Dom.css
	'.tile':
		display: 'inline-block'
		width: '40px'
		margin: '5px'
		height: '40px'
		borderRadius: '3px'
		border: '1px solid grey'
		verticalAlign: 'middle'
		fontSize: '30px'

	'.tile.empty':
		background: 'white'

	'.tile.letter':
		background: 'beige'
		color: 'grey'
		textAlign: 'center'
		boxShadow: 'black 1px 1px'