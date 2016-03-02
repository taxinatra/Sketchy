exports.canvasRatio = -> 1.283783784 # (296 * 380)
exports.canvasSize = -> 676
exports.drawTime = -> 45000 # ms
exports.guessTime = -> 50000 # ms
exports.cooldown = -> 3600*4 # 4 hours in sec

exports.timeToScore = (time) ->
	if time < 10 then return 10
	if time < 20 then return 5
	if time < 30 then return 3
	return 1

exports.simpleHash = (s) ->
	hash = i = c = 0
	return hash unless s
	for i in [0...s.length] by 1
		c = s.charCodeAt(i)
		hash = (((hash << 5) - hash) + c) | 0 # Convert to 32bit integer
	hash # return
