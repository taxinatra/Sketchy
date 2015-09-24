Db = require 'db'

exports.client_addDrawing = (drawing) !->
	id = Db.shared.incr 'drawingCount'
	Db.shared.set 'drawings', id, drawing
