App = require 'app'
Canvas = require 'canvas'
Db = require 'db'
Dom = require 'dom'
Form = require 'form'
Icon = require 'icon'
Obs = require 'obs'
Page = require 'page'
Server = require 'server'
Ui = require 'ui'
{tr} = require 'i18n'

COLORS = ['darkslategrey', 'white', '#FF6961', '#FDFD96', '#3333ff', '#77DD77', '#CFCFC4', '#FFD1DC', '#B39EB5', '#FFB347', '#836953']
BRUSH_SIZES = [{t:'S',n:5}, {t:'M',n:16}, {t:'L',n:36}, {t:'XL', n:160}]

CANVAS_SIZE = 676
CANVAS_RATIO = 1.283783784 # (296 * 380)

DRAW_TIME = 45000 # ms

exports.render = !->
	myWord = Obs.create false
	drawingId = false
	Server.call 'startDrawing', (drawing) !->
		drawingId = drawing.id
		myWord.set drawing

	Dom.style _userSelect: 'none'
	LINE_SEGMENT = 5
	color = Obs.create COLORS[0]
	lineWidth = Obs.create BRUSH_SIZES[1].n

	steps = []

	startTime = Obs.create false
	timeUsed = Obs.create 0
	size = 296 # render size of the canvas

	Obs.observe !->
		if startTime.get()
			Form.setPageSubmit submit, true
			Obs.onClean !->
				log "onclean bar startTheClock"

	# ------------ helper functions -------------

	startTheClock = !->
		return if startTime.peek() isnt false # timer already running
		log "startTheClock"
		startTime.set Date.now()

	submit = !->
		log "submitting! across the universe"
		time = Date.now()
		Server.sync 'addDrawing', drawingId, steps, time, !->
			log "predict"
			Db.shared.set 'drawings', drawingId,
				userId: App.memberId()
				wordId: myWord.peek().id
				steps: steps
				time: time
		Page.up()

	# add a drawing step to our recording
	addStep = (type, data) !->
		# log "adding Step:", type, data
		step = {}
		if data? then step = data
		step.type = type
		step.time = Date.now() - startTime.peek()
		steps.push step

		# draw this step on the canvas
		cvs.addStep step

	toCanvasCoords = (pt) ->
		{
			x: Math.round((pt.x / size) * CANVAS_SIZE)
			y: Math.round((pt.y / size) * CANVAS_SIZE)
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
				addStep 'brush', {size: lineWidth.peek()}
				addStep 'col', { col: color.peek() }
			lastPoint = pt # keep track of last point so we don't draw 1000s of tiny lines
			addStep 'move', lastPoint
			drawPhase = 1 # started

		else if drawPhase is 0 # if we're not drawing atm, we're done
			return true

		else if t.op&2
			if not lastPoint? or distanceBetween(lastPoint, pt) > LINE_SEGMENT #let's not draw lines < minimum
				# TODO: also limit on delta angel and delta time
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

	Obs.observe !-> # send the drawing to server
		st = startTime.get()
		return if st is false

		Obs.interval 1000, !->
			timeUsed.set Math.min((Date.now() - st), DRAW_TIME)

		Obs.onTime DRAW_TIME, submit

	# ------------ button functions ---------------
	renderColorSelector = (color) !->
		for c in COLORS then do (c) !->
			Dom.div !->
				Dom.cls 'button-block'
				Dom.div !->
					Dom.style
						height: '100%'
						width: '100%'
						borderRadius: '50%'
						backgroundColor: c
				Obs.observe !->
					Dom.style
						border: if color.get() is c then '4px solid grey' else 'none'
						padding: if color.get() is c then 0 else 4
				Dom.onTap !->
					color.set c
					log "well? c:", c
					addStep 'col', { col: c }

	renderBrushSelector = (lineWidth) !->
		for b in BRUSH_SIZES then do (b) !->
			Dom.div !->
				Dom.cls 'button-block'
				Dom.div !->
					Dom.style
						height: '100%'
						width: '100%'
						borderRadius: '50%'
						backgroundColor: 'white'
						Box: 'middle center'
						fontWeight: 'bold'
					Dom.text b.t
				Obs.observe !->
					Dom.style
						border: if lineWidth.get() is b.n then '4px solid grey' else 'none'
						padding: if lineWidth.get() is b.n then 0 else 4
				Dom.onTap !->
					lineWidth.set b.n
					addStep 'brush', { size: b.n }

	# ------------ compose dom -------------

	Dom.style backgroundColor: '#666', height: '100%'

	Ui.top !->
		Dom.style
			textAlign: 'center'
			fontWeight: 'bold'
		word = myWord.get()
		if word
			Dom.text tr("Draw %1 '%2'", word.prefix, word.word)
		else
			Dom.text "_" # prevent resizing when word has been retrieved

	Dom.div !-> # timer
		Dom.style
			position: 'absolute'
			width: '40px'
			height: '40px'
			left: Page.width()/2-25+'px'
			top: '50px'
			zIndex: 10
			borderRadius: '50%'
			Box: 'middle center'
		Obs.observe !->
			remaining = DRAW_TIME - timeUsed.get()
			Dom.style
				background_: "linear-gradient(top, rgba(255,26,0,0) 0%, rgba(255,26,0,0)  #{100-remaining/DRAW_TIME*100}%, rgba(255,26,0,1) #{99-remaining/DRAW_TIME*100}%, rgba(255,26,0,1) 100%)"
			if remaining < (DRAW_TIME/3)
				r = 255
			else
				r = Math.round(255 * timeUsed.get() / (2*DRAW_TIME/3))
			Dom.text (remaining * .001).toFixed(0)

	cvs = false
	Dom.div !->
		Dom.style
			position: 'relative'
			margin: '0 auto'
		size = 296
		Obs.observe !-> # set size
			# 296 * 360, ratio=1:1.126
			width = Page.width()-24 # margin
			height = Page.height()-16-40-80 # margin, top, shelf
			size = if height<(width*CANVAS_RATIO) then height/CANVAS_RATIO else width
			Dom.style width: size+'px', height: size*CANVAS_RATIO+'px'
		log "canvas render size:", size
		cvs = Canvas.render size, touchHandler # render canvas

		Dom.div !->
			return if startTime.get()
			Dom.style
				position: 'absolute'
				top: '30%'
				width: '100%'
				fontSize: '90%'
			word = myWord.get()
			return unless word
			Ui.emptyText tr("Draw %1 '%2'", word.prefix, word.word)
			Ui.emptyText tr("Timer will start when you start drawing");

	# toolbar
	Dom.div !-> # shelf
		Dom.style
			Flex: true
			height: '80px'
			marginBottom: '4px'
			# position: 'relative'
		Dom.div !->
			Dom.style Flex: true, height: '42px'
			Dom.overflow()
			Dom.div !->
				Dom.style
					Box: 'top'
					width: 40*COLORS.length + 'px'
					marginTop: '2px'
				renderColorSelector color
			# Obs.observe !-> addStep 'brush', {size: lineWidth.get()}

		Dom.div !->
			Dom.style Box: 'top'

			Dom.div !-> # undo button
				Dom.cls 'button-block'
				Icon.render
					data: 'arrowrotl'
					size: 20
					color: 'white'
					style: padding: '10px'
					onTap: !-> addStep 'undo'

			Dom.div !->
				Dom.style Flex: true, Box: 'top center'
				renderBrushSelector lineWidth

			Dom.div !-> # clear button
				Dom.cls 'button-block'
				Icon.render
					data: 'cancel'
					size: 20
					color: 'white'
					style: padding: '10px'
					onTap: !-> addStep 'clear'




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
		boxSizing: 'border-box'
		borderRadius: '50%'
		width: '40px'
		height: '40px'
		cursor: 'pointer'
