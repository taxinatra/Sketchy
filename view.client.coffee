App = require 'app'
Canvas = require 'canvas'
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
	drawingId = Page.state.get('?drawing')
	drawingR = Db.shared.ref('drawings', drawingId)

	Dom.style minHeight: '100%'

	overlay = (cb) !->
		Dom.style
			position: 'absolute'
			top: 0
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
		Dom.style Box: 'vertical center', textAlign: 'center', zIndex: 99

		state = 0
		Dom.div !->
			if drawingR.get('memberId') is App.memberId() # my drawing
				Dom.h1 tr("Your drawing")
				arr = (v for k, v of drawingR.get('members'))
				lowestTime = Math.min.apply(null, arr)||-1
				if arr.length
					if lowestTime <0
						Dom.text tr("has not been successfully guessed yet")
						state = 1
					else
						Dom.text tr("has been guessed in %1 second|s", lowestTime)
						state = 2
				else
					Dom.text tr("has not been guessed yet")
					state = 0
			else # you have guessed
				if myTime >= 0
					state = 2
					Dom.h1 tr("Nice!")
					Dom.text tr("You guessed it correctly in %1 seconds!", 
						myTime)
				else # failed to guess
					state = 1
					Dom.h1 tr("Shame")
					Dom.text tr("You have not guessed it correctly")
		return if state is 0 # lack of goto :p
		Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill
		if state is 2
			Dom.div !->
				Dom.style Box: 'vertical center', minHeight: '116px'
				Dom.text tr("This earned you")
				points = Config.timeToScore(myTime)
				renderPoints(points, 60, {margin:'12px 12px 4px'}) # points, size, style
				Dom.text if points>1 then tr("points") else tr("point")
			Dom.div !->	Dom.style Flex: true, minHeight: '20px' # fill
		Dom.div !->
			Dom.style Flex: true, textAlign: 'left', width:'100%'
			drawingR.iterate 'members', (member) !->
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
	Dom.div !->
		renderScoreScreen()

	Dom.div !->
		width = Page.width()
		height = Page.height()
		size = if height>(width*CANVAS_RATIO) then height/CANVAS_RATIO else width
		Dom.style
			width: '100%'
			height: '100%'
			margin: 0
			overflow: 'hidden'
			display: 'none'
		cvs = Canvas.render null # render canvas
		thisE = Dom.get()

		# draw the image slightly delayed so the main render doesn't wait for it
		setTimeout !->
			steps = drawingR.get('steps')
			return unless steps
			steps = steps.split(';')
			for step in steps then do (step) !->
				cvs.addStep Canvas.decode(step)
			thisE.style display: 'block'
		, 100
