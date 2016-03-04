Dom = require 'dom'

Config = require 'config'

CANVAS_SIZE = Config.canvasSize()
CANVAS_RATIO = Config.canvasRatio()

exports.render = (touchHandler) !->
	width = CANVAS_SIZE
	height = CANVAS_SIZE*CANVAS_RATIO
	steps = []
	ctx = false
	Dom.canvas !->
		Dom.prop('width', width)
		Dom.prop('height', height)
		Dom.cls 'drawing-canvas'
		cvs = Dom.get()
		ctx = cvs.getContext '2d'
		ctx.SmoothingEnabled = true
		ctx.mozImageSmoothingEnabled = true
		ctx.webkitImageSmoothingEnabled = true
		ctx.msImageSmoothingEnabled = true
		ctx.imageSmoothingEnabled = true
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
				# log "drawing: #{step.x} #{step.y}"
			when 'dot'
				ctx.beginPath()
				ctx.moveTo step.x, step.y
				ctx.arc step.x, step.y, 1, 0, 2 * 3.14, true
				ctx.stroke()
			when 'col'
				ctx.strokeStyle = step.col
				# log "setting color: #{step.col}"
			when 'brush'
				ctx.lineWidth = step.size
				# log "setting brush:", step
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
		ctx.clearRect 0, 0, width, height

	addStep = (step) !->
		if step.type isnt 'undo' then steps.push step
		drawStep step

	redraw = !->
		clear()
		for step in steps
			drawStep step

	undo = !->
		return if not steps.length

		#brush size and color
		storedSteps = []
		# undo isn't talking about invisible changes, so don't remove those.
		while steps[steps.length-1].type in ['brush', 'col']
			storedSteps.unshift steps.pop()

			# nothing to undo, really. Just restore the brush and color and return
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
		backgroundColor: '#EEEDEA'
		width: '100%'
		height: '100%'
		cursor: 'crosshair'

exports.encode = (step) ->
	line = ""
	# type
	line += ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'].indexOf(step.type)
	# value
	if step.x then line += ("000" + Math.round(step.x)).substr(-3)
	if step.y then line += ("000" + Math.round(step.y)).substr(-3)
	if step.size then line += ("000000" + step.size).substr(-6)
	if step.col then line += (""+step.col).substr(1) # skip the hash of colors
	# time
	line += ("00000" + step.time).substr(-5) # 5 chars is enough. we cannot have higher then DRAW_TIME
	return line


exports.decode = (data) ->
	r = {} #TXXXYYYttttt
	type = 0|data[0]
	r.type = ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'][type] # first char
	if r.type in ['move', 'draw', 'dot']
		r.x = 0|data.substr(1,3)
		r.y = 0|data.substr(4,3)
	else if r.type is 'col'
		r.col = '#' + data.substr(1,6)
	else if r.type is 'brush'
		r.size = 0|data.substr(1,6)
	if type > 4 # not clear or undo
		r.time = 0|data.substr(1,5)
	else
		r.time = 0|data.substr(7,5)
	return r