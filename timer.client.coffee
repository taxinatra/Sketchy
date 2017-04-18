Dom = require 'dom'
Obs = require 'obs'

exports.render = (maxTime, elapsedO, top=4, right=4, pauseO=false, pauseTime=10) !->

	renderPauseMode = !->
		Dom.addClass "timer"
		Dom.style
			position: 'absolute'
			width: '50px'
			height: '50px'
			top: top+'px'
			right: right+'px'
			margin: '0 auto'
			borderRadius: '50%'
			border: '1px solid white'
			zIndex: 99
			opacity: '0.75'
			pointerEvents: 'none' # don't be tappable
		Obs.observe !->
			color = '#ec9b00'
			remaining = pauseTime - elapsedO.get()
			proc = 360/pauseTime*remaining
			if proc > 180
				nextdeg = 90 - proc
				Dom.style
					backgroundImage: "linear-gradient(90deg, #{color} 50%, transparent 50%, transparent), linear-gradient(#{nextdeg}deg, white 50%, #{color} 50%, #{color})"
			else
				nextdeg = -90 - (proc-180)
				Dom.style
					backgroundImage: "linear-gradient(#{nextdeg}deg, white 50%, transparent 50%, transparent), linear-gradient(270deg, white 50%, #{color} 50%, #{color})"
		Dom.div !->
			Dom.style
				position: 'absolute'
				width: '30px'
				height: '30px'
				backgroundColor: 'white'
				borderRadius: '50%'
				margin: "10px 0 0 10px"
				textAlign: 'center'
				lineHeight: '30px'
				fontSize: '16px'
			Obs.observe !->
				remaining = pauseTime - elapsedO.get()
				Dom.text (remaining * .001).toFixed(0)

		Icon.render
			data: 'pause'
			size: 30
			style:
				position: 'absolute'
				right: '55px'
				top: '10px'
		Dom.last().addClass 'blink'
		Dom.css
			'.blink':
				animation: "blinker 1s linear infinite"

			"@keyframes blinker":
				'50%':
					'opacity': '0.0'

			# Dom.style
			# 	position: 'absolute'
			# 	width: '30px'
			# 	height: '30px'
			# 	backgroundColor: 'white'
			# 	borderRadius: '50%'
			# 	margin: "10px 0 0 10px"
			# 	textAlign: 'center'
			# 	lineHeight: '30px'
			# 	fontSize: '16px'
			# Obs.observe !->
			# 	remaining = pauseTime - elapsedO.get()
			# 	Dom.text (remaining * .001).toFixed(0)


	renderNormalMode = !->
		Dom.addClass "timer"
		Dom.style
			position: 'absolute'
			width: '50px'
			height: '50px'
			top: top+'px'
			right: right+'px'
			margin: '0 auto'
			borderRadius: '50%'
			border: '1px solid white'
			zIndex: 99
			opacity: '0.75'
			pointerEvents: 'none' # don't be tappable
		Obs.observe !->
			color = '#7b02ff'
			proc = 0
			color = '#7b02ff'
			remaining = maxTime - elapsedO.get()
			proc = 360/maxTime*remaining
			if proc > 180
				nextdeg = 90 - proc
				Dom.style
					backgroundImage: "linear-gradient(90deg, #{color} 50%, transparent 50%, transparent), linear-gradient(#{nextdeg}deg, white 50%, #{color} 50%, #{color})"
			else
				nextdeg = -90 - (proc-180)
				Dom.style
					backgroundImage: "linear-gradient(#{nextdeg}deg, white 50%, transparent 50%, transparent), linear-gradient(270deg, white 50%, #{color} 50%, #{color})"
		Dom.div !->
			Dom.style
				position: 'absolute'
				width: '30px'
				height: '30px'
				backgroundColor: 'white'
				borderRadius: '50%'
				margin: "10px 0 0 10px"
				textAlign: 'center'
				lineHeight: '30px'
				fontSize: '16px'
			Obs.observe !->
				remaining = maxTime - elapsedO.get()
				Dom.text (remaining * .001).toFixed(0)

	Dom.div !->
		if pauseO and pauseO.get()
			renderPauseMode()
		else
			renderNormalMode()