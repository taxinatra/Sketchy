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
	points = []
	colour = Obs.create 'black'

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
		ctx.lineWidth = 6
		Obs.observe !-> ctx.strokeStyle = colour.get()
		cvs = Dom.get()

		cvs.clear = !-> ctx.clearRect 0, 0, cvs.width(), cvs.height()

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

		isDrawing = false

		drawToPoint = (pt) !->
			points.push pt
			ctx.lineTo pt.x, pt.y
			ctx.stroke()

		isMoving = false
		start = (e) !->
			isDrawing = true
			isMoving = false
			pt = getCanvasXY e
			ctx.beginPath()
			ctx.moveTo pt.x, pt.y
			drawToPoint pt

		move = (e) !->
			return if not isDrawing
			currentPoint = getCanvasXY e
			return if distanceBetween(points[points.length-1], currentPoint) < LINE_SEGMENT #let's not draw ridiculously short 1px lines
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

		# capture events
		Dom.on 'mousedown', start
		Dom.on 'touchstart', start

		Dom.on 'mousemove', move
		Dom.on 'touchmove', move

		Dom.on 'mouseup', end
		Dom.on 'touchend', end

	Dom.div !->
		Dom.style
			border: '1px solid grey'
		for color in ['white', 'darkslategrey', '#FF6961', '#FDFD96', '#AEC6CF', '#77DD77', '#CFCFC4', '#FFD1DC', '#B39EB5', '#FFB347', '#836953'] then do (color) !->
			Dom.div !->
				Dom.style
					display: 'inline-block'
					backgroundColor: color
					width: '40px'
					height: '40px'
				Dom.onTap !->
					colour.set color

		Dom.div !->
			Dom.style
				display: 'inline-block'
				margin: '0 10px'
				boxSizing: 'border-box'
				border: '1px solid red'
				width: '40px'
				height: '40px'
			Dom.onTap !-> if cvs then cvs.clear()
