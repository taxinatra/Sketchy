
exports.simpleHash = (s) ->
	hash = i = c = 0
	return hash unless s
	for i in [0...s.length] by 1
		c = s.charCodeAt(i)
		hash = (((hash << 5) - hash) + c) | 0 # Convert to 32bit integer
	hash # return
