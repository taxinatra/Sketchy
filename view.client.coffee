App = require 'app'
Canvas = require 'canvas'
Comments = require 'comments'
Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Page = require 'page'
Server = require 'server'
Time = require 'time'
Ui = require 'ui'
{tr} = require 'i18n'
Photo = require 'photo'

Config = require 'config'

CANVAS_RATIO = Config.canvasRatio()

exports.renderPoints = renderPoints = (points, size, style=null) !->
	Dom.div !->
		Dom.style
			background: '#0077CF'
			borderRadius: '50%'
			fontSize: '120%'
			textAlign: 'center'
			width: size+'px'
			height: size+'px'
			color: 'white'
			Box: 'middle center'
		if style then Dom.style style
		Dom.text points

exports.render = !->
	falseNavigationO = Obs.create false
	backgroundO = Obs.create ""

	Obs.observe !->
		if falseNavigationO.get()
			Ui.emptyText tr("It seems like you are not suppose to be here.")

	drawingId = Page.state.get(0)
	unless drawingId # if we have no id, error
		falseNavigationO.set true
		return

	drawingR = Db.shared.ref('drawings', drawingId)

	Dom.style minHeight: '100%', background: "rgba(255, 255, 255, 1)"

	myTime = drawingR.get('members', App.memberId())
	unless myTime # if we have no id, error
		falseNavigationO.set true
		return
	Dom.style
		Box: 'vertical center'
		textAlign: 'center'

	state = 0
	Dom.div !->
		Dom.style minHeight: '130px'
		if drawingR.get('memberId') is App.memberId() # my drawing
			Dom.h1 tr("Your sketch")
			arr = (v for k, v of drawingR.get('members'))
			lowestTime = 99
			for i in arr
				if (i<lowestTime and i>=0) then lowestTime = i
			if arr.length
				if lowestTime is 99
					Dom.text tr("has not been successfully guessed yet")
					Dom.div !->
						Dom.style color: '#777', margin: '12px'
						Dom.text tr("You will be rewarded the same amount of points as the fastest player.")
					state = 1
				else
					Dom.text tr("has been guessed in %1 second|s", lowestTime)
					Dom.div !->
						Dom.style color: '#777', margin: '12px'
						Dom.text tr("You are awarded the same amount of points as the fastest player.")
					state = 2
			else
				Dom.text tr("has not been guessed yet")
				Dom.div !->
					Dom.style color: '#777', margin: '12px'
					Dom.text tr("You will be rewarded the same amount of points as the fastest player.")
				state = 0
		else # you have guessed
			if myTime >= 0
				state = 2
				Dom.h1 tr("Nice!")
				Dom.text tr("It took you %1 seconds to guess:", 
					myTime)
			else # failed to guess
				state = 1
				Dom.h1 tr("Too bad")
				Dom.text tr("You have not guessed it correctly.")
				Dom.br()
				Dom.br()
				Dom.text tr("The correct answer was:")

			wordO = Obs.create false
			Dom.h2 !->
				if word = wordO.get()
					Dom.style fontSize: '28px', textTransform: 'uppercase'
					Dom.text word
				else
					Dom.style height: '49px'
			Server.call "getWord", drawingId, (word) !->
				if word
					wordO.set word
				else
					log "You haven't guessed this question, but requested the answer. That's not very nice."
					falseNavigationO.set true

	return if state is 0 # lack of goto :p
	Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill
	if state is 2
		points = Db.shared.get('scores', App.memberId(), drawingId)
		if points
			Dom.div !->
				Dom.style Box: 'vertical center', minHeight: '116px'
				Dom.text tr("This earned you")
				renderPoints(points, 60, {margin:'12px 12px 4px'}) # points, size, style
				Dom.text if points>1 then tr("points") else tr("point")
			Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill
	Dom.div !->
		Dom.style textAlign: 'left', width:'100%', margin: 0, flexShrink: 0
		drawingR.iterate 'members', (member) !->
			return if member.get() is -1 # skip members who are currently guessing
			Ui.item
				prefix: !-> renderPoints(Db.shared.get('scores', member.key(), drawingId)||0, 40, {marginRight:'12px'})
				avatar: App.memberAvatar(member.key())
				content: App.memberName(member.key())
				afterIcon: !-> Dom.div !->
					Dom.style
						border: '1px solid #999'
						borderRadius: '2px'
						padding: "4px 8px"
					if member.get() >= 0
						Dom.text tr("%1 sec", member.get())
					else
						Dom.text "failed"
				onTap: !->
					App.showMemberInfo(member.key())
		, (member) ->
			s = member.peek()
			if s <0 then s = 999
			return s
	Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill

	Dom.div !->
		Dom.style width: '100%', textAlign: 'left', _boxSizing: 'border-box', ChildMargin: 12, margin: 0
		Comments.inline
			store: ['drawings', drawingId, 'comments']
			postRpc: 'post' # redirect to server.coffee

	Obs.observe !->
		bg = backgroundO.get()
		if bg
			Page.setBackground "no-repeat center url(" + bg + ")"
			Dom.transition background: "rgba(255, 255, 255, 0.9)"

	# invisible canvas
	cvs = Canvas.render null, true # render canvas in stealth mode
	# draw the image slightly delayed so the main render doesn't wait for it
	Dom.div !-> # obs scope for onClean
		Obs.onTime 500, !->
			steps = drawingR.get('steps')
			return unless steps
			startTime = Date.now()
			steps = steps.split(';')
			for data in steps then do (data) !->
				step = Canvas.decode(data)
				now = (Date.now() - startTime)
				cvs.addStep step

			log "Drawn. Canvas to png."
			backgroundO.set cvs.dom.toDataUrl()