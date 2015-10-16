Db = require 'db'
Dom = require 'dom'
Plugin = require 'plugin'
Page = require 'page'
Ui = require 'ui'

Canvas = require 'canvas'
Drawing = require 'drawing'
Guess = require 'guess'

exports.render = !->
	switch Page.state.get(0)
		when 'draw'
			return Drawing.render()
		when 'guess'
			i = Page.state.get('drawing')
			drawing = Db.shared.ref('drawings').get(i)
			return Guess.render drawing

	Ui.button "New drawing", !->
		Page.nav 'draw'

	cnt = Db.shared.get('drawingCount')
	for i in [(cnt-1)..0] then do (i) !->
		Dom.div !->
			Dom.text "Guess #{i + 1}"
			Dom.onTap !->
				Page.nav {0:'guess', drawing:i}
