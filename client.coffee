Db = require 'db'
Dom = require 'dom'
App = require 'app'
Page = require 'page'
# Form = require 'form'
Ui = require 'ui'
{tr} = require 'i18n'

Draw = require 'draw'
Guess = require 'guess'

exports.render = !->
	pageName = Page.state.get(0)
	log "page state:", pageName
	return Draw.render() if pageName is 'draw'
	return Guess.render() if pageName is 'guess'

	renderOverview()

renderOverview = !->
	Ui.item
		icon: 'add'
		content: tr("Start drawing")
		onTap: !->
			Page.nav 'draw'

	Db.shared.iterate 'drawings', (drawing) !->
		memberId = drawing.get('userId')
		Ui.item
			avatar: App.memberAvatar(memberId)
			content: tr("Guess drawing by %1", App.memberName(memberId))
			onTap: !->
				log "navigating to:", drawing.key()
				Page.nav {0:'guess', '?drawing':drawing.key()}
	, (drawing) ->
		drawing.time|0
	Page.setFooter
		label: 'See scores'
