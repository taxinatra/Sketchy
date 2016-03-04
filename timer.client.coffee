Dom = require 'dom'
Obs = require 'obs'

exports.render = (maxTime, elapsedO, top=4) !->
	Dom.div !-> # timer
		Dom.style
			position: 'absolute'
			width: '50px'
			height: '50px'
			top: top+'px'
			right: '4px'
			margin: '0 auto'
			borderRadius: '50%'
			border: '1px solid white'
			zIndex: 99
			opacity: '0.75'
			pointerEvents: 'none' # don't be tappable
		Obs.observe !->
			remaining = maxTime - elapsedO.get()
			proc = 360/maxTime*remaining
			if proc > 180
				nextdeg = 90 - proc
				Dom.style
					backgroundImage: "linear-gradient(90deg, #0077CF 50%, transparent 50%, transparent), linear-gradient(#{nextdeg}deg, white 50%, #0077CF 50%, #0077CF)"
			else
				nextdeg = -90 - (proc-180)
				Dom.style
					backgroundImage: "linear-gradient(#{nextdeg}deg, white 50%, transparent 50%, transparent), linear-gradient(270deg, white 50%, #0077CF 50%, #0077CF)"
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