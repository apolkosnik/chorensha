
	text

__start:
	pea		string
	move	#9,-(sp)
	trap	#1
	addq	#6,sp

	move	#1,-(sp)
	trap	#1
	addq	#2,sp

	clr		-(sp)
	trap	#1

	data

string:
	dc.b	'hallo!',10,13,0

	even
