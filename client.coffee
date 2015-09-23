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
DRAW_TIME = 50000 # ms
CANVAS_WIDTH = CANVAS_HEIGHT = 500

exports.render = !->
	if Page.state.get(0) is 'draw'
		return renderDraw()
	Ui.button "New drawing", !->
		Page.nav 'draw'

renderCanvas = !->
	steps = []
	cvs = false
	ctx = false
	Dom.canvas !->
		Dom.prop('width', CANVAS_WIDTH)
		Dom.prop('height', CANVAS_HEIGHT)
		Dom.style
			backgroundColor: 'white'
			border: '1px solid grey'
			width: '100%'
			height: '80%'
			cursor: 'crosshair'
		cvs = Dom.get()
		ctx = cvs.getContext '2d'
		ctx.lineJoin = ctx.lineCap = 'round'

	drawStep = (step) !->
		log 'drawing a step'

	clear = !->
		ctx.clearRect 0, 0, CANVAS_WIDTH, CANVAS_HEIGHT


	addStep = (step) !->
		steps.push step
		drawStep step

	redraw = !->
		for step in steps
			drawStep step

	undo = !->
		steps.pop()
		redraw()

	return
		clear: clear
		addStep: addStep

renderDraw = !->
	Dom.style _userSelect: 'none'
	LINE_SEGMENT = 5
	lines = []
	colour = Obs.create COLOURS[0]
	lineWidth = Obs.create BRUSH_SIZES[1].n
	cvs = false

	startTime = Date.now()
	timeUsed = Obs.create DRAW_TIME
	Obs.observe !->
		Obs.interval 100, !->
			timeUsed.set Math.min((Date.now() - startTime), DRAW_TIME)
		Obs.onTime DRAW_TIME, !->
			Server.send 'addDrawing', lines
			# TODO: send drawing to server
			Page.nav ''

	Dom.div !->
		Dom.text ((DRAW_TIME - timeUsed.get()) * .001).toFixed(1)

	clear = (cvs) !->
		ctx = cvs.getContext('2d')
		ctx.clearRect 0, 0, CANVAS_WIDTH, CANVAS_HEIGHT

	cvs = renderCanvas()
	clear = (replay) !->
		if not replay then lines.push {clear: true, time: Date.now() - startTime}
		cvs.clear()

	undo = (replay) !->
		lines.pop()
		cvs.undo()

	drawLine = (line) !->
		first = true
		ctx.beginPath()
		ctx.strokeStyle = line.colour
		ctx.lineWidth = line.lineWidth
		for pt in line.points # points
			if first
				ctx.moveTo pt.x, pt.y
				first = false
			else
				ctx.lineTo pt.x, pt.y
		ctx.stroke()

	redraw = !->
		lines.push {clear: true}
		cvs.clear()
		for obj in lines
			if obj.clear #clear object
				cvs.clear true
			else
				firstPt = obj.points[0]
				lastPt = obj.points[obj.points.length-1]
				drawLine obj

	distanceBetween = (p1, p2) ->
		dx = p2.x - p1.x
		dy = p2.y - p1.y
		Math.sqrt (dx*dx + dy*dy)

	angleBetween = (p1, p2) ->
		dx = p2.x - p1.x
		dy = p2.y - p1.y
		Math.atan2 dx, dy

	toCanvasCoords = (pt) -> {
			x: Math.round((pt.x/cvs.width())*CANVAS_WIDTH)
			y: Math.round((pt.y/cvs.height())*CANVAS_HEIGHT)
		}

	drawingLine = false

	points = []
	lastPoint = null
	drawToPoint = (pt) !->
		pt.time = Date.now() - startTime
		ctx.lineTo pt.x, pt.y
		ctx.stroke()
		points.push pt
		lastPoint = pt

	isMoving = false

	Dom.trackTouch (touches...) !->
			return if not touches.length
			t = touches[0]
			pt = toCanvasCoords {x: t.xc, y: t.yc}
			if t.op&1
				drawingLine = true
				isMoving = false
				ctx.beginPath()
				ctx.strokeStyle = colour.peek()
				ctx.lineWidth = lineWidth.peek()
				ctx.moveTo pt.x, pt.y
				drawToPoint pt
			else if t.op&2
				if drawingLine
					if not lastPoint? or distanceBetween(lastPoint, pt) > LINE_SEGMENT #let's not draw ridiculously short 1px lines
						isMoving = true
						drawToPoint pt
			else if t.op&4
				if drawingLine
					if isMoving #draw a line
						drawToPoint pt
					else #draw a dot
						ctx.beginPath()
						ctx.arc(pt.x, pt.y, 1, 0, 2 * 3.14, true)
						ctx.stroke()
					drawingLine = false
					line = {colour: colour.peek(), lineWidth: lineWidth.peek(), points: points}
					lines.push line
					points = []
			return false
		, cvs

	# toolbar
	Dom.div !->
		renderBrushSelector lineWidth

		Dom.div !-> Dom.cls 'icon-separator'

		renderColourSelector colour

		Dom.div !-> Dom.cls 'icon-separator'

		# undo button
		Dom.div !->
			Dom.cls 'button-block'
			Icon.render
				data: 'arrowrotl'
				size: 20
				color: 'grey'
				style: {margin: '9px'}
				onTap: !-> if cvs then cvs.undo()

		# clear button
		Dom.div !->
			Dom.cls 'button-block'
			Icon.render
				data: 'cancel'
				size: 20
				color: 'grey'
				style: {margin: '9px'}
				onTap: !-> if cvs then cvs.clear()

renderColourSelector = (colour) !->
	for c in COLOURS then do (c) !->
		Dom.div !->
			Dom.cls 'button-block'
			Dom.style backgroundColor: c
			Obs.observe !->
				Dom.style
					border: if colour.get() is c then '1px dashed grey' else 'none'
			Dom.onTap !-> colour.set c

BRUSH_SIZES = [{t:'S',n:2}, {t:'M',n:6}, {t:'L',n:12}, {t:'XL', n:70}]

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
