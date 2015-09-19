Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Plugin = require 'plugin'
Page = require 'page'
Server = require 'server'
Ui = require 'ui'

exports.render = !->
	CANVAS_WIDTH = CANVAS_HEIGHT = 500
	LINE_SEGMENT = 5
	lines = []
	colour = Obs.create 'darkslategrey'
	lineWidth = Obs.create 6

	cvs = false
	Dom.canvas !->
		Dom.prop('width', CANVAS_WIDTH)
		Dom.prop('height', CANVAS_HEIGHT)
		Dom.style
			backgroundColor: 'white'
			border: '1px solid grey'
			width: '100%'
			height: '80%'

		ctx = Dom.getContext('2d')
		ctx.lineJoin = ctx.lineCap = 'round'

		cvs = Dom.get()

		cvs.clear = !-> ctx.clearRect 0, 0, CANVAS_WIDTH, CANVAS_HEIGHT

		cvs.undo = !->
			log '----undo'
			lines.pop()
			cvs.redraw()

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

		cvs.redraw = !->
			cvs.clear()
			for line in lines
				firstPt = line.points[0]
				lastPt = line.points[line.points.length-1]
				drawLine line

		distanceBetween = (p1, p2) ->
			dx = p2.x - p1.x
			dy = p2.y - p1.y
			Math.sqrt (dx*dx + dy*dy)

		angleBetween = (p1, p2) ->
			dx = p2.x - p1.x
			dy = p2.y - p1.y
			Math.atan2 dx, dy

		getCanvasXY = (e) -> {
				x: Math.round((e.getTouchXY(cvs).x/cvs.width())*CANVAS_WIDTH)
				y: Math.round((e.getTouchXY(cvs).y/cvs.height())*CANVAS_HEIGHT)
			}

		startTime = false

		isDrawing = false

		points = []
		lastPoint = null
		drawToPoint = (pt) !->
			pt.time = Date.now() - startTime
			ctx.lineTo pt.x, pt.y
			ctx.stroke()
			points.push pt
			lastPoint = pt

		isMoving = false
		start = (e) !->
			isDrawing = true
			if not startTime
				startTime = Date.now()
			isMoving = false
			pt = getCanvasXY e
			ctx.beginPath()
			ctx.strokeStyle = colour.peek()
			ctx.lineWidth = lineWidth.peek()
			ctx.moveTo pt.x, pt.y
			drawToPoint pt

		move = (e) !->
			return if not isDrawing
			currentPoint = getCanvasXY e
			return if lastPoint? and distanceBetween(lastPoint, currentPoint) < LINE_SEGMENT #let's not draw ridiculously short 1px lines
			isMoving = true
			drawToPoint currentPoint

		end = (e) !->
			return if not isDrawing
			pt = getCanvasXY e
			if isMoving #draw a line
				drawToPoint pt
			else #draw a dot
				ctx.beginPath()
				ctx.arc(pt.x, pt.y, 1, 0, 2 * 3.14, true)
				ctx.stroke()
			isDrawing = false
			line = {colour: colour.peek(), lineWidth: lineWidth.peek(), points: points}
			lines.push line
			points = []

		# capture events
		Dom.on 'mousedown', start
		Dom.on 'touchstart', start

		Dom.on 'mousemove', move
		Dom.on 'touchmove', move

		Dom.on 'mouseup', end
		Dom.on 'touchend', end

	Dom.div !->
		Dom.style border: '1px solid grey'
		for c in ['white', 'darkslategrey', '#FF6961', '#FDFD96', '#AEC6CF', '#77DD77', '#CFCFC4', '#FFD1DC', '#B39EB5', '#FFB347', '#836953'] then do (c) !->
			Dom.div !->
				Dom.cls 'colour-block'
				Dom.style backgroundColor: c
				Obs.observe !->
					Dom.style
						border: if colour.get() is c then '1px dashed white' else 'none'
				Dom.onTap !-> colour.set c

		# undo button
		Dom.div !->
			Dom.cls 'colour-block'
			Dom.style
				border: '1px solid blue'
			Dom.onTap !-> if cvs then cvs.undo()

		# clear button
		Dom.div !->
			Dom.cls 'colour-block'
			Dom.style
				margin: '0 10px'
				border: '1px solid red'
			Dom.onTap !-> if cvs then cvs.clear()

		# brush sizes
		for size in [{t:'S',n:3}, {t:'M',n:6}, {t:'L',n:9}] then do (size) !->
			Dom.div !->
				Dom.cls 'colour-block'
				Dom.style
					border: '1px solid grey'
					lineHeight: '40px'
				Dom.text size.t
				Dom.onTap !-> lineWidth.set size.n

Dom.css
	'.colour-block':
		display: 'inline-block'
		boxSizing: 'border-box'
		width: '40px'
		height: '40px'
		cursor: 'pointer'
