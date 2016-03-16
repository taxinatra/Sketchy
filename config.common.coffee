exports.canvasRatio = -> 1.283783784 # (296 * 380)
exports.canvasSize = -> 676
exports.drawTime = -> 45000 # ms
exports.thinkingTime = -> 20000 # ms
exports.guessTime = -> 60000 # ms
exports.cooldown = -> 3600*12 # 12 hours in sec
exports.guessRatio = -> 0.67 # about 2/3

exports.timeToScore = (time) ->
	if time < 15 then return 10
	if time < 30 then return 5
	if time < 45 then return 3
	return 1

exports.simpleHash = (s) ->
	hash = i = c = 0
	return hash unless s
	for i in [0...s.length] by 1
		c = s.charCodeAt(i)
		hash = (((hash << 5) - hash) + c) | 0 # Convert to 32bit integer
	hash # return