Dom = require 'dom'
Obs = require 'obs'
Page = require 'page'

Config = require 'config'

CANVAS_SIZE = Config.canvasSize()
CANVAS_RATIO = Config.canvasRatio()

exports.render = (touchHandler, hidden=false, responsive=true) !->
	width = CANVAS_SIZE
	height = CANVAS_SIZE*CANVAS_RATIO
	steps = []
	ctx = cvs = null

	Dom.div !-> # define container
		if responsive # we don't need to resize if we're hidden
			containerE = Dom.get()
			Obs.observe !->
				# observe window size
				Page.width()
				Page.height()
				Dom.style
					position: 'relative'
					margin: "0 auto"
					Flex: true
					overflow: 'hidden'
					width: ''
					height: ''
				Dom.onLayout !-> # set size
					sWidth = containerE.width()
					sHeight = containerE.height()
					size = if sWidth is 0 or sHeight<(sWidth*CANVAS_RATIO) then sHeight/CANVAS_RATIO else sWidth
					containerE.style
						width: size+'px'
						height: size*CANVAS_RATIO+'px'
						Flex: false
						margin: "auto auto"
					log "canvas set size:", sWidth, sHeight, size

		# make canvas
		Dom.canvas !->
			Dom.prop('width', width)
			Dom.prop('height', height)
			Dom.style
				backgroundColor: '#DDD'
				width: '100%'
				height: '100%'
				cursor: 'crosshair'
			cvs = Dom.get()
			if hidden then Dom.style display: 'none' # hide
			# Unattached to the DOM would be prefferable.
			# But in that case, toDataURL will present an empty png.

	ctx = cvs.getContext '2d'
	ctx.SmoothingEnabled = true
	ctx.mozImageSmoothingEnabled = true
	ctx.webkitImageSmoothingEnabled = true
	ctx.msImageSmoothingEnabled = true
	ctx.imageSmoothingEnabled = true
	ctx.lineJoin = ctx.lineCap = 'round'

	if touchHandler?
		Dom.trackTouch touchHandler, cvs

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
		dom: cvs
	}