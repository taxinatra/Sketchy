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
	drawingId = Page.state.get(0)
	drawingR = Db.shared.ref('drawings', drawingId)

	Dom.style minHeight: '100%'

	overlay = (cb) !->
		Dom.style
			# position: 'absolute'
			# top: 0
			width: '100%'
			height: '100%'
			margin: 0
			ChildMargin: 16
			Box: 'middle center'
			background: "rgba(255, 255, 255, 0.9)"
			color: 'black'
		cb()

	renderScoreScreen = !->	overlay !->
		myTime = drawingR.get('members', App.memberId())
		Dom.style Box: 'vertical center', textAlign: 'center'

		state = 0
		Dom.div !->
			Dom.style minHeight: '105px'
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
						Page.up()

		return if state is 0 # lack of goto :p
		Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill
		if state is 2
			Dom.div !->
				Dom.style Box: 'vertical center', minHeight: '116px'
				Dom.text tr("This earned you")
				points = Db.shared.get('scores', App.memberId(), drawingId)||0
				renderPoints(points, 60, {margin:'12px 12px 4px'}) # points, size, style
				Dom.text if points>1 then tr("points") else tr("point")
			Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill
		Dom.div !->
			Dom.style textAlign: 'left', width:'100%', margin: 0, minHeight: '100px'
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

	# --- compose DOM ---

	Dom.style height: '100%', overflow: 'hidden'

	Dom.div !->
		Obs.observe !->
			width = Page.width()
			height = Page.height()
			size = if height>(width*CANVAS_RATIO) then height/CANVAS_RATIO else width
			widthMargin = Math.max 0, (size-width)/2
			heightMargin = Math.max 0, (size*CANVAS_RATIO-height)/2
			log size, size*CANVAS_RATIO,':', width, height, widthMargin, heightMargin
			Dom.style
				position: 'absolute'
				top: -heightMargin+'px'
				left: -widthMargin+'px'
				width: size
				height: size*CANVAS_RATIO
				# if you wonder why '100%' isn't used: android <4.4 doesn't like it.
				margin: 0
				overflow: 'hidden'
		cvs = Canvas.render null # render canvas
		thisE = Dom.get()

		# draw the image slightly delayed so the main render doesn't wait for it
		setTimeout !->
			steps = drawingR.get('steps')
			return unless steps
			startTime = Date.now()
			steps = steps.split(';')
			for data in steps then do (data) !->
				step = Canvas.decode(data)
				now = (Date.now() - startTime)
				# speed times 8!
				if step.time/8 > now
					Obs.onTime (step.time/8 - now), !->
						cvs.addStep step
				else
					cvs.addStep step
		, 0

	Dom.div !->
		Dom.overflow()
		Dom.style
			_transform: "translateY(#{'0px'})" # need to make this a hardware layer. or zIndex doesn't work
			height: '100%'
		renderScoreScreen()

		Dom.div !->
			Dom.style width: '100%', textAlign: 'left', _boxSizing: 'border-box', ChildMargin: 12
			Comments.inline
				store: ['drawings', drawingId, 'comments']
				postRpc: 'post' # redirect to server.coffee