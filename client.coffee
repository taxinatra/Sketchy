Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Plugin = require 'plugin'
Page = require 'page'
Server = require 'server'
Ui = require 'ui'
Icon = require 'icon'

COLOURS = ['darkslategrey', 'white', '#FF6961', '#FDFD96', '#3333ff', '#77DD77', '#CFCFC4', '#FFD1DC', '#B39EB5', '#FFB347', '#836953']
DRAW_TIME = 90000 # ms
CANVAS_WIDTH = CANVAS_HEIGHT = 500

exports.render = !->
	switch Page.state.get(0)
		when 'draw' then return renderDraw()
		when 'guess' then return renderGuess Page.state.get('drawing')

	Ui.button "New drawing", !->
		Page.nav 'draw'

	cnt = Db.shared.get('drawingCount')
	for i in [0...cnt] then do (i) !->
		Ui.button "Guess #{i + 1}", !->
			Page.nav {0:'guess', drawing:i}

renderCanvas = (touchHandler) !->
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
			when 'draw'
				ctx.lineTo step.x, step.y
				ctx.stroke()
			when 'dot'
				ctx.beginPath()
				ctx.moveTo step.x, step.y
				ctx.arc step.x, step.y, 1, 0, 2 * 3.14, true
				ctx.stroke()
			when 'col'
				ctx.strokeStyle = step.col
			when 'brush'
				ctx.lineWidth = step.size
			when 'clear'
				clear()
			when 'undo'
				undo()
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
		if steps.length
			steps.pop()
		redraw()

	return {
		clear: clear
		addStep: addStep
		dom: cvsDom
	}

renderGuess = (i) !->
	drawings = Db.shared.ref('drawings')
	drawing = drawings.get(i)
	steps = drawing.steps
	cvs = renderCanvas()

	startTime = Date.now()
	for step in drawing.steps then do (step) !->
		now = Date.now() - startTime
		if step.time > now
			Obs.onTime (step.time - now), !->
				cvs.addStep step
		else
			cvs.addStep step

renderDraw = !->
	Dom.style _userSelect: 'none'
	LINE_SEGMENT = 5
	colour = Obs.create COLOURS[0]
	lineWidth = Obs.create BRUSH_SIZES[1].n

	steps = []

	startTime = false
	timeUsed = Obs.create 0

	startTheClock = !->
		startTime = Date.now()

		Obs.observe !->
			Obs.interval 100, !->
				timeUsed.set Math.min((Date.now() - startTime), DRAW_TIME)
			Obs.onTime DRAW_TIME, !->
				Server.send 'addDrawing', {word: 'strawberry', steps: steps}
				Page.nav ''

	Dom.div !->
		remaining = DRAW_TIME - timeUsed.get()
		if remaining < (DRAW_TIME/3)
			r = 255
		else
			r = Math.round(255 * timeUsed.get() / (2*DRAW_TIME/3))
		Dom.style
			color: "rgb(#{r}, 0, 0)"
		Dom.text (remaining * .001).toFixed(1)

	# add a drawing step to our recording
	addStep = (type, data) !->
		step = {}
		if data? then step = data
		step.type = type
		step.time = Date.now() - startTime
		steps.push step

		# draw this step on the canvas
		cvs.addStep step

	toCanvasCoords = (pt) -> {
			x: Math.round((pt.x / cvs.dom.width()) * CANVAS_WIDTH)
			y: Math.round((pt.y / cvs.dom.height()) * CANVAS_HEIGHT)
		}

	drawPhase = 0 # 0:ready, 1: started, 2: moving
	lastPoint = undefined
	touchHandler = (touches...) !->
		return if not touches.length
		t = touches[0] # TODO" should I iterate over this?
		pt = toCanvasCoords {x: t.xc, y: t.yc}

		if t.op&1
			if not startTime
				startTheClock()
				# time's started, let's do setup
				addStep 'brush', {size: lineWidth.get()}
				addStep 'col', { col: colour.get() }
			lastPoint = pt # keep track of last point so we don't draw 1000s of tiny lines
			addStep 'move', lastPoint
			drawPhase = 1 # started

		else if drawPhase is 0 # if we're not drawing atm, we're done
			return true

		else if t.op&2
			if not lastPoint? or distanceBetween(lastPoint, pt) > LINE_SEGMENT #let's not draw lines < minimum
				addStep 'draw', pt
				lastPoint = pt
				drawPhase = 2 # moving

		else if t.op&4
			if drawPhase is 1 # started but not moved, draw a dot
				addStep 'dot', pt
			drawPhase = 0
			lastPoint = undefined

		else
			return true

		return false # if we've handled it, let's stop the rest from responding too

	cvs = renderCanvas touchHandler

	# toolbar
	Dom.div !->
		renderBrushSelector lineWidth
		Obs.observe !-> addStep 'brush', {size: lineWidth.get()}

		Dom.div !-> Dom.cls 'icon-separator'

		renderColourSelector colour
		Obs.observe !-> addStep 'col', {col: colour.get()}

		Dom.div !-> Dom.cls 'icon-separator'

		# undo button
		Dom.div !->
			Dom.cls 'button-block'
			Icon.render
				data: 'arrowrotl'
				size: 20
				color: 'grey'
				style: {margin: '9px'}
				onTap: !-> addStep 'undo'

		# clear button
		Dom.div !->
			Dom.cls 'button-block'
			Icon.render
				data: 'cancel'
				size: 20
				color: 'grey'
				style: {margin: '9px'}
				onTap: !-> addStep 'clear'

renderColourSelector = (colour) !->
	for c in COLOURS then do (c) !->
		Dom.div !->
			Dom.cls 'button-block'
			Dom.style backgroundColor: c
			Obs.observe !->
				Dom.style
					border: if colour.get() is c then '1px dashed grey' else 'none'
			Dom.onTap !-> colour.set c

BRUSH_SIZES = [{t:'S',n:3}, {t:'M',n:10}, {t:'L',n:20}, {t:'XL', n:70}]

renderBrushSelector = (lineWidth) !->
	selectingBrush = Obs.create false
	Obs.observe !->
		if not selectingBrush.get()
			Dom.div !->
				Dom.cls 'button-block'
				Dom.style
					border: '1px dashed grey'
					position: 'relative'
					lineHeight: '40px'

				Dom.div !->
					Dom.style
						width: '100%'
						height: '100%'
						position: 'absolute'
						textAlign: 'center'
					for c in BRUSH_SIZES
						if lineWidth.get() is c.n
							Dom.text c.t
				Dom.onTap !-> selectingBrush.set not selectingBrush.peek()
		else
			Dom.div !->
				Dom.style
					position: 'relative'
					display: 'inline-block'
					width: '40px'
					height: '40px'

				Dom.div !->
					Dom.style
						transition: 'opacity 1s ease'
						position: 'absolute'
						maxWidth: '40px'
						bottom: 0

					Obs.observe !->
						if selectingBrush.get()
							Dom.style
								display: 'block'
								opacity: 1
						else
							Dom.style
								opacity: 0
								display: 'none'

					# brush sizes
					for size in BRUSH_SIZES then do (size) !->
						Dom.div !->
							Dom.cls 'button-block'
							Dom.style
								lineHeight: '40px'
							Dom.div !->
								Dom.style
									width: '100%'
									height: '100%'
									position: 'absolute'
									textAlign: 'center'
								Dom.text size.t
							Obs.observe !->
								Dom.style
									border: if lineWidth.get() is size.n then '1px dashed grey' else '1px solid grey'
							Dom.onTap !->
								lineWidth.set size.n
								selectingBrush.set false

# helper function (pythagoras)
distanceBetween = (p1, p2) ->
	dx = p2.x - p1.x
	dy = p2.y - p1.y
	Math.sqrt (dx*dx + dy*dy)

Dom.css
	'.drawing-canvas':
		backgroundColor: 'white'
		border: '1px solid grey'
		width: '100%'
		height: '80%'
		cursor: 'crosshair'

	'.icon-separator':
		width: '10px'
		display: 'inline-block'

	'.button-block':
		position: 'relative'
		display: 'inline-block'
		boxSizing: 'border-box'
		backgroundColor: 'white' #default
		width: '40px'
		height: '40px'
		cursor: 'pointer'
