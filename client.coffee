Db = require 'db'
Dom = require 'dom'
Plugin = require 'plugin'
Page = require 'page'
Ui = require 'ui'
{tr} = require 'i18n'

Canvas = require 'canvas'

exports.render = !->
	if pageName = Page.state.get(0)
		log pageName
		if p = load pageName
			p.render()
		else
			Dom.text tr("Loading...")
		return

	Ui.button "New drawing", !->
		Page.nav 'draw'

	cnt = Db.shared.get('drawingCount')
	for i in [(cnt-1)..0] then do (i) !->
		Dom.div !->
			Dom.text "Guess #{i + 1}"
			Dom.onTap !->
				Page.nav {0:'guess', drawing:i}
