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
	return renderScores() if pageName is 'scores'
	return View.render() if pageName # anything else

	renderOverview()

renderOverview = !->
	Comments.enable
		messages: # no longer generated
			new: (c) -> tr("%1 added a new drawing", c.user)

	Obs.observe !->
		if Db.shared.get 'outOfWords'
			Ui.item
				icon:'info'
				color: '#999'
				content: tr("No more words left to sketch")
				sub: tr("We know of your hardship and will add new words shortly.")
				style: color: '#999'
			return
		if (t = (Db.personal.get('wait')||0)+Config.cooldown()) < Date.now()*0.001
			Ui.item
				icon: 'add'
				content: tr("Start sketching")
				onTap: !->
					Page.nav 'draw'
		else
			Ui.item
				icon:'chronometer'
				color: '#999'
				content: !->
					Dom.text tr("Wait ")
					Time.deltaText t, 'duration'
				sub: !->
					wg = Db.personal.get('waitGuessed')
					if wg>1
						Dom.text tr("Or until %1 more people guessed your previous sketch", wg)
					else if wg is 1
						Dom.text tr("Or until %1 more person guessed your previous sketch", wg)
					else
						Dom.text tr("Or until more people guessed your previous sketch")
				style: color: '#999'

	Db.shared.iterate 'drawings', (drawing) !->
		memberId = drawing.get('memberId')
		yourId = App.memberId()
		state = drawing.get 'members', yourId

		item =
			avatar: App.memberAvatar(memberId)
			onTap: !-> Page.nav {0:drawing.key()}
		isNew = Event.isNew(drawing.get('time'))
		if isNew
			item.style = color: '#5b0'

		if memberId is yourId # own sketch
			mem = drawing.get('members')
			what = Db.personal.get('words', drawing.key())||false
			if what
				r = /^(a[a-z]?)?\s?(.*)$/i.exec what
				prefix = if [1] then r[1] + " " else ""
				what = r[2]
				item.content = !->
					Dom.userText tr("You sketched %1", prefix)
					Dom.span !->
						color = if isNew then '#5b0' else '#0077CF'
						Dom.style color: color, fontWeight: 'bold'
						Dom.text what
			else
				item.content = tr("Your sketch")
			if mem
				item.sub = !->
					Dom.text tr("Guessed by ")
					Dom.text (a = (App.memberName(+k) for k, v of mem)).join(" · ")
				item.afterIcon = !->
					Event.renderBubble ['/'+drawing.key()+"?comments"]
					View.renderPoints(Db.shared.get('scores', yourId, drawing.key())||0, 40)
			else
				item.sub = !->
					Dom.text tr("Guessed by no one yet")
		else if state? and state isnt -1 # you've guessed it
			what = Db.personal.get('words', drawing.key())||false
			if what
				r = /^(a[a-z]?)?\s?(.*)$/i.exec what
				prefix = if [1] then r[1] + " " else ""
				what = r[2]

				item.content = !->
					Dom.userText tr("%1 sketched %2", App.memberName(memberId), prefix)
					Dom.span !->
						color = if isNew then '#5b0' else '#0077CF'
						Dom.style color: color, fontWeight: 'bold'
						Dom.text what
			else
				item.content = tr("Sketching by %1", App.memberName(memberId))
			if state >= 0
				item.sub = tr("Guessed by you in %1 second|s", state)
			else
				item.sub = tr("Failed to guess")
			item.afterIcon = !->
					Event.renderBubble ['/'+drawing.key()+"?comments"]
					View.renderPoints(Db.shared.get('scores', yourId, drawing.key()), 40)
		else # no state, so not guessed yet
			item.content = tr("Guess sketch by %1", App.memberName(memberId))
			item.sub= !->
				Dom.text "Sketched "
				Time.deltaText(drawing.get('time'))
			item.onTap = !->
				Page.nav {0:'guess', '?drawing':drawing.key()}
			item.afterIcon = !->
				Event.renderBubble ['/'+drawing.key()+"?comments"]

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
			sub: tr("Guessed %1 sketching|s", Object.keys(scores||{}).length)
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