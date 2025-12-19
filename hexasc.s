  # hexmain.S
  # Written 2015-09-04 by F Lundevall
  # Copyright abandonded - this file is in the public domain.

	.text
	.globl hex2asc

hex2asc:
	#li	a0, 4		# test number (from 0 to 15)
		
	addi    sp,sp,-4	#gör plats på stacken 4 byte
	sw      ra,0(sp)	#sparar returadressen
	
	li t1, 0		#t1 = start
	li t2 15		#t2 = slut
	
loop:
	mv a0, t1		#lägg loopens värde i a0 (argument till hexasc)
	
	
	jal	hexasc		# call hexasc
	
	li	a7, 11	# write a0 to stdout/systemcall: print character
	ecall		#skriv ut tecknet i a0
	
	addi t1, t1, 1	#t++
	ble t1, t2 loop	#om t1 <= 15 fortsätt loopen
	
	li a0, 10	#skriver ut en radbrytning \n bara
	li a7, 11	#systemcall: print character
	ecall		#skriv ut tecknet i a0

	lw      ra,0(sp)	#hämta tillbaka ra
	addi    sp,sp,4		#fria stackplatsen
	jr      ra		#returnera från hex2asc

  # You can write your own code for hexasc here
  #
  hexasc:
	andi a0, a0, 0x0F	#behåll bara nedre 4 bitar (0...15)
	li t0, 9		
	ble a0, t0, .digit	#om a0 <= t0, hoppa till .digit
	
	#FALL A a0 är 10..15
	addi a0, a0, 55		#10 blir A (65), 11 blir B (66)... 15 blir F (70)
	andi a0, a0, 0x7F	#säkra 7-bit ASCII (onödigt men ofarligt)
	
	jr ra		#retur med tecknet i a0
	
	#FALL B (0-9)
.digit:
	addi a0, a0, 48		#0 blir 0 (48), 1 blir 1 (49)... 9 blir 9 (57)
	andi a0, a0,0x7F	#säkra 7-bit ASCII (onödigt men ofarligt)
	jr ra
