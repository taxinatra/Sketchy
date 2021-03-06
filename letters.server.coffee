
letters =
	EN:
		a: 0.08167
		b: 0.01492
		c: 0.02782
		d: 0.04253
		e: 0.12702
		f: 0.02228
		g: 0.02015
		h: 0.06094
		i: 0.06966
		j: 0.00153
		k: 0.00772
		l: 0.04025
		m: 0.02406
		n: 0.06749
		o: 0.07507
		p: 0.01929
		q: 0.00095
		r: 0.05987
		s: 0.06327
		t: 0.09056
		u: 0.02758
		v: 0.00978
		w: 0.02361
		x: 0.00150
		y: 0.01974
		z: 0.00074
	NL:
		a: 0.0769
		b: 0.0136
		c: 0.0130
		d: 0.0541
		e: 0.1909
		f: 0.0073
		g: 0.0312
		h: 0.0312
		i: 0.0630
		j: 0.0182
		k: 0.0279
		l: 0.0380
		m: 0.0256
		n: 0.0991
		o: 0.0581
		p: 0.0149
		q: 0.0001
		r: 0.0562
		s: 0.0384
		t: 0.0642
		u: 0.0212
		v: 0.0224
		w: 0.0172
		x: 0.0005
		y: 0.0006
		z: 0.0160
	ES:
		a: 0.12127
		b: 0.02215
		c: 0.04019
		d: 0.05010
		e: 0.16829
		f: 0.00692
		g: 0.01768
		h: 0.00703
		i: 0.06972
		j: 0.00493
		k: 0.00011
		l: 0.04967
		m: 0.03157
		n: 0.06712
		o: 0.09510
		p: 0.02510
		q: 0.00877
		r: 0.06871
		s: 0.07977
		t: 0.04632
		u: 0.03107
		v: 0.01138
		w: 0.00017
		x: 0.00215
		y: 0.01008
		z: 0.00467
		ñ: 0.00311
	FR:
		a: 0.08173
		b: 0.00901
		c: 0.03345
		d: 0.03669
		e: 0.16716
		f: 0.01066
		g: 0.00866
		h: 0.00737
		i: 0.07579
		j: 0.00613
		k: 0.00049
		l: 0.05456
		m: 0.02968
		n: 0.07095
		o: 0.05819
		p: 0.02521
		q: 0.01362
		r: 0.06693
		s: 0.07948
		t: 0.07244
		u: 0.06369
		v: 0.01838
		w: 0.00074
		x: 0.00427
		y: 0.00128
		z: 0.00326
	IT:
		a: 0.11745
		b: 0.00927
		c: 0.05031
		d: 0.03736
		e: 0.12577
		f: 0.01153
		g: 0.01644
		h: 0.00636
		i: 0.10173
		j: 0.00011
		k: 0.00009
		l: 0.06510
		m: 0.02512
		n: 0.06883
		o: 0.09834
		p: 0.03056
		q: 0.00505
		r: 0.06367
		s: 0.04981
		t: 0.05623
		u: 0.03177
		v: 0.02097
		w: 0.00033
		x: 0.00003
		y: 0.00020
		z: 0.01181
	DE:
		a: 0.07094
		b: 0.01886
		c: 0.02732
		d: 0.05076
		e: 0.16396
		f: 0.01656
		g: 0.03009
		h: 0.04577
		i: 0.16550
		j: 0.00268
		k: 0.01417
		l: 0.03437
		m: 0.02534
		n: 0.09776
		o: 0.03037
		p: 0.00670
		q: 0.00018
		r: 0.07003
		s: 0.07577
		t: 0.06154
		u: 0.05161
		v: 0.00846
		w: 0.01921
		x: 0.00034
		y: 0.00039
		z: 0.01134

exports.getRandom = (count) !->
	result = []
	lan = Db.shared.get 'language'
	total = (v for k,v of letters[lan]).reduce (t, s) -> t + s # should be 100??
	for i in [0...count]
		rnd = Math.random() * total
		for k,v of letters[lan]
			if rnd < v
				result.push k
				break
			rnd -= v
	return result
