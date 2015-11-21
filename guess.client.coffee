Canvas = require 'canvas'
Obs = require 'obs'
Db = require 'db'
Page = require 'page'
Dom = require 'dom'

exports.render = !->
	i = Page.state.get('drawing')
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

#	renderGuessing drawing.word # TODO: replace this with random letters containing the word

#renderGuessing = (word) !->
	#Dom.text word
