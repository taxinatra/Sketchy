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

Config = require 'config'
Timer = require 'timer'
# COLORS = ['darkslategrey', 'white', '#FF6961', '#FDFD96', '#3333ff', '#77DD77', '#CFCFC4', '#FFD1DC', '#B39EB5', '#FFB347', '#836953']
# use deciHexi only!
COLORS = ['#DDDDDD', '#45443D', '#FFFFFF', '#0077CF', '#DD2BC3', '#EA2323', '#F1E80A', '#0CE666', '#BA5212', '#F9B6DD']
BRIGHT_COLORS = ['#EEEDEA', '#45443D', '#FFFFFF', '#5CACE7', '#F0ABE6', '#F59494', '#FFFCAF', '#9BFF80', '#E59B6D', '#F9B6DD']
DARK_COLORS = ['#EEEDEA', '#000000', '#D6C9CC', '#003D6B', '#731665', '#960F00', '#785A00', '#00840B', '#513515', '#875572']
BRUSH_SIZES = [{t:'S',n:5}, {t:'M',n:16}, {t:'L',n:36}, {t:'XL', n:160}]

CANVAS_SIZE = Config.canvasSize()
CANVAS_RATIO = Config.canvasRatio()

THINK_TIME = Config.thinkingTime()
DRAW_TIME = Config.drawTime()

timeDelta = Date.now()-App.time()*1000
getTime = ->
	Date.now()-timeDelta

exports.render = !->
	myWordO = Obs.create false
	falseNavigationO = Obs.create false
	initializedO = Obs.create false
	drawingId = false
	firstSketch = !Db.shared.peek('drawingCount')?

	Obs.observe !->
		if falseNavigationO.get()
			Ui.emptyText tr("It seems like you are not supposed to be here.")

	Dom.style _userSelect: 'none'
	LINE_SEGMENT = 5
	colorO = Obs.create 1
	tintO = Obs.create 1
	lineWidthO = Obs.create BRUSH_SIZES[1].n
	steps = []

	thinkTimer = Obs.create false
	startTime = Obs.create false
	timeUsed = Obs.create 0
	size = 296 # render size of the canvas

	# if our local stored sketch is still valid, continue with it.
	# valid means we are still in the time frame and it isn't submitted
	if Db.local.peek('drawing', 'time') > getTime()-Config.drawTime() and !Db.shared.peek('drawings', Db.local.peek('drawing', 'id'))?
		# we are continuing a sketch! (update occurred?)
		drawingId = Db.local.peek 'drawing', 'id'
		myWordO.set Db.local.peek 'drawing', 'word'
		log "continue sketch", drawingId, myWordO.peek(), myWordO.peek('word')
		steps = Db.local.peek 'drawing', 'steps'
		colorO.set (Db.local.peek 'drawing', 'color')
		tintO.set (Db.local.peek 'drawing', 'tint')
		lineWidthO.set (Db.local.peek 'drawing', 'lineWidth')
		startTime.set (Db.local.peek 'drawing', 'time')
	else
		# call for a new word to sketch
		Server.call 'startDrawing', (drawing) !->
			if drawing is false
				log "You don't belong here! Wait for your turn."
				falseNavigationO.set true
				return
			if drawing is "out of words"
				log "We're out of words. Sorry."
				falseNavigationO.set true
				return

			log "got word to sketch:", drawing.id, drawing

			drawingId = drawing.id
			myWordO.set drawing

			App.trackActivity()
			startThinkTimer() # start

	Obs.onClean !-> # upgrade safeguard
		Db.local.set 'drawing',
			id: drawingId
			word: myWordO.peek()
			steps: steps
			color: colorO.peek()
			tint: tintO.peek()
			lineWidth: lineWidthO.peek()
			time: startTime.peek()
		log "drawing: onclean", Db.local.peek('drawing')

	Dom.div !-> # needs to be in obs scope for cleaning reasons
		if startTime.get()
			timeSinceStarted = getTime() - startTime.peek()
			Form.setPageSubmit !->
				submit()
			, true
			Obs.onTime DRAW_TIME-timeSinceStarted, !-> submit()
		else if thinkTimer.get()
			Obs.onTime THINK_TIME, !->
				log "thinkTimer espired"
				startTheClock()

		if startTime.get() or thinkTimer.get()
			return if firstSketch # no need to scare the user with this msg at first sketch
			Page.setBackConfirm
				title: tr("Are you sure?")
				message: tr("You will have to wait for 12 hours to sketch again.")

		Obs.interval 200, !->
			if st = thinkTimer.peek()
				timeUsed.set Math.min((getTime() - st), THINK_TIME)
			else if st = startTime.peek()
				timeUsed.set Math.min((getTime() - st), DRAW_TIME)

	# ------------ helper functions -------------

	getColor = (i=null) ->
		if i is null
			i = colorO.peek()
		t = tintO.peek()
		return DARK_COLORS[i] if t is 0
		return COLORS[i] if t is 1
		return BRIGHT_COLORS[i] if t is 2

	startThinkTimer = !->
		return if thinkTimer.peek() isnt false # timer already running
		thinkTimer.set getTime()

	startTheClock = !->
		return if startTime.peek() isnt false # timer already running
		thinkTimer.set false
		startTime.set getTime()

		# time's started, let's do setup
		addStep 'brush', {size: lineWidthO.peek()}
		addStep 'col', { col: getColor() }

	submit = !->
		time = 0|getTime()*.001

		if drawingId is false
			log "drawingId is false. Not submitting your drawing."
			return

		# convert steps to a more efficient format
		data = Encoding.encode steps

		# tell the server we're done
		log "Sending sketch to the server", myWordO.peek().wordId, time
		Server.sync 'addDrawing', drawingId, data, time, !-> # steps for raw array of objects
			Db.shared.set 'drawings', drawingId,
				memberId: App.memberId()
				wordId: myWordO.peek().wordId
				steps: steps
				time: time
		Db.local.remove 'drawing'
		Page.up()

	# add a drawing step to our recording
	addStep = (type, data) !->
		step = {}
		if data? then step = data
		step.type = type
		st = startTime.peek()
		if st
			step.time = Math.max(1, getTime() - st)
		else
			step.time = 1 # step before starting to draw.
		steps.push step

		# draw this step on the canvas
		cvs.addStep step

	toCanvasCoords = (pt) ->
		{
			x: Math.max 1, Math.min 999, Math.round (pt.x / size) * CANVAS_SIZE
			y: Math.max 1, Math.min 999, Math.round (pt.y / size) * CANVAS_SIZE
		}

	drawPhase = 0 # 0:ready, 1: started, 2: moving
	lastPoint = undefined
	touchHandler = (touches...) !->
		return if not touches.length
		t = touches[0] # TODO" should I iterate over this?
		pt = toCanvasCoords {x: t.xc, y: t.yc}

		if t.op&1
			lastPoint = pt # keep track of last point so we don't draw 1000s of tiny lines
			addStep 'move', lastPoint
			drawPhase = 1 # started

		else if drawPhase is 0 # if we're not drawing atm, we're done
			return true

		else if t.op&2
			return if startTime.peek() is false
			if not lastPoint? or distanceBetween(lastPoint, pt) > LINE_SEGMENT #let's not draw lines < minimum
				# TODO: also limit on delta angle and delta time
				addStep 'draw', pt
				lastPoint = pt
				drawPhase = 2 # moving

		else if t.op&4
			return if startTime.peek() is false
			if drawPhase is 1 # started but not moved, draw a dot
				addStep 'dot', pt
			drawPhase = 0
			lastPoint = undefined

		else
			return true

		return false # if we've handled it, let's stop the rest from responding too

	# ------------ button functions ---------------
	renderColorSelector = !->
		for i in [0...COLORS.length] then do (i) !->
			Dom.div !->
				Dom.cls 'button-block'
				Dom.div !->
					Dom.style
						height: '100%'
						width: '100%'
						borderRadius: '50%'
					Dom.style backgroundColor: getColor(i)
					tintO.get() # reactive on tint change
				Obs.observe !->
					Dom.style
						border: if colorO.get() is i then '4px solid grey' else 'none'
						padding: if colorO.get() is i then 0 else 4
				Dom.onTap !->
					colorO.set i
					addStep 'col', { col: getColor() }

	renderBrushSelector = !->
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
						border: if lineWidthO.get() is b.n then '4px solid grey' else 'none'
						padding: if lineWidthO.get() is b.n then 0 else 4
				Dom.onTap !->
					lineWidthO.set b.n
					addStep 'brush', { size: b.n }

	# ------------ compose dom -------------
	## background: '#4E5E7B'
	Dom.style backgroundColor: '#4E5E7B', height: '100%'

	Ui.top !->
		Dom.style
			backgroundColor: '#4E5E7B'
			color: 'white'
			textAlign: 'center'
			fontWeight: 'bold'
			margin: 0
			border: 0
		word = myWordO.get()
		if word
			Dom.text tr("Sketch %1 '%2'", word.prefix, word.word)
			Page.setTitle tr("Sketch %1 %2", word.prefix, word.word)
		else
			Dom.text "_" # prevent resizing when word has been retrieved
			Page.setTitle tr("Prepare to make a sketch")

	Obs.observe !->
		if startTime.get()
			Timer.render DRAW_TIME, timeUsed, 44
		else if thinkTimer.get()
			Timer.render THINK_TIME, timeUsed, 70, Page.width()/2-25

	cvs = false
	Dom.div !->
		Dom.style
			position: 'relative'
			margin: '0 auto'
		size = 296
		Obs.observe !-> # set size
			width = Page.width()
			height = Page.height()-3-40-80 # margin, top, shelf
			size = if height<(width*CANVAS_RATIO) then height/CANVAS_RATIO else width
			Dom.style width: size+'px', height: size*CANVAS_RATIO+'px'
		# render canvas, not hidden, but not responsive
		cvs = Canvas.render touchHandler, false, false
		# if we have steps (means we have recovered), draw them
		cvs.addStep step for step in steps

		Dom.div !->
			return if startTime.get()
			Dom.style
				position: 'absolute'
				top: '30%'
				width: '100%'
				fontSize: '90%'
				# pointerEvents: 'none' # don't be tappable
				textAlign: 'center'
			word = myWordO.get()
			return unless word
			Dom.text tr("Sketch %1", word.prefix)#, word.word)
			Dom.div !->
				Dom.style
					fontSize: '28px'
					textTransform: 'uppercase'
					fontFamily: "Bree Serif"
					letterSpacing: '2px'
				Dom.h2 word.word
			Ui.button tr("Let's go!"), !->
				# if startTime.peek() is false
				startTheClock()
			Dom.last().style
				display: 'inline-block'
				fontSize: '130%'
				padding: '12px'
				margin: '8px'
			Ui.emptyText tr("You have %1 seconds to sketch.", 0|DRAW_TIME*.001)

	# toolbar
	Dom.div !-> # shelf
		Dom.style
			Flex: true
			height: '80px'
			margin: 0
			paddingBottom: '4px'
			background: '#4E5E7B'
		Dom.div !->
			Dom.style Flex: true, height: '42px'
			Dom.overflow()
			Dom.div !->
				Dom.style
					Box: 'top center'
					minWidth: 40*COLORS.length + 'px'
					marginTop: '2px'
				renderColorSelector()

		Dom.div !->
			Dom.style Box: 'top'

			Dom.div !-> # undo button
				Dom.cls 'button-block'
				Icon.render
					data: 'arrowrotl'
					size: 20
					color: 'white'
					style: padding: '10px 8px'
					onTap: !-> addStep 'undo'

			Dom.div !->
				Dom.style Flex: true, Box: 'top center'
				renderBrushSelector()

			Dom.div !-> # lighter
				Dom.cls 'button-block'
				t = tintO.get()
				Icon.render
					data: 'brightness'+(if t>0 then 1 else 2)
					size: 20
					color: 'white'
					style: padding: '6px 8px 10px 6px'
				Dom.style
					border: if t>1 then '4px solid grey' else 'none'
					padding: if t>1 then 0 else 4
				Dom.onTap !->
					if t < 2 then tintO.incr 1
					addStep 'col', { col: getColor() }

			Dom.div !-> # darker
				Dom.cls 'button-block'
				t = tintO.get()
				Icon.render
					data: 'brightness'+(if t>1 then 2 else 4)
					size: 20
					color: 'white'
					style: padding: '6px 8px 10px 6px'
				Dom.style
					border: if t is 0 then '4px solid grey' else 'none'
					padding: if t is 0 then 0 else 4
				Dom.onTap !->
					if tintO.peek() > 0 then tintO.incr -1
					addStep 'col', { col: getColor() }

			Dom.div !-> # clear button
				Dom.cls 'button-block'
				Icon.render
					data: 'cancel'
					size: 20
					color: 'white'
					style: padding: '10px 8px'
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
