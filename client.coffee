{tr} = require 'i18n'

Config = require 'config'
Draw = require 'draw'
View = require 'view'

roundArchive = null

exports.render = !->
	pageName = Page.state.get(0)
	wayBackMachine = +Page.state.get('round')
	log "render. wayBackMachine", wayBackMachine, roundArchive

	if wayBackMachine
		return renderScores( wayBackMachine, roundArchive ) if pageName is 'scores'
		archivedModeButton wayBackMachine
		return View.render( roundArchive.drawings[pageName], roundArchive.scores ) if pageName # anything else
		renderOverview(wayBackMachine)
	else
		return Draw.render() if pageName is 'draw'
		return renderScores() if pageName is 'scores'
		return View.render() if pageName # anything else
		renderOverview()

archivedModeButton = (roundNumber) !->
	Dom.div !->
		Dom.style
			padding: '12px'
			textAlign: 'center'
			margin: 0
			fontSize: '90%'
			background: '#444'
			color: '#eee'
		Dom.text tr("Viewing round %1 - tap to view current round", roundNumber)
		Dom.onTap !->
			Page.state.remove 0
			Page.state.remove 'round'

renderOverview = (inArchiveMode=false) !->
	log "renderOverview with inArchiveMode:", inArchiveMode
	Comments.enable
		messages: # no longer generated
			new: (c) -> tr("%1 added a new drawing", c.user)
			roundReminder: (c) -> tr("Round %1 will close in a day!", c.v)
			roundClosed: (c) ->
				Dom.span !->
					Dom.text tr("Round %1 won by %2!", c.v, c.names)
					Dom.onTap !->
						if (inArchiveMode is c.v) or (not inArchiveMode and c.v is Db.shared.peek('roundId'))
							Toast.show tr "Already viewing round %1", c.v
							return
						Server.call 'getArchive', c.v, (data) !->
							if data
								log "got archive:", data, c.v
								roundArchive = data
								Page.state.merge
									'round': c.v
									'?comments': null # collapse comments
				true
			roundNew: (c) -> tr("Round %1 has started!", c.v)
			upgradeNotice: (c) ->
				duration = "in #{c.days} days."
				if c.days is 0 then duration = "today!"
				if c.days is 1 then duration = "tomorrow!"
				tr "Sketchy now consists of multiple *rounds*. The current round will end %1", duration

	# mapping for archive mode
	roundO = Obs.create {}
	if inArchiveMode
		if roundArchive
			log "set roundO to roundArchive", roundArchive
			roundO.set roundArchive
		else
			log "should set roundO to roundArchive, but the archive is empty."
			Server.call 'getArchive', inArchiveMode, (data) !->
				if data
					roundArchive = data
					log "got archive:", data, inArchiveMode, roundArchive
					roundO.set roundArchive
				else
					log "no archive data received"
					Page.state.remove 'round'
	else
		log "set roundO to Db.shared"
		roundO = Db.shared.ref()

	hasOlderRounds = !!Db.shared.count('rounds').get()
	if hasOlderRounds
		Page.setActions
			icon: 'history'
			content: "View a previous round"
			action: !-> Modal.show
				title: tr "Rounds"
				buttons: ['cancel', tr 'Cancel']
				content: !->
					log "Showing rounds:", "inArchiveMode", inArchiveMode, "roundId", Db.shared.peek('roundId')
					unless Db.shared.peek('roundClosed') # current round still open
						Ui.item
							content: !->
								unless inArchiveMode
									Dom.style fontWeight: 'bold'
								Dom.text tr "Current round"
							sub: tr "Round open"
							onTap: !->
								if (not inArchiveMode)
									Toast.show tr "Already viewing the current round"
								Page.state.remove 0
								Page.state.remove 'round'
								Modal.remove()
								return
					loadingRoundO = Obs.create null
					Db.shared.iterate 'rounds', (roundOi) !->
						currentRound = Db.shared.peek('roundId') is +roundOi.key()
						Ui.item
							content: !->
								if (+inArchiveMode is +roundOi.key()) or (not inArchiveMode and currentRound)
									Dom.style fontWeight: 'bold'

								if currentRound
									Dom.text tr("Current hunting season")
									return

								Dom.text tr("Round ending ")
								date = new Date(+roundOi.get('endDate')*1000)
								Dom.text date.toUTCString().match(/\d+ \w+/)[0]
							sub: !->
								if roundOi.get('winners')[0]
									Dom.text tr("Best: %1", App.userName(roundOi.get('winners')[0]))
								else
									Dom.text tr("Round not won by anyone")
							afterIcon: !->
								if loadingRoundO.get() is +roundOi.key()
									Ui.spinner()
									return
								return unless roundOi.get('winners')[0]
								Ui.avatar
									key: App.userAvatar(roundOi.get('winners')[0])
									style: margin: "0 0 0 16px"
							onTap: !->
								if (+inArchiveMode is +roundOi.key()) or (not inArchiveMode and currentRound)
									Toast.show tr "Already viewing round %1", +roundOi.key()
									return
								if currentRound # return to now
									Page.state.remove 0
									Page.state.remove 'round'
									Modal.remove()
									return
								loadingRoundO.set +roundOi.key()
								Server.call 'getArchive', roundOi.key(), (data) !->
									if data
										log "got archive:", data, roundOi.key()
										roundArchive = data
										Page.state.merge
											'round': roundOi.key()
											'?comments': null # collapse comments
										Modal.remove()
					, (roundOi) -> -(+roundOi.get('endDate')) # sort on inverse date

	sketchesDoneO = Obs.create 0
	sketchesTotalO = roundO.count('drawings')

	# render your scoring neighbors
	Ui.top !->
		Dom.style
			padding: 0
			margin: 0
			ChildMargin: 12
			background: "url(#{App.resourceUri(if inArchiveMode then 'bgarchive.jpg' else 'bg.jpg')} ) 50% 50% no-repeat"
			backgroundSize: 'cover'
			textAlign: 'center'
			borderBottom: '1px solid #bbdeca'
			position: 'relative'
		Dom.div !->
			return if inArchiveMode
			Dom.style
				fontWeight: 'bold'
				marginBottom: '6px'
				fontSize: '80%'
				color: 'white'
				textShadow: "rgba(0,0,0,0.4) 0px 2px 2px"
			if (endDate = roundO.get('roundEndDate')) and !roundO.get('roundClosed')
				Dom.style fontWeight: 'none'
				Dom.text tr("Round ends ")
				Time.deltaText(endDate, 'countdown')

		# make a sorted array of players scores and calc drawn and guessed
		scoreArray = []
		for u, v of App.users.get()
			t = 0
			t += s for d, s of roundO.get('scores', u)
			scoreArray.push [u, t]
		scoreArray.sort (a,b) -> b[1] - a[1]

		Dom.div !->
			Dom.overflow()
			Dom.style
				width: '100%'
				margin: 0
				Box: true
				paddingBottom: '48px'

			meElement = null

			[0..scoreArray.length-1].forEach (i) !->
				Dom.div !-> Dom.style Flex: true, height: '10px'
				Dom.div !->
					userId = scoreArray[i][0]
					Dom.style padding: "8px 0", position: 'relative', minWidth: '116px'
					Ui.avatar
						key: App.memberAvatar(userId)
						style:
							border: '3px solid white'
							_borderRadius: '50%' # makes it work magically on 2.3 while it does not support % in border radius
							boxSizing: 'border-box'
						size: 86
					Dom.div !->
						nr = i+1
						Dom.style
							borderRadius: '50%'
							background: if +userId is App.userId() then '#ffd22f' else 'white'
							width: '34px'
							height: '34px'
							lineHeight: '34px'
							position: 'absolute'
							border: '2px solid white'
							left: '8px'
							color: 'black'
							top: '64px'
							fontSize: if nr<10 then '100%' else '85%'
						renderPosition nr
					Dom.div !->
						Dom.style
							position: 'absolute'
							right: '8px'
							top: '64px'
						, style: marginRight: '6px'
						View.renderPoints(scoreArray[i][1], 34, { border: '2px solid white' } )
					Dom.div !->
						Dom.style marginTop: '12px', color: '#1d4a34', fontWeight: 'bold', textShadow: '0 1px 2px white'
						Dom.text App.userName(userId)
					Dom.onTap !->
						App.showMemberInfo(userId)
					if +userId is App.userId()
						meElement = Dom.get()

			if App.members.count().get() is 1
				Dom.div !->
					Dom.style
						margin: "8px 15px",
						width: '86px'
						height: '86px'
						lineHeight: '86px'
						textAlign: 'center'
						position: 'relative',
						backgroundColor: 'rgba(0, 0, 0, 0.3)'
						_borderRadius: '50%' # makes it work magically on 2.3 while it does not support % in border radius
						boxSizing: 'border-box'
						color: '#fff'
						fontWeight: 'bold'
					Dom.text '...?'
					Dom.onTap !->
						Modal.show tr("Just you"), tr("You're the only one in here for now. No wonder you're in first place!")


			Dom.div !-> Dom.style Flex: true, height: '10px'
			# scroll to me
			if meElement
				Obs.observe !-> # prevent big redrawings when page width changes
					offsetLeft = meElement.getOffsetXY().x + (meElement.width()/2) - (Page.width()/2)
					Dom.get().prop 'scrollLeft', offsetLeft

		Dom.div !->
			Dom.style
				position: 'absolute'
				bottom: 0
				left: 0
				right: 0
				padding: '8px'
				marginBottom: '8px'
				borderRadius: '2px'
				textAlign: 'center'
				fontWeight: 'bold'
				textShadow: '0 1px 2px white'
			Dom.addClass 'link'
			Dom.text tr("Show leaderboard")
			Dom.onTap !->
				Page.nav {0:'scores', 'round': inArchiveMode}

	# headers above the list
	Obs.observe !->
		# no buttens when viewing archived
		return if inArchiveMode

		# round closed interface
		if roundO.get 'roundClosed'
			Dom.div !->
				Dom.style
					backgroundColor: '#eee'
					MarginPolicy: 'adopt'
					ChildMargin: 12
					paddingTop: '12px'
					textAlign: 'center'

				_roundId = if inArchiveMode then inArchiveMode else roundO.peek('roundId')
				winners = Db.shared.get('rounds', _roundId, 'winners')
				if not winners or winners.length is 0
					names = "no one"
				else
					names = (App.memberName(id) for id in winners)
					names = names.join(', ')
					names = names.replace /, (?=\w+$)/, ' and '
				Dom.b tr("Round won by %1!", names)

				if startDate = roundO.get('roundStartDate')
					Dom.div !->
						Dom.text "Next round starts "
						Time.deltaText(startDate, 'countdown')
				else
					Ui.bigButton tr("Start new round"), !->
						Server.sync 'scheduleNewRound', !->
							Db.shared.set 'roundStartDate', App.time()+(24*3600)
			return

		# block buttons if you pressed one (and have no connection)
		blockO = Obs.create false

		# buttons
		Dom.div !->
			Dom.style Box: 'middle', margin: '12px', alignItems: 'stretch'
			itemButtonStyle = (isNew=false) ->
				Flex: 1
				border: "1px solid " + (if isNew then '#19b500' else '#dc0074')
				background: if isNew then '#19b500' else '#dc0074'
				borderRadius: '2px'
				color: 'white'
				padding: '6px 8px 6px 0'
				textTransform: 'uppercase'
				fontSize: '90%'

			Dom.div !-> # sketch button
				Dom.style
					color: '#999', Flex: 1, marginRight: '4px'
				t = (Db.personal.get('wait')||1458648797)+Config.cooldown()
				if roundO.get 'outOfWords'
					Ui.item
						icon:'info'
						color: '#999'
						content: tr("No more words left to sketch")
						sub: tr("We know of your hardship and will add new words shortly.")
						style:
							color: '#999'
							border: "1px solid #999"
							borderRadius: '2px'
							padding: '4px'
					return
				if t <= Date.now()*0.001
					Ui.item
						icon:
							data: 'add'
							color: 'white'
							style: padding: '8px'

						content: tr("Start sketching")
						style: itemButtonStyle()
						onTap: !->
							return if blockO.peek()
							blockO.set true
							Page.nav 'draw'
				else
					Dom.div !->
						Dom.style
							border: "1px solid #999"
							borderRadius: '2px'
							padding: '4px'
						Dom.div !->
							Dom.style Box: 'middle'
							Icon.render
								data: 'chronometer'
								style: padding: '8px', minWidth: '24px'
								color: '#999'
							Dom.div !->
								Dom.style Flex: 1
								Dom.text tr("Cannot sketch yet")
						# if your last drawing has been added
						# if not: you have skipped it
						Dom.div !->
							Dom.style fontSize: '80%', padding:'2px 8px 4px'

							Dom.text tr("Wait ")
							Time.deltaText t, 'duration'
							if roundO.get('drawings', Db.personal.get('lastDrawing', 'id'))?
								Dom.text tr(" or for more people to guess ")
								Dom.span !->
									Dom.style color: '#7b02ff'
									Dom.text Db.personal.get('lastDrawing', 'word')
							# Dom.text tr("Or more people guess your previous")

			Dom.div !-> # guess button
				Dom.style color: '#999', Flex: 1, Box: 'middle', alignItems: 'stretch'

				unguessed = sketchesTotalO.get() - sketchesDoneO.get()
				log "sketches total:",sketchesTotalO.get(), "done:", sketchesDoneO.get(), "left:", unguessed
				if unguessed > 0
					isNew = Event.isNew roundO.get('drawings', roundO.get('drawingCount')-1,'time')
					Ui.item # guess button
						icon:
							data: 'play'
							color: 'white'
							style: padding: '8px'
						content: tr("Guess next sketch (%1)", if unguessed>5 then '5+' else unguessed)
						style: itemButtonStyle(isNew)
						onTap: !->
							return if blockO.peek()
							blockO.set true
							# am I currently guessing?
							curDrawingId = Db.personal.peek('lastGuessed')
							if curDrawingId? and not Db.personal.peek('words', curDrawingId)?
								log "I'm currently guessing:", curDrawingId
								if roundO.peek('drawings', curDrawingId, 'wordId')
									return Page.nav {0:+curDrawingId}
								# else: drawing does not exist anymore, request new

							# nope, not currently guesing
							log "requesting drawing to guess"
							Server.call 'requestDrawing', (drawingId) !->
								if drawingId is null
									log "crap. no more drawings"
									Modal.show tr("No more sketches"), tr("It turns out, you seem to have run out of sketches to guess.")
								else
									log "got drawing:", drawingId
									App.trackActivity()
									Page.nav {0:drawingId}
				else
					Dom.div !->
						Dom.style
							border: "1px solid #999"
							borderRadius: '2px'
							padding: '6px 8px 6px 0'
							Flex: 1
							Box: 'middle'
						Dom.div !->
							Dom.style
								Box: 'middle'
							Dom.div !->
								Icon.render
									data: 'chronometer'
									style: padding: '8px', minWidth: '24px', display: 'block'
									color: '#999'
							Dom.div !->
								Dom.style Flex: 1
								Dom.text tr("Nothing left to guess")


	# start new group nudge when waiting to sketch/guess again (only in first round)
	Obs.observe !->
		if !inArchiveMode and roundO.get('roundId') is 1 and roundO.get('drawingCount') > 5 and !Db.personal.get('seen', 'nudge1') and (Db.personal.get('wait')||1458648797)+Config.cooldown() > Date.now()/1000 and (sketchesTotalO.get() - sketchesDoneO.get()) <= 0
			seenNudge = !-> Server.sync 'seenNudge', 1

			Dom.div !->
				Dom.style fontSize: '115%', border: '1px solid #999', borderRadius: '2px', textAlign: 'center', padding: '8px 8px 4px 8px', marginBottom: '8px'
				Dom.userText tr("Also play Sketchy with others?")
				Ui.bigButton !->
					Dom.style margin: '10px 0 0 0'
					Dom.text tr("Start new group")
				, !->
					App.newGroup?()
					seenNudge()

				Ui.lightButton !->
					Dom.style fontSize: '75%', textAlign: 'center'
					Dom.text tr("No thanks")
				, !->
					seenNudge()

	renderSketchItem = (drawing) !->
		memberId = drawing.get('memberId')
		drawingId = drawing.key()
		state = drawing.get 'members', yourId, 'time'
		item =
			avatar: App.memberAvatar(memberId)||'#ccc'
			onTap: !-> Page.nav {0:drawing.key(), 'round': inArchiveMode}
		isNew = Event.isNew(drawing.get('time'))
		if isNew
			item.style = color: '#19b500'

		if memberId is yourId # own sketch
			sketchesDoneO.incr()
			Obs.onClean !-> sketchesDoneO.incr -1

			mem = drawing.get('members')
			if mem
				(delete mem[k] if v.time is -1) for k,v of mem # skip members with a time of -1
			if inArchiveMode
				what = drawing.get('word')
			else
				what = Db.personal.get('words', drawing.key())||false
			if what
				r = /^([a-z]*\s)?(.*)$/i.exec what
				prefix = if r[1] then r[1] else ""
				what = r[2]
				item.content = !->
					Dom.userText tr("**You sketched %1**", prefix)
					Dom.span !->
						color = if isNew then '#19b500' else '#7b02ff'
						Dom.style color: color, fontWeight: 'bold'
						Dom.text what
			else
				item.content = tr("Your sketch")
			if mem and Object.keys(mem).length
				item.sub = !->
					Dom.text tr("Attempted by ")
					Dom.text (a = (App.memberName(+k) for k, v of mem)).join(" · ")
					Dom.br()
					Dom.text tr("%1 point|s", roundO.get('scores', yourId, drawingId)||0)
				item.afterIcon = !-> afterIcon drawing
			else
				item.sub = !->
					Dom.text tr("Attempted by no one yet")
		else
			return unless state? # not guessed? not listed!
			sketchesDoneO.incr()
			Obs.onClean !-> sketchesDoneO.incr -1
			what = Db.personal.get('words', drawing.key())||false
			if what
				r = /^([a-z]*\s)?(.*)$/i.exec what
				prefix = if r[1] then r[1] else ""
				what = r[2]

				item.content = !->
					Dom.userText tr("%1 sketched %2", App.memberName(memberId), prefix)
					Dom.span !->
						color = if isNew then '#19b500' else '#7b02ff'
						Dom.style color: color, fontWeight: 'bold'
						Dom.text what
			else
				item.content = tr("Sketch by %1", App.memberName(memberId))
			if state >= 0
				item.sub = !->
					Dom.text tr("Guessed by you in %1 seconds", (state*.001).toFixed(1))
					Dom.br()
					Dom.text tr("%1 point|s", roundO.get('scores', yourId, drawingId)||0)
			else if state is -1
				item.sub = tr("Currently guessing. Hurry!")
			else
				item.sub = tr("You failed to guess")
			item.afterIcon = !-> afterIcon drawing

		Dom.lazily !->
			Ui.item item
		, !->
			Dom.div !->
				Dom.style minHeight: "60px"
			if Event.getUnread drawingId
				Event.bubblePointerTarget()

	# Done sketches list
	yourId = App.memberId()
	afterIcon = (drawing, showPoints=false) !->
		drawingId = drawing.key()
		if noti = Event.getUnread drawingId, true
			log "noti:", noti
			Event.renderBubble count: noti
		# else
			# Event.renderBubble [drawingId]
		else
			Dom.div !->
				return unless drawing.getKeys? # might not be available yet. core update
				nrOfMsg = drawing.get('comments', 'max')# - drawing.getKeys('members').length
				return unless nrOfMsg > 0
				Dom.style Box: 'middle', marginRight: '5px'
				Icon.render
					data: 'chat3'
					color: '#ddd'
					size: 16
					style: padding: '3px'
				Dom.div !->
					Dom.style
						color: '#ddd'
						fontSize: 14
					Dom.text nrOfMsg
		if showPoints
			points = roundO.get('scores', yourId, drawingId)||0
			View.renderPoints(points, 40)

	nrOfDrawingsInvolved = 0
	roundO.iterate 'drawings', (drawing) !->
		renderSketchItem (drawing)
		nrOfDrawingsInvolved++

	, (drawing) ->
		if drawing.peek('memberId') is yourId # I'm the artist
			return -drawing.peek('time')*1000
		return -Db.personal.peek drawing.key() # time I've guessed this drawing

	if nrOfDrawingsInvolved is 0
		if roundO.get('drawingCount')
			if roundO.get('roundClosed')
				Ui.emptyText tr("This round has no sketches")
			else
				Ui.emptyText tr("Start a new sketch or guess one someone made earlier")
		else
			Ui.emptyText tr("No sketches yet, be the first!")

renderScores = (roundId = false, data = false) !->
	Page.setTitle tr("Leaderboard (rounds won)")
	rounds = Db.shared.get('rounds')

	rankings = []
	App.members.iterate (member) !->
		roundScore = 0
		roundScore += 1 for k, v of rounds when (+member.key() in v.winners)
		sketchScore = 0
		sketchScore += v.scores[+member.key()]||0 for k, v of rounds
		rankings.push {id: member.key(), s: roundScore, t:sketchScore}
	rankings.sort (a, b) -> (+b.s*10000 + b.t) - (+a.s*10000 + b.t)
	# Using same ranking number for multiple teams if scores are the same
	ranking = 0
	same = 0
	lastScore = -1
	for member in rankings
		same++
		if lastScore isnt member.s
			ranking+=same
			same = 0
		member['r'] = ranking
		lastScore = member.s

	rankings.forEach (member) !->
		Ui.item
			prefix: !->
				Dom.div !->
					Dom.style
						height: '40px'
						width: '40px'
						lineHeight: '40px'
						textAlign: 'center'
						borderRadius: '20px'
						border: '1px solid #ddd'
						marginRight: '12px'
					renderPosition member.r

			avatar: App.memberAvatar(member.id)
			content: App.memberName(member.id)
			sub: tr("Total score: %1", member.t)
			afterIcon: !-> View.renderPoints(member.s, 40)
			onTap: !-> App.showMemberInfo member.id

renderPosition = (points) !->
	Dom.text points
	Dom.span !->
		Dom.style fontSize: '80%'
		ext = 'th'
		if not (3 < points%100 < 21)
			ext = ([null, 'st', 'nd', 'rd'][points%10])||'th'
		Dom.text ext

exports.renderSettings = !->
	return if Db.shared? # install only option

	Form.box !->
		opts =
			'EN': tr("English")
			'NL': tr("Dutch")
			'ES': tr("Spanish")
			'FR': tr("French")
			'DE': tr("German")
			'IT': tr("Italian")

		def = if !!App.userLanguage and (uLang = App.userLanguage().substring(0, 2).toUpperCase()) and opts[uLang]
			uLang
		else
			'EN'
		langO = Obs.create def

		[handleChange] = Form.makeInput
			name: 'language'
			value: langO.peek()

		Dom.text tr("Language")
		Dom.div !->
			Dom.style fontSize: '75%'
			Dom.text opts[langO.get()]

		Dom.onTap !->
			Modal.show tr("Language"), !->
				for lanCode, lanName of opts then do (lanCode, lanName) !->
					Ui.item !->
						Dom.text lanName
						if langO.peek() is lanCode
							Dom.style fontWeight: 'bold'

							Dom.div !->
								Dom.style
									Flex: 1
									textAlign: 'right'
									fontSize: '150%'
									color: App.colors().highlight
								Dom.text "✓"
						Dom.onTap !->
							handleChange lanCode
							langO.set lanCode
							Modal.remove()
		Icon.render
			data: 'flag2'
			size: 30

	# iniValue = 'EN'
	# if Db.shared then iniValue = Db.shared.get('language')

	# Form.segmented
	# 	name: 'language'
	# 	value: iniValue
	# 	segments: ['EN', tr("English"), 'NL', tr("Dutch"), 'ES', tr("Spanish"), 'FR', tr("French"), 'DE', tr("German"), 'IT', tr("Italian")]
	# 	onChange: (v) !->
	# 		log "on change", v
