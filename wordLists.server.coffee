Config = require 'config'

diacriticsRemovalMap = [
    {'base':'a', 'letters':/[äâàá]/g}
    {'base':'c', 'letters':/[çĉ]/g}
    {'base':'e', 'letters':/[ëêèé]/g}
    {'base':'i', 'letters':/[ïîìí]/g}
    {'base':'o', 'letters':/[óôòó]/g}
    {'base':'u', 'letters':/[üûùú]/g}
]

getWords = (lan = Db.shared.get('language')) ->
	require('wordlist'+lan).wordList()

exports.process = process = (word) ->
	word = word.replace(/\s/g,'') # remove spaces
	word = word.toLowerCase() # force lower case
	for k, mapping of diacriticsRemovalMap
		word = word.replace(mapping.letters, mapping.base)
	return word

exports.getRndWord = (lang = Db.shared.get('language')) ->
	used = {}
	Db.shared.forEach 'drawings', (item) !->
		return unless item.get('wordId')
		[lang,id] = splitWordId item.get('wordId')
		if lang is lang # current language?
			used[id] = true

	now = 0|App.time()
	Db.backend.forEach 'inUse', (item) !-> # words currently being sketched
		if item.get() > now+(Config.drawTime()*2) # if too old, remove
			Db.backend.remove 'inUse', item.key()
			return
		[lang,id] = splitWordId item.key()
		if lang is lang # current language?
			used[id] = true

	words = []
	for w in getWords(lang) when w[4] and !used[w[0]]
		words.push w # w[4] means enabled

	if !words.length
		log "Out of words"
		return false
	if words.length is 1
		log "Wordlist: this is the last word"
		Db.shared.set "outOfWords", true

	if word = words[0 | (Math.random() * words.length)]
		wordId: lang + '_' + word[0]
		word: word[1]
		prefix: word[2]


splitWordId = (wordId) -> # returns ['lang', intId]
	r = /^([a-z]+)?1?_(.*)$/i.exec wordId
	[r[1].toUpperCase(), 0|r[2]]

exports.getWord = (wordId) ->
	[lang,id] = splitWordId wordId
	getWords(lang)[id][1]

exports.getPrefix = (wordId) ->
	[lang,id] = splitWordId wordId
	getWords(lang)[id][2]

