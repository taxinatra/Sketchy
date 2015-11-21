Canvas = require 'canvas'
Obs = require 'obs'
Db = require 'db'
Page = require 'page'
Dom = require 'dom'
Server = require 'server'

exports.render = !->
	i = Page.state.get('drawing')
	letters = Obs.create false
	Server.call 'getLetters', i, (_letters) !-> letters.set _letters
	drawing = Db.shared.ref('drawings').get(i)

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
		if letters.get()
			renderGuessing letters.get() # TODO: replace this with random letters containing the word

renderGuessing = (letters) !->
	scrambled = []
	letters = (letters[i] for i in [0...letters.length])
	while letters.length
		index = Math.floor(Math.random() * letters.length)
		scrambled.push letters.splice index, 1
	Dom.text scrambled.join ' '
