Comments = require 'comments'
Db = require 'db'
Dom = require 'dom'
App = require 'app'
Event = require 'event'
Obs = require 'obs'
Page = require 'page'
# Form = require 'form'
Time = require 'time'
Ui = require 'ui'
{tr} = require 'i18n'

Config = require 'config'
Draw = require 'draw'
Guess = require 'guess'
View = require 'view'

exports.render = !->
	pageName = Page.state.get(0)
	return Draw.render() if pageName is 'draw'
	return Guess.render() if pageName is 'guess'
	return View.render() if pageName is 'view'
	return renderScores() if pageName is 'scores'

	renderOverview()

renderOverview = !->
	Comments.enable
		messages:
			new: (c) -> tr("%1 added a new drawing", c.user)

	Obs.observe !->
		if (t = (Db.personal.get('lastDrawing', 'time')||0)+Config.cooldown()) < Date.now()*0.001
			Ui.item
				icon: 'add'
				content: tr("Start drawing")
				onTap: !->
					Page.nav 'draw'
		else
			Ui.item
				icon:'chronometer'
				color: '#999'
				content: !->
					Dom.text tr("Wait ")
					Time.deltaText t, 'duration'
				sub: tr("Before you can draw again")
				style: color: '#999'

	Db.shared.iterate 'drawings', (drawing) !->
		memberId = drawing.get('memberId')
		yourId = App.memberId()
		state = drawing.get 'members', yourId

		item =
			avatar: App.memberAvatar(memberId)
			onTap: !-> Page.nav {0:'view', '?drawing':drawing.key()}
		if Event.isNew(drawing.get('time'))
			item.style = color: '#5b0'

		if memberId is yourId # own drawing
			mem = drawing.get('members')
			what = Db.personal.get('words', drawing.key())||false
			if what
				item.content = !->
					Dom.userText tr("Your drawing of **%1**", what)
			else
				item.content = tr("Your drawing")
			if mem
				item.sub = !->
					Dom.text tr("Guessed by ")
					Dom.text (a = (App.memberName(+k) for k, v of mem)).join(" · ")
				item.afterIcon = !->
					View.renderPoints(Db.shared.get('scores', yourId, drawing.key())||0, 40)
			else
				item.sub = !->
					Dom.text tr("Guessed by no one yet")
		else if state? # you've guessed it
			log "trying to get word:", drawing.key()
			what = Db.personal.get('words', drawing.key())||false
			if what
				item.content = !->
					Dom.userText tr("%1 drew **%2**", App.memberName(memberId), what)
			else
				item.content = tr("Drawing by %1", App.memberName(memberId))
			if state >= 0
				item.sub = tr("Guessed by you in %1 second|s", state)
			else
				item.sub = tr("Failed to guess")
			item.afterIcon = !->
					View.renderPoints(Db.shared.get('scores', yourId, drawing.key()), 40)
		else # no state, so not guessed yet
			item.content = tr("Guess drawing by %1", App.memberName(memberId))
			item.sub= !->
				Dom.text "Drawn "
				Time.deltaText(drawing.get('time'))
			item.onTap = !->
				Page.nav {0:'guess', '?drawing':drawing.key()}

		Ui.item item

	, (drawing) ->
		-drawing.peek('time')|0
	Page.setFooter
		label: 'See scores'
		action: !-> Page.nav {0:'scores'}

renderScores = !->
	App.members.iterate (member) !->
		scores = Db.shared.get('scores', member.key())
		Ui.item
			avatar: member.get('avatar')
			content: member.get('name')
			sub: tr("Guessed %1 drawing|s", Object.keys(scores||{}).length)
			afterIcon: !->
				s = 0
				s += v for k, v of scores
				View.renderPoints(s, 40)
			onTap: !->
				App.showMemberInfo member.key()
	, (member) ->
		s = 0
		s += v for k, v of Db.shared.get('scores', member.key())
		-s