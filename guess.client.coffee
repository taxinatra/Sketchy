Canvas = require 'canvas'
Obs = require 'obs'
Db = require 'db'
Page = require 'page'
Dom = require 'dom'
Server = require 'server'

exports.render = !->
	i = Page.state.get('drawing')
	letters = Obs.create false
	word = null
	initialized = Obs.create false
	success = Obs.create false

	Server.call 'getLetters', i, (_word, _letters) !->
		word = _word
		letters.set _letters
		initialized.set true
	drawing = Db.shared.ref('drawings').get(i)

	cvs = null
	Dom.div !->
		if success.get()
			Dom.text "Hoera!"
	Dom.div !->
		Dom.style
			height: '300px'
			position: 'relative'
		cvs = Canvas.render()

	startTime = Date.now()
	for step in drawing.steps then do (step) !->
		now = Date.now() - startTime
		if step.time > now
			Obs.onTime (step.time - now), !->
				cvs.addStep step
		else
			cvs.addStep step

	chosenLetters = Obs.create()
	Obs.observe !->
		return if not initialized.get()
		chosenLetters.set 'count', word.length

		Obs.observe !->
			solution = (chosenLetters.get(i) for i in [0...word.length]).join ''
			if solution is word
				success.set true

		renderGuessing chosenLetters, letters # TODO: shouldn't have the real word client-side

renderGuessing = (chosenLetters, remainingLetters) !->
	moveTile = (from, to, curIndex) !->
		# find next empty spot
		for i in [0...to.get('count')]
			if not to.get(i)?
				to.set i, from.get(curIndex)
				from.set curIndex, null
				break

	renderTiles = (from, to) !->
		Dom.div !->
			Dom.style
				textAlign: 'center'
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

	renderTiles chosenLetters, remainingLetters
	renderTiles remainingLetters, chosenLetters

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