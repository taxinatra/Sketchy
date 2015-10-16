Dom = require 'dom'
Obs = require 'obs'
Page = require 'page'
Server = require 'server'
Icon = require 'icon'
Canvas = require 'canvas'

COLOURS = ['darkslategrey', 'white', '#FF6961', '#FDFD96', '#3333ff', '#77DD77', '#CFCFC4', '#FFD1DC', '#B39EB5', '#FFB347', '#836953']
BRUSH_SIZES = [{t:'S',n:3}, {t:'M',n:10}, {t:'L',n:20}, {t:'XL', n:70}]

CANVAS_WIDTH = CANVAS_HEIGHT = 500

DRAW_TIME = 9000 # ms

exports.render = !->
	Dom.style _userSelect: 'none'
	LINE_SEGMENT = 5
	colour = Obs.create COLOURS[0]
	lineWidth = Obs.create BRUSH_SIZES[1].n

	steps = []

	startTime = Obs.create false
	timeUsed = Obs.create 0

	startTheClock = !->
		return if startTime.peek() isnt false # timer already running
		startTime.set Date.now()

	Obs.observe !->
		st = startTime.get()
		return if st is false

		Obs.interval 100, !->
			timeUsed.set Math.min((Date.now() - st), DRAW_TIME)

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
		step.time = Date.now() - startTime.peek()
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
			if startTime.peek() is false
				log 'starting the clock'
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

	cvs = Canvas.render touchHandler

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
