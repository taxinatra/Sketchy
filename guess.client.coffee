App = require 'app'
Canvas = require 'canvas'
Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Page = require 'page'
Server = require 'server'
Ui = require 'ui'
{tr} = require 'i18n'

Config = require 'config'

CANVAS_RATIO = 1.283783784 # (296 * 380)

exports.render = !->
	drawingId = Page.state.get('?drawing')
	letters = Obs.create false
	fields = null
	solutionHash = null
	length = 0 # total number of letters in the answer
	initialized = Obs.create false
	success = Obs.create false

	Server.call 'getLetters', drawingId, (_fields, _solutionHash, _letters) !->
		log "getLetters", _fields, _solutionHash, _letters
		fields = _fields
		solutionHash = _solutionHash
		length += i for i in fields
		letters.set _letters
		initialized.set true

	Obs.observe !->
		if initialized.get()
			Page.setBackAction
				icon: 'cancel'
				tap: !->
					Modal.confirm tr("Are you sure?"), tr("This is your only change to guess this."), !->
						Page.up()

	drawing = Db.shared.ref('drawings').get(drawingId)

	Dom.style minHeight: '100%'

	Obs.observe !->
		if initialized.get()
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

			startTime = Date.now()
			for step in drawing.steps then do (step) !->
				now = Date.now() - startTime
				if step.time > now
					Obs.onTime (step.time - now), !->
						cvs.addStep step
				else
					cvs.addStep step

			chosenLetters = Obs.create({count: length})

			Obs.observe !-> # We compare to a simple hash so we can work offline.
			# If some Erik breaks this, we'll think of something better >:)
				solution = (chosenLetters.get(i) for i in [0...length]).join ''
				if solution.length is length
					if Config.simpleHash(solution) is solutionHash
						log "Corret answer!"
						Server.sync 'submitAnswer', drawingId, solution, !->
							Db.shared.set 'drawings', drawingId, 'members', App.memberId(), true
						Page.up()

						success.set true

			renderGuessing chosenLetters, letters

			Dom.div !->
				return unless success.get()
				Dom.style
					position: 'absolute'
					top: 0
					width: '100%'
					height: '100%'
					margin: 0
					Box: 'middle center'
					background: "rgba(0, 0, 0, 0.5)"
					color: 'white'
				Dom.text tr("Great! you guessed it correctly!")
				Page.removeBarAction('back')
		else
			Ui.emptyText tr("Loading...")

	renderGuessing = (chosenLetters, remainingLetters) !->
		moveTile = (from, to, curIndex) !->
			# find next empty spot
			for i in [0...to.get('count')]
				if not to.get(i)?
					to.set i, from.get(curIndex)
					from.set curIndex, null
					break

		renderTiles = (from, to, format=false) !->	Dom.div !->
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
								Dom.cls 'tile'
								Obs.observe !->
									v = from.get(k)
									if v
										Dom.cls 'letter'
										Dom.text from.get(k)
										Dom.onTap !-> moveTile from, to, k
									else
										Dom.cls 'empty'
										Dom.text '-'
						l+=i
			else
				for i in [0...from.get('count')] then do (i) !->
					Dom.div !->
						Dom.cls 'tile'
						if not from.get(i)?
							Dom.cls 'empty'
							Dom.text ' '
						else
							Dom.cls 'letter'
							Dom.text from.get(i)
							Dom.onTap !-> moveTile from, to, i

		renderTiles chosenLetters, remainingLetters, true
		renderTiles remainingLetters, chosenLetters, false

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