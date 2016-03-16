App = require 'app'
Canvas = require 'canvas'
Comments = require 'comments'
Db = require 'db'
Dom = require 'dom'
Icon = require 'icon'
Modal = require 'modal'
Obs = require 'obs'
Page = require 'page'
Server = require 'server'
Time = require 'time'
Ui = require 'ui'
{tr} = require 'i18n'
Photo = require 'photo'

Config = require 'config'
Guess = require 'guess'

CANVAS_RATIO = Config.canvasRatio()

exports.renderPoints = renderPoints = (points, size, style=null) !->
	Dom.div !->
		Dom.style
			background: '#0077CF'
			borderRadius: '50%'
			fontSize: (if points < 1000 then (size*.5) else (size*.3)) + 'px'
			textAlign: 'center'
			width: size+'px'
			height: size+'px'
			color: 'white'
			Box: 'middle center'
		if style then Dom.style style
		Dom.text points

exports.render = !->
	drawingId = Page.state.get(0)
	unless drawingId # if we have no id, error
		log 'No drawing Id'
		return
	drawingR = Db.shared.ref('drawings', drawingId)
	myId = App.memberId()
	guessO = Obs.create false

	Obs.observe !->
		myTime = drawingR.get('members', myId)

		# score view is defined here. Guessing in guess.client.coffee
		log "me:", myId, "artist:", drawingR.get('memberId'), "myTime:", myTime
		# not my own drawing. not guessed, or busy guessing
		if myId isnt drawingR.get('memberId') and (!myTime? or myTime is -1)
			log "guessing"
			guessO.set true
		else
			guessO.set false

	Dom.style minHeight: '100%'
	Dom.div !-> # dom obs
		Dom.style margin: 0, minHeight: '100%'
		if guessO.get()
			Guess.render()
		else
			renderResult(drawingId)

renderResult = (drawingId) !->
	myId = App.memberId()
	drawingR = Db.shared.ref('drawings', drawingId)
	myTime = drawingR.get('members', myId)

	# --- result screen ---

	falseNavigationO = Obs.create false
	backgroundO = Obs.create ""

	Obs.observe !->
		if falseNavigationO.get()
			Ui.emptyText tr("It seems like you are not suppose to be here.")

	Dom.style minHeight: '100%', background: "rgba(255, 255, 255, 1)", height: ''

	Dom.style
		Box: 'vertical center'
		textAlign: 'center'

	state = 0

	renderTop = (opts) !->
		Dom.div !->
			Dom.style minHeight: '72px'
			Dom.h1 opts.header if opts.header
			Dom.text opts.content if opts.content
			if opts.content2
				Dom.br()
				Dom.br()
				Dom.text opts.content2

	renderAnswer = (drawingId) !->
		Dom.div !->
			Dom.style
				position: 'relative'
				width: '100%'
			word = Db.personal.get 'words', drawingId
			if word
				word = (/^([a-z]*\s)?(.*)$/i.exec word)[2]
				Dom.h2 !->
					Dom.style
						fontSize: '28px'
						textTransform: 'uppercase'
						fontFamily: "Bree Serif"
						letterSpacing: '2px'
					Dom.text word
			else
				log "You haven't guessed this question, but requested the answer. That's not very nice."
				falseNavigationO.set true
				return

			Icon.render
				data: 'play'
				size: 28
				style:
					position: 'absolute'
					top: '3px'
					right: '6px'
					padding: '6px'
					borderRadius: '50%'
				onTap: !->
					Page.nav !-> Dom.div !->
						Dom.style
							margin: 0
							height: '100%'
							width: '100%'
							Box: "center midden"
							background: '#DDD'
						cvs = Canvas.render null # render canvas
						steps = Db.shared.get('drawings', drawingId, 'steps')
						Page.back() unless steps
						steps = steps.split(';')
						startTime = Date.now()
						for data in steps then do (data) !->
							step = Canvas.decode(data)
							now = (Date.now() - startTime)
							if step.time > now
								Obs.onTime (step.time - now)/6, !->
									cvs.addStep step
							else
								cvs.addStep step

	renderScore = (drawingId) !->
		points = Db.shared.get('scores', myId, drawingId)
		Dom.div !->
			Dom.style Box: 'vertical center', minHeight: '116px'
			Dom.text tr("This earned you")
			if points
				renderPoints(points, 60, {margin:'12px 12px 4px'}) # points, size, style
			Dom.text if points>1 then tr("points") else tr("point")


	if drawingR.get('memberId') is myId # my drawing
		arr = (v for k, v of drawingR.get('members'))
		lowestTime = 99
		for i in arr
			if (i<lowestTime and i>=0) then lowestTime = i
		if arr.length
			if lowestTime is 99
				renderTop
					header: tr("Your sketch")
					content: tr("has not been successfully guessed yet")
				renderAnswer drawingId
				Dom.div !->
					Dom.style color: '#777', margin: '12px'
					Dom.text tr("You will be rewarded the same amount of points as the fastest player.")
			else
				renderTop
					header: tr("Your sketch")
					content: tr("has been guessed in %1 second|s", lowestTime)
				renderAnswer drawingId
				Dom.div !->
					Dom.style color: '#777', margin: '12px'
					Dom.text tr("You are awarded the same amount of points as the fastest player.")
				renderScore drawingId,
		else
			renderTop
				header: tr("Your sketch")
				content: tr("has not been guessed yet")
			renderAnswer drawingId
			Dom.div !->
				Dom.style color: '#777', margin: '12px'
				Dom.text tr("You will be rewarded the same amount of points as the fastest player.")
	else # you have guessed
		unless myTime # if we have no id, error
			falseNavigationO.set true
			return
		if myTime >= 0
			renderTop
				header: tr("Nice!")
				content: tr("It took you %1 seconds to guess:", 
				myTime)
			renderAnswer drawingId
			renderScore drawingId
		else # failed to guess
			renderTop
				header: tr("Too bad")
				content: tr("You have not guessed it correctly.")
				content2: tr("The correct answer was:")
			renderAnswer drawingId

	Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill
	Dom.div !->
		Dom.style textAlign: 'left', width:'100%', margin: 0, flexShrink: 0
		drawingR.iterate 'members', (member) !->
			log "member", member.get()
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
	Dom.div !->	Dom.style Flex: true, minHeight: '16px' # fill

	Dom.div !->
		Dom.style width: '100%', textAlign: 'left', _boxSizing: 'border-box', ChildMargin: 12, margin: 0
		Comments.inline
			store: ['drawings', drawingId, 'comments']
			postRpc: 'post' # redirect to server.coffee
			messages:
				correct: (c) -> tr("%1 guessed this sketch in %2 seconds!", c.user, c.value)
				failed: (c) -> tr("%1 failed to guess this sketch", c.user)

	Obs.observe !->
		bg = backgroundO.get()
		if bg
			Page.setBackground "no-repeat 50% 50%/cover url(" + bg + ")"
			Dom.transition background: "rgba(255, 255, 255, 0.9)"

	# invisible canvas
	cvs = Canvas.render null, true, false # render canvas in stealth mode
	# draw the image slightly delayed so the main render doesn't wait for it
	Dom.div !-> # obs scope for onClean
		Dom.style margin:0
		Obs.onTime 500, !->
			steps = drawingR.get('steps')
			return unless steps
			steps = steps.split(';')
			for data in steps then do (data) !->
				cvs.addStep Canvas.decode(data)

			log "Drawn. Canvas to png."
			backgroundO.set cvs.dom.toDataUrl()