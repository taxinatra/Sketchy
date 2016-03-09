Db = require 'db'

exports.getRndWordObjects = (amount, process = true) ->
	word = rndWord()[0]
	return false if not word
	if process
		word[1] = word.replace(/\s/g,'') # remove spaces
		word[1] = word.toLowerCase() # force lower case
	return {
		wordId: word[0]
		word: word[1]
		prefix: word[2]
	}

exports.getWord = (id, process = true) ->
	if id is null
		word = rndWord()[0][1]
	else
		word = wordList[id][1] # get word
	if process
		word = word.replace(/\s/g,'') # remove spaces
		word = word.toLowerCase() # force lower case
	return word

exports.getPrefix = (id) ->
	return wordList[id][2]

exports.getFields = (id) ->
	word = wordList[id][1] # get word
	return (i.length for i in word.split(" "))

rndWord = (amount = 1) ->
	# form an sorted array with id's we already used
	used = []
	Db.shared.forEach 'drawings', (item) !->
		used.push 0|item.get('wordId')
	used.sort (a,b) -> a - b # sort on value

	# form an sorted array with possible words
	words = []
	for w in wordList
		words.push(w) if w[4] # if not disabled

	# pick x numbers that will be available
	usedLen = used.length
	limit = words.length - usedLen

	if limit <= 0
		log "Out of words"
		return false
	if limit is 1
		log "Wordlist: this is the last word"
		Db.shared.set "outOfWords", true

	pick = []
	for i in [0...amount]
		a = Math.floor(Math.random()*limit)
		pick.push a
	pick = pick.sort (a,b) -> a - b # sort on value

	# walk though the available list, splicing the used and picking along the way
	# the idea is that only have to walk each array once. because of sorting
	r = []
	usedWalker = 0
	rWalker = 0
	i = 0
	while i < words.length
		word = words[i]
		word[0] = 0|word[0] #parse to int

		# check if the word is already used
		while usedWalker < usedLen and used[usedWalker] <= word[0]
			if (used[usedWalker]) is (word[0]) # if so, splice
				words.splice i, 1
				i--
				break
			usedWalker++
		# if index is what we picked, write to return
		if i is (pick[rWalker])
			r[rWalker] = word
			rWalker++
			break if rWalker >= pick.length # we're done here
		i++
	return r

# id, word, prefix, difficulty, active
# difficulty not yet implemented
wordList = [
	[0, "rabbit", "a", 1, true]
	[1, "strawberry", "a", 1, false]
	[2, "crazy", "", 1, false]
	[3, "painting", "a", 1, true]
	[4, "fence", "a", 1, true]
	[5, "horse", "a", 1, true]
	[6, "door", "a", 1, false]
	[7, "song", "a", 1, false]
	[8, "trip", "", 1, false]
	[9, "backbone", "a", 1, false]
	[10, "bomb", "a", 1, false]
	[11, "treasure", "a", 1, true]
	[12, "garbage", "", 1, true]
	[13, "park", "a", 1, false]
	[14, "pirate", "a", 1, true]
	[15, "ski", "a", 1, false]
	[16, "state", "a", 1, true]
	[17, "whistle", "a", 1, true]
	[18, "palace", "a", 1, true]
	[19, "baseball", "a", 1, true]
	[20, "coal", "", 1, false]
	[21, "queen", "a", 1, true]
	[22, "dominoes", "", 1, true]
	[23, "photo", "a", 1, true]
	[24, "computer", "a", 1, true]
	[25, "hockey", "a", 1, true]
	[26, "aircraft", "an", 1, true]
	[27, "hot", "", 1, false]
	[28, "dog", "a", 1, false]
	[29, "salt", "", 1, false]
	[30, "pepper", "", 1, true]
	[31, "key", "a", 1, false]
	[32, "iPad", "an", 1, true]
	[33, "frog", "a", 1, false]
	[34, "lawn mower", "a", 1, false]
	[35, "mattress", "a", 1, true]
	[36, "cake", "a", 1, false]
	[37, "circus", "a", 1, true]
	[38, "battery", "a", 1, true]
	[39, "mailman", "a", 1, true]
	[40, "cowboy", "a", 1, true]
	[41, "password", "a", 1, true]
	[42, "bicycle", "a", 1, true]
	[43, "skate", "a", 1, false]
	[44, "electricity", "", 1, false]
	[45, "lightsaber", "a", 1, false]
	[46, "thief", "a", 1, true]
	[47, "teapot", "a", 1, true]
	[48, "spring", "", 1, true]
	[49, "nature", "", 1, true]
	[50, "shallow", "", 1, false]
	[51, "toast", "a", 1, true]
	[52, "outside", "", 1, true]
	[53, "America", "", 1, true]
	[54, "man", "a", 1, false]
	[55, "bowtie", "a", 1, true]
	[56, "half", "", 1, false]
	[57, "spare", "", 1, false]
	[58, "wax", "", 1, false]
	[59, "lightbulb", "a", 1, false]
	[60, "chicken", "a", 1, true]
	[61, "music", "", 1, true]
	[62, "sailboat", "a", 1, true]
	[63, "popsicle", "a", 1, true]
	[64, "brain", "a", 1, true]
	[65, "birthday", "a", 1, true]
	[66, "skirt", "a", 1, false]
	[67, "knee", "a", 1, false]
	[68, "pineapple", "a", 1, false]
	[69, "sprinkler", "a", 1, false]
	[70, "money", "a", 1, true]
	[71, "lighthouse", "a", 1, false]
	[72, "doormat", "a", 1, true]
	[73, "face", "a", 1, false]
	[74, "flute", "a", 1, true]
	[75, "rug", "a", 1, false]
	[76, "snowball", "a", 1, true]
	[77, "purse", "a", 1, true]
	[78, "owl", "an", 1, false]
	[79, "gate", "a", 1, false]
	[80, "suitcase", "a", 1, true]
	[81, "stomach", "a", 1, true]
	[82, "doghouse", "a", 1, true]
	[83, "bathroom", "a", 1, true]
	[84, "peach", "a", 1, true]
	[85, "newspaper", "a", 1, false]
	[86, "hook", "a", 1, false]
	[87, "school", "a", 1, true]
	[88, "beaver", "a", 1, true]
	[89, "fries", "", 1, true]
	[90, "beehive", "a", 1, true]
	[91, "beach", "a", 1, true]
	[92, "artist", "an", 1, true]
	[93, "flagpole", "a", 1, true]
	[94, "camera", "a", 1, true]
	[95, "hairdryer", "a", 1, false]
	[96, "mushroom", "a", 1, true]
	[97, "toe", "a", 1, false]
	[98, "pretzel", "a", 1, true]
	[99, "tv", "a", 1, false]
	[100, "jeans", "", 1, true]
	[101, "chalk", "a", 1, true]
	[102, "dollar", "a", 1, true]
	[103, "soda", "a", 1, false]
	[104, "chin", "a", 1, false]
	[105, "swing", "a", 1, true]
	[106, "garden", "a", 1, true]
	[107, "ticket", "a", 1, true]
	[108, "boot", "a", 1, false]
	[109, "cello", "a", 1, true]
	[110, "rain", "", 1, false]
	[111, "clam", "a", 1, false]
	[112, "treehouse", "a", 1, false]
	[113, "rocket", "a", 1, true]
	[114, "fur", "a", 1, false]
	[115, "fish", "a", 1, false]
	[116, "rainbow", "a", 1, true]
	[117, "happy", "", 1, true]
	[118, "fist", "a", 1, false]
	[119, "base", "a", 1, false]
	[120, "storm", "a", 1, true]
	[121, "mitten", "a", 1, true]
	[122, "nail", "a", 1, false]
	[123, "sheep", "a", 1, true]
	[124, "traffic light", "a", 1, false]
	[125, "coconut", "a", 1, true]
	[126, "helmet", "a", 1, true]
	[127, "ring", "a", 1, false]
	[128, "seesaw", "a", 1, true]
	[129, "plate", "a", 1, true]
	[130, "hammer", "a", 1, true]
	[131, "bell", "a", 1, false]
	[132, "street", "", 1, true]
	[133, "roof", "a", 1, false]
	[134, "cheek", "a", 1, true]
	[135, "phone", "a", 1, true]
	[136, "barn", "a", 1, false]
	[137, "snowflake", "a", 1, false]
	[138, "flashlight", "a", 1, false]
	[139, "muffin", "a", 1, true]
	[140, "sunflower", "a", 1, false]
	[141, "tophat", "a", 1, true]
	[142, "pool", "a", 1, false]
	[143, "tusk", "a", 1, false]
	[144, "radish", "a", 1, true]
	[145, "peanut", "a", 1, true]
	[146, "chair", "a", 1, true]
	[147, "poodle", "a", 1, true]
	[148, "potato", "a", 1, true]
	[149, "shark", "a", 1, true]
	[150, "jaws", "a", 1, false]
	[151, "waist", "a", 1, true]
	[152, "spoon", "a", 1, true]
	[153, "bottle", "a", 1, true]
	[154, "mail", "", 1, false]
	[155, "crab", "a", 1, false]
	[156, "ice", "", 1, false]
	[157, "lawn", "a", 1, false]
	[158, "bubble", "a", 1, true]
	[159, "pencil", "a", 1, true]
	[160, "hamburger", "a", 1, false]
	[161, "corner", "a", 1, true]
	[162, "popcorn", "", 1, true]
	[163, "seastar", "a", 1, true]
	[164, "octopus", "a", 1, true]
	[165, "desk", "an", 1, false]
	[166, "pie", "a", 1, false]
	[167, "kitten", "a", 1, true]
	[168, "sun", "the", 1, false]
	[169, "mars", "the", 1, true]
	[170, "cup", "a", 1, false]
	[171, "ghost", "a", 1, true]
	[172, "flower", "a", 1, true]
	[173, "cow", "a", 1, false]
	[174, "banana", "a", 1, true]
	[175, "bug", "a", 1, false]
	[176, "book", "a", 1, false]
	[177, "jar", "a", 1, false]
	[178, "snake", "a", 1, true]
	[179, "tree", "a", 1, false]
	[180, "lips", "a", 1, false]
	[181, "apple", "an", 1, true]
	[182, "socks", "", 1, true]
	[183, "swing", "a", 1, true]
	[184, "coat", "a", 1, false]
	[185, "shoe", "a", 1, false]
	[186, "water", "a", 1, true]
	[187, "heart", "a", 1, true]
	[188, "ocean", "an", 1, true]
	[189, "kite", "a", 1, false]
	[190, "mouth", "a", 1, true]
	[191, "milk", "a", 1, false]
	[192, "duck", "a", 1, false]
	[193, "eyes", "", 1, false]
	[194, "bird", "a", 1, false]
	[195, "boy", "a", 1, false]
	[196, "person", "a", 1, true]
	[197, "man", "a", 1, false]
	[198, "woman", "a", 1, true]
	[199, "girl", "a", 1, false]
	[200, "mouse", "a", 1, true]
	[201, "ball", "a", 1, false]
	[202, "house", "a", 1, true]
	[203, "star", "a", 1, false]
	[204, "nose", "a", 1, false]
	[205, "bed", "a", 1, false]
	[206, "whale", "a", 1, true]
	[207, "jacket", "a", 1, true]
	[208, "shirt", "a", 1, true]
	[209, "hippo", "a", 1, true]
	[210, "beach", "a", 1, true]
	[211, "egg", "an", 1, false]
	[212, "face", "a", 1, false]
	[213, "cookie", "a", 1, true]
	[214, "cheese", "a", 1, true]
	[215, "ice", "", 1, false]
	[216, "cream", "a", 1, true]
	[217, "cone", "a", 1, false]
	[218, "drum", "a", 1, false]
	[219, "circle", "a", 1, true]
	[220, "spoon", "a", 1, true]
	[221, "worm", "a", 1, false]
	[222, "spider", "a", 1, true]
	[223, "web", "a", 1, false]
	[224, "bridge", "a", 1, true]
	[225, "bone", "a", 1, false]
	[226, "grapes", "", 1, true]
	[227, "bell", "a", 1, false]
	[228, "truck", "a", 1, true]
	[229, "grass", "", 1, true]
	[230, "monkey", "a", 1, true]
	[231, "bread", "a", 1, true]
	[232, "ears", "", 1, false]
	[233, "bowl", "a", 1, false]
	[234, "bat", "a", 1, false]
	[235, "clock", "a", 1, true]
	[236, "doll", "a", 1, false]
	[237, "orange", "an", 1, true]
	[238, "bike", "a", 1, false]
	[239, "pen", "a", 1, false]
	[240, "seashell", "a", 1, true]
	[241, "cloud", "a", 1, true]
	[242, "bear", "a", 1, false]
	[243, "corn", "", 1, false]
	[244, "glasses", "", 1, true]
	[245, "blocks", "", 1, true]
	[246, "carrot", "a", 1, true]
	[247, "turtle", "a", 1, true]
	[248, "pencil", "a", 1, true]
	[249, "dinosaur", "a", 1, true]
	[250, "head", "a", 1, false]
	[251, "lamp", "a", 1, false]
	[252, "snowman", "a", 1, true]
	[253, "ant", "an", 1, false]
	[254, "giraffe", "a", 1, true]
	[255, "cupcake", "a", 1, true]
	[256, "leaf", "a", 1, false]
	[257, "bunk", "a", 1, false]
	[258, "snail", "a", 1, true]
	[259, "baby", "a", 1, false]
	[260, "balloon", "a", 1, true]
	[261, "bus", "a", 1, false]
	[262, "cherry", "a", 1, true]
	[263, "football", "a", 1, true]
	[264, "branch", "a", 1, true]
	[265, "robot", "a", 1, true]
	[266, "laptop", "a", 1, true]
	[267, "pillow", "a", 1, true]
	[268, "monitor", "a", 1, true]
	[269, "dinner", "a", 1, true]
	[270, "bottle", "a", 1, true]
]