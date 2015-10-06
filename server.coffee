Db = require 'db'

exports.client_addDrawing = (drawing) !->
	id = Db.shared.get('drawingCount') ? 0
	Db.shared.set 'drawings', id, drawing
	Db.shared.incr 'drawingCount'
