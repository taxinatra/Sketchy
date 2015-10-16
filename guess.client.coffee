Canvas = require 'canvas'
Obs = require 'obs'

exports.render = (drawing) !->
	cvs = Canvas.render()

	startTime = Date.now()
	for step in drawing.steps then do (step) !->
		now = Date.now() - startTime
		if step.time > now
			Obs.onTime (step.time - now), !->
				cvs.addStep step
		else
			cvs.addStep step