Dom = require 'dom'

CANVAS_WIDTH = CANVAS_HEIGHT = 500

exports.render = (touchHandler) !->
	steps = []
	ctx = false
	Dom.canvas !->
		Dom.prop('width', CANVAS_WIDTH)
		Dom.prop('height', CANVAS_HEIGHT)
		Dom.cls 'drawing-canvas'
		cvs = Dom.get()
		ctx = cvs.getContext '2d'
		ctx.lineJoin = ctx.lineCap = 'round'

		if touchHandler?
			Dom.trackTouch touchHandler, cvs

	cvsDom = Dom.last()

	drawStep = (step) !->
		switch step.type
			when 'move'
				ctx.beginPath()
				ctx.moveTo step.x, step.y
				#log "moving: #{step.x}, #{step.y}"
			when 'draw'
				ctx.lineTo step.x, step.y
				ctx.stroke()
				#log "drawing: #{step.x} #{step.y}"
			when 'dot'
				ctx.beginPath()
				ctx.moveTo step.x, step.y
				ctx.arc step.x, step.y, 1, 0, 2 * 3.14, true
				ctx.stroke()
			when 'col'
				ctx.strokeStyle = step.col
				#log "setting colour: #{step.col}"
			when 'brush'
				ctx.lineWidth = step.size
				#log "setting brush: #{step.size}"
			when 'clear'
				clear()
				#log "clearing"
			when 'undo'
				undo()
				#log "undoing"
			else
				log "unknown step type: #{step.type}"

	clear = (clearSteps) !->
		if clearSteps then steps = []
		ctx.clearRect 0, 0, CANVAS_WIDTH, CANVAS_HEIGHT

	addStep = (step) !->
		if step.type isnt 'undo' then steps.push step
		drawStep step

	redraw = !->
		clear()
		for step in steps
			drawStep step

	undo = !->
		return if not steps.length

		#brush size and colour
		storedSteps = []
		# undo isn't talking about invisible changes, so don't remove those.
		while steps[steps.length-1].type in ['brush', 'col']
			storedSteps.unshift steps.pop()

			# nothing to undo, really. Just restore the brush and colour and return
			if not steps.length
				steps = steps.concat storedSteps
				return

		switch steps[steps.length-1].type
			when 'draw'
				steps.pop() while steps[steps.length-1].type is 'draw'
				steps.pop() #remove the 'move'
			when 'clear', 'dot'
				steps.pop()
		steps = steps.concat storedSteps
		redraw()

	return {
		clear: clear
		addStep: addStep
		dom: cvsDom
	}

Dom.css
	'.drawing-canvas':
		backgroundColor: 'white'
		border: '1px solid grey'
		width: '100%'
		height: '80%'
		cursor: 'crosshair'
