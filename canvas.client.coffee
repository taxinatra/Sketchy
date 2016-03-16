Dom = require 'dom'
Obs = require 'obs'
Page = require 'page'

Config = require 'config'

CANVAS_SIZE = Config.canvasSize()
CANVAS_RATIO = Config.canvasRatio()

jiffy = 10 # in ms

exports.render = (touchHandler, hidden=false, responsive=true) !->
	width = CANVAS_SIZE
	height = CANVAS_SIZE*CANVAS_RATIO
	steps = []
	ctx = cvs = null

	Dom.div !-> # define container
		if responsive# we don't need to resize if we're hidden
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
				Obs.observe !->
					Obs.nextTick !-> # set size
						width = containerE.width()
						height = containerE.height()
						size = if height<(width*CANVAS_RATIO) then height/CANVAS_RATIO else width
						containerE.style
							width: size+'px'
							height: size*CANVAS_RATIO+'px'
							Flex: false
							margin: "auto auto"

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
		# log "step", step
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

exports.encode = (data) ->
	lastTime = 0
	lastX = 338 # never change these!
	lastY = 434 # never change these!

	# Draw encoding is the following:
	# A datapoint has 3-7 characters. We use the charcodes -32 (first 32 are not handy to use)
	# First char charcode (32-126) if the delta time since last datapoint.
	# Second char for the deltaX.
	#	if that char is 136 (~) the value is 47 (or -47) plus the next char.
	#	same for the possible next char (with +94)
	#	the last char is signed with -47 for negative values.
	# Then the same for the deltaY.

	# Example 1: !aC decodes to:
	#	! = 33-32 (actii offset) = 1 delta time (times jiffy is 10ms)
	#	a = 97-32 (ascii offset) = 65 -47 (signing) = 18
	#	C = 43-32 (ascii offset) = 11 -47 (signing) = -36

	# Example 2: H~~G~p decodes to:
	#	H = 72-32 = 40 delta time (times jiffy is 400ms)
	#	~ = add 47 to next value
	#	~ = add 47 to next value
	#	G = 71-32 = 39 -47 (signing) = -8. -8-47-47 = -102
	#	~ = add 47 to next value
	#	p = 112-32 = 80 -47 (signing) = 33. 33+47 = 80
	encodeStep = (step) -> # draw is done more efficient
		r = ""
		# log step, lastTime
		deltaTime = step.time-lastTime
		deltaX = Math.round(step.x) - lastX
		deltaY = Math.round(step.y) - lastY

		# if time, or coordinates are too big (or too small) use normal encoding
		if deltaTime >= 931 # too big deltaTime!
			doOther = true
		if deltaX >= 141 or deltaX <= -141# too big or small deltaX!
			doOther = true
		if deltaY >= 141 or deltaY <= -141# too big or small deltaX!
			doOther = true
		if doOther # do that
			return encodeOther (step)

		r += String.fromCharCode(Math.ceil(deltaTime/jiffy)+32) # write time

		# if a coordinate is to big (or too small) use the next char.
		x = Math.abs(deltaX)
		while x>47
			r += '~' # 126
			x -= 47
		r+=String.fromCharCode((deltaX%47)+47+32)

		y = Math.abs(deltaY)
		while y>47
			r += '~' # 126
			y -= 47
		r+=String.fromCharCode((deltaY%47)+47+32)

		# encode drawing
		# log "draw:", deltaTime, deltaX, deltaY, "(", lastX, lastY, ")"

		lastX += deltaX
		lastY += deltaY
		lastTime = step.time

		return r

	encodeOther = (step) -> # anything else
		deltaTime = step.time-lastTime
		r = ""
		r += String.fromCharCode(94+32) # max time flags 'other'

		# type
		r += ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'].indexOf(step.type)
		# value
		if step.x
			r += ("000" + Math.round(step.x)).substr(-3)
			lastX = Math.round(step.x)
		if step.y
			r += ("000" + Math.round(step.y)).substr(-3)
			lastY = Math.round(step.y)
		if step.size then r += ("000000" + step.size).substr(-6)
		if step.col then r += (""+step.col).substr(1) # skip the hash of colors
		# time
		r += ("00000" + Math.ceil(deltaTime/jiffy)).substr(-5) # 5 chars is enough.

		lastTime = step.time
		# log step.time, ": ", r
		return r

	r = ""
	for step in data
		if step.type is 'draw'
			r += encodeStep(step)
		else
			r += encodeOther(step)
	return r

exports.decode = (data) ->
	lastTime = 0
	lastX = 338 # never change these!
	lastY = 434 # never change these!
	i = 0

	# log "start decode", lastX, lastY
	decodeStep = (step) ->
		r = {} #TXXXYYYttttt
		type = 0|step[0]
		r.type = ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'][type] # first char
		if r.type in ['move', 'draw', 'dot']
			r.x = 0|step.substr(1,3)
			r.y = 0|step.substr(4,3)
			lastX = r.x
			lastY = r.y
		else if r.type is 'col'
			r.col = '#' + step.substr(1,6)
		else if r.type is 'brush'
			r.size = 0|step.substr(1,6)
		if type > 4 # clear or undo
			r.time = lastTime+=(0|step.substr(1,5))*jiffy
			i+=6 # move cursor
		else
			r.time = lastTime+=(0|step.substr(7,5))*jiffy
			# r.time = 0|step.substr(7,5)
			i+=12 # move cursor

		lastTime = r.time

		# log "decode other", step, r
		return r

	decodeDraw = (step) ->
		r = {}
		r.type = 'draw'
		r.time = lastTime + (step.charCodeAt(0)-32)*jiffy

		l = 1
		# X
		if step[l] is '~' and step[l+1] is '~' # use 2 extra chars
			l+=2
			r.x = step.charCodeAt(l)-47-32
			if r.x>0 then r.x+=94 else r.x-=94
		else if step[l] is '~' # use 1 extra chars
			l+=1
			r.x = step.charCodeAt(l)-47-32
			if r.x>0 then r.x+=47 else r.x-=47
		else # use no extra chars
			r.x = step.charCodeAt(l)-47-32
		l+=1

		# Y
		if step[l] is '~' and step[l+1] is '~' # use 2 extra chars
			l+=2
			r.y = step.charCodeAt(l)-47-32
			if r.y>0 then r.y+=94 else r.y-=94
		else if step[l] is '~' # use 1 extra chars
			l+=1
			r.y = step.charCodeAt(l)-47-32
			if r.y>0 then r.y+=47 else r.y-=47
		else # use no extra chars
			r.y = step.charCodeAt(l)-47-32
		l+=1

		r.x = lastX + r.x
		r.y = lastY + r.y

		i+=l # move cursor
		lastTime = r.time
		lastX = r.x
		lastY = r.y

		# log "decode draw", step, r, l
		return r

	r = []
	while i < data.length
		if data[i] is '~' # other
			i+=1 # skip the tilde
			r.push decodeStep(data.substr(i,12))
		else # draw
			r.push decodeDraw(data.substr(i,7))
	return r

exports.decodeOld = (data) ->
	decodeStep = (step) ->
		# log "decode", step
		r = {} #TXXXYYYttttt
		type = 0|step[0]
		r.type = ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'][type] # first char
		if r.type in ['move', 'draw', 'dot']
			r.x = 0|step.substr(1,3)
			r.y = 0|step.substr(4,3)
			lastX = r.x
			lastY = r.y
		else if r.type is 'col'
			r.col = '#' + step.substr(1,6)
		else if r.type is 'brush'
			r.size = 0|step.substr(1,6)
		if type > 4 # clear or undo
			r.time = (0|step.substr(1,5))
		else
			r.time = (0|step.substr(7,5))

		return r

	r = []
	data = data.split(';')
	for step in data
		r.push decodeStep(step)
	return r