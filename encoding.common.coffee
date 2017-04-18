jiffy = 10 # in ms

exports.simpleHash = (s) ->
	hash = i = c = 0
	return hash unless s
	for i in [0...s.length] by 1
		c = s.charCodeAt(i)
		hash = (((hash << 5) - hash) + c) | 0 # Convert to 32bit integer
	hash # return

# encode version 3
encodeInt = (val,signed) -> # into asci range 35..126 -> 92 options
	if signed
		# encode sign is lsb
		val = if val<0 then (-2*val)|1 else val*2
	res = ''
	loop
		# encode end-of-int in lsb
		if val < 46
			res += String.fromCharCode(35 + val*2 + 1)
			break
		res += String.fromCharCode(35 + (val%46)*2)
		val = 0 | (val / 46)
	return res

decodeInt = (str, pos=0, signed=false) -> # returns [val,newPos]
	val = 0
	base = 1
	loop
		chr = str.charCodeAt(pos++) - 35
		unless chr>=0 and chr<92
			throw new Error "invalid coded int"
		val += base * (chr>>1)
		if chr&1 # last char for this int
			if signed
				val = if val&1 then -(val>>1) else (val>>1)
			return [val,pos]
		base *= 46

testInt = (str, pos=0, signed=false) -> # returns [val,newPos]
	val = 0
	base = 1
	loop
		chr = str.charCodeAt(pos++) - 35
		unless chr>=0 and chr<92
			return null # in test mode, we want to know if we failed
		val += base * (chr>>1)
		if chr&1 # last char for this int
			if signed
				val = if val&1 then -(val>>1) else (val>>1)
			return [pos]
		base *= 46

exports.encode = (data) ->
	lastTime = 0
	lastX = 338 # never change these!
	lastY = 434 # never change these!

	# drawing: command...
	#
	# command: time ( '!' specialCommand | x y )
	#
	# specialCommand:
	# specialCommand:
	#    0, move: x y, move to position
	#    2, dot:  x y, move to position and set a dot
	#    3, col: color, set drawing color
	#    4, brush: size, set brush size
	#    5, clear
	#    6, undo
	#
	# time: unsigned encoded int, time delta in 10ms increments
	# x: signed encoded int, x coordinate delta
	# y: signed encoded int, y coordinate delta
	# color: 6 character color code
	# size: unsigned encoded int

	encodeDraw = (step) -> # draw is done more efficient
		r = ""
		deltaTime = step.time-lastTime
		deltaX = Math.round(step.x) - lastX
		deltaY = Math.round(step.y) - lastY

		r += encodeInt Math.ceil(deltaTime/jiffy), false # time is unsigned and expressed in 10ms increments
		r += encodeInt deltaX, true # coordinates are signed
		r += encodeInt deltaY, true # coordinates are signed

		lastX += deltaX
		lastY += deltaY
		lastTime = step.time

		return r

	encodeSpecial = (step) ->
		deltaTime = step.time-lastTime
		lastTime = step.time
		r = encodeInt Math.ceil(deltaTime/jiffy), false # time is unsigned and expressed in 10ms increments
		r += "!" # note this is a 'special' step
		r += ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'].indexOf(step.type)
		if step.x
			deltaX = Math.round(step.x) - lastX
			r += encodeInt deltaX, true # coordinates are signed
			lastX += deltaX
		if step.y
			deltaY = Math.round(step.y) - lastY
			r += encodeInt deltaY, true # coordinates are signed
			lastY += deltaY
		if step.size
			r += encodeInt step.size, false # brush sizes are unsigned
		if step.col
			r += (""+step.col).substr(1) # skip the hash of colors

		return r

	# make encoding
	r = "v3"
	for step in data
		if step.type is 'draw'
			r += encodeDraw(step)
		else
			r += encodeSpecial(step)
	return r

# decode version 3
exports.decode = (data) ->
	lastTime = 0
	lastX = 338 # never change this!
	lastY = 434 # never change this!

	res = []
	return unless data.length
	return unless !!data.match(/^v3/)[0] # check if this is a v3 encoding
	i = 2 # skip the 'v3' bit

	while i < data.length
		r = {}
		# time
		[t, i] = decodeInt(data, i, false)
		lastTime += t*jiffy
		r.time = lastTime

		if data[i] is '!' # special step
			i++
			type = 0|data[i++]
			r.type = ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'][type]
			if r.type in ['move', 'draw', 'dot']
				# x
				[x, i] = decodeInt(data, i, true)
				lastX+=x
				r.x = lastX
				# y
				[y, i] = decodeInt(data, i, true)
				lastY+=y
				r.y = lastY
			else if r.type is 'col'
				r.col = '#' + data.substr(i,6)
				i+=6
			else if r.type is 'brush'
				[s, i] = decodeInt(data, i, false)
				r.size = s
		else # draw step
			r.type = 'draw'
			# x
			[x, i] = decodeInt(data, i, true)
			lastX+=x
			r.x = lastX
			# y
			[y, i] = decodeInt(data, i, true)
			lastY+=y
			r.y = lastY
		res.push r
	return res

exports.test = (data) ->
	return unless data.length
	return unless !!data.match(/^v3/)[0] # check if this is a v3 encoding
	i = 2 # skip the 'v3' bit

	while i < data.length
		r = {}
		# time
		i = testInt(data, i, false, true)
		return false if i is null

		if data[i] is '!' # special step
			i++
			type = 0|data[i++]
			r.type = ['move', 'draw', 'dot', 'col', 'brush', 'clear', 'undo'][type]
			if r.type in ['move', 'draw', 'dot']
				i = testInt(data, i, true, true)
				return false if i is null
				i = testInt(data, i, true, true)
				return false if i is null
			else if r.type is 'col'
				i+=6
			else if r.type is 'brush'
				i = testInt(data, i, false, true)
				return false if i is null
		else # draw step
			i = testInt(data, i, true, true)
			return false if i is null
			i = testInt(data, i, true, true)
			return false if i is null
	return true

# decode version 2
exports.decode2 = (data) ->
	lastTime = 0
	lastX = 338 # never change this!
	lastY = 434 # never change this!
	i = 0

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

		return r

	decodeDraw = (step) ->
		# Draw encoding is the following:
		# A datapoint has 3-7 characters. We use the charcodes 32..125 (first 32 are not handy to use)
		# First char charcode (32..125) is the delta time (in 10ms increments) since last datapoint.
		# Second char for the deltaX.
		#	if that char is 126 (~) the value is 47 (or -47) plus the next char.
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

		return r

	r = []
	while i < data.length
		if data[i] is '~' # other
			i+=1 # skip the tilde
			r.push decodeStep(data.substr(i,12))
		else # draw
			r.push decodeDraw(data.substr(i,7))
	return r

# decode version 1
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