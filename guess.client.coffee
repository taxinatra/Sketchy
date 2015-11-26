Canvas = require 'canvas'
Obs = require 'obs'
Db = require 'db'
Page = require 'page'
Dom = require 'dom'
Server = require 'server'

exports.render = !->
	i = Page.state.get('drawing')
	letters = Obs.create false
	word = Obs.create()
	Server.call 'getLetters', i, (_word, _letters) !->
		word.set _word
		letters.set _letters
	drawing = Db.shared.ref('drawings').get(i)

	cvs = null
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

	log drawing
	Obs.observe !->
		if word.get()
			renderGuessing word.get(), letters # TODO: shouldn't have the real word client-side

renderGuessing = (word, letters) !->
	chosenLetters = Obs.create()
	chooseLetter = (curIndex, c) !->
		# find next empty spo
		for i in [0...word.length]
			if not chosenLetters.get(i)?
				chosenLetters.set(i, c)
				letters.set(curIndex, null)
				letters.set('count', letters.get('count') - 1)
				break

	Dom.div !->
		Dom.style
			textAlign: 'center'
		for i in [0...word.length] then do (i) !->
			Dom.div !->
				Dom.cls 'tile'
				if chosenLetters.get(i)?
					Dom.cls 'letter'
					Dom.text chosenLetters.get(i)
				else
					Dom.cls 'empty'

	Dom.div !->
		Dom.style
			textAlign: 'center'
		for i in [0...letters.get('count')] then do (i) !->
			Dom.div !->
				Dom.cls 'tile'
				Dom.cls 'letter'

				Dom.text letters.get(i)
				Dom.onTap !->
					chooseLetter i, letters.get(i)

Dom.css
	'.tile':
		display: 'inline-block'
		width: '40px'
		margin: '5px'
		height: '40px'
		borderRadius: '3px'
		border: '1px solid grey'

	'.tile.empty':
		background: 'white'

	'.tile.letter':
		background: 'beige'
		color: 'grey'
		fontSize: '30px'
		textAlign: 'center'
		boxShadow: 'black 1px 1px'