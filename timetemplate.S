# timetemplate.S
# Written 2015 by F Lundevall
# Ported 2024/06 by W Szczerek (from MIPS to RISC-V)
# Copyright abandonded - this file is in the public domain.

#############################################################
# Choose the macro syntax for RARS or DTEK-V board.         #
# The syntax for RARS is probably due to its MIPS heritage. #
#############################################################
###################
# Macros for RARS #
###################
#.macro	PUSH (%reg)
#	addi	sp,sp,-4
#	sw	%reg,0(sp) 
#.end_macro

#.macro	POP (%reg)
#	lw	%reg,0(sp)
#	addi	sp,sp,4
#.end_macro
###################
# Macros for DTEK #
###################
#.macro	PUSH reg
#	addi sp,sp,-4
#	sw \reg,0(sp) 
#.endm

#.macro	POP reg
#	lw	\reg,0(sp)
#	addi	sp,sp,4
#.endm
#############################################################

	.data
	.align 2
mytime:	.word 	0x5957
timstr:	.asciz 	"text more text lots of text\0"
	.text
	.globl timetemplate, tick, time2string, delay, display_string, main
	.eqv TICKS_PER_MS, 14550		#kalibreringskonstant 14550 är 1 ms (innerloop)


timetemplate:
    j main        # hoppa direkt till din C-main()

# Function for displaying a string with a newline at the end	
display_string:	
	li a7,4
	ecall
	li a0, 10
	li a7,11
	ecall
	jr ra
	
# tick: update time pointed to by $a0
tick:	lw	t0, 0(a0)	# get time
	addi	t0, t0, 1	# increase
	andi	t1, t0, 0xf	# check lowest digit
	sltiu	t2, t1, 0xa	# if digit < a, okay
	bnez	t2, tiend
	
	addi	t0, t0, 0x6	# adjust lowest digit
	andi	t1, t0, 0xf0	# check next digit
	sltiu	t2, t1, 0x60	# if digit < 6, okay
	bnez	t2, tiend
	
	addi	t0, t0, 0xa0	# adjust digit
	li	t3, 0xF
	slli	t3, t3, 0x8
	and	t1, t0, t3	# check minute digit
	addi	t3, x0, 0xA
	slli	t3, t3, 0x8
	slt	t2, t1, t3	# if digit < a, okay
	bnez	t2, tiend
	addi	t0, t0, 0x600	# adjust digit - this one's okay, it's lower than 0x7FF 
	
	li	t3, 0xF
	slli	t3, t3, 0xC
	and	t1, t0, t3	# check last digit
	addi	t3, x0, 0x6
	slli	t3, t3, 0xC
	slt	t2, t1, t3	# if digit < 6, okay
	bnez	t2, tiend
	
	li	t3, 0xA
	slli	t3, t3, 0xC
	add	t0, t0, t3	# adjust last digit
tiend:	sw	t0,0(a0)	# save updated result (a0 pekade på mytime när tick kallades så nya tiden skrivs hit)
	jr	ra		# return

#########################################################
# Place for your functions: time2string, hex2asc, delay.#
#########################################################
time2string:
	addi sp, sp, -12
	sw ra, 8(sp)
	sw s0, 4(sp)
	sw s1, 0(sp)
	
	mv s0, a0 #s0 = destpekare
	mv s1, a1 #s1 = tid 

	     #Surprise assignment
    andi t6, s1, 0xFF       
    bnez t6, .normal    # Om sekunder inte noll hoppa till normal

    
    li   t5, 'D'            # Lägg in ASCII D
    sb   t5, 0(s0)          # Skriv D bufferten vid s0
    addi s0, s0, 1          # Flytta pekaren framåt

    li   t5, 'I'            
    sb   t5, 0(s0)          
    addi s0, s0, 1          

    li   t5, 'N'            
    sb   t5, 0(s0)          
    addi s0, s0, 1          

    li   t5, 'G'            
    sb   t5, 0(s0)          
    addi s0, s0, 1          

    sb   x0, 0(s0)          # Avsluta med NUL 0x00

    # Epilog
    lw    s1, 0(sp)         
    lw    s0, 4(sp)         
    lw    ra, 8(sp)         
    addi sp, sp, 12         
    jr   ra                 

.normal:
	
	# M10: (a1 >> 12) & 0xF
    srli  t0, s1, 12	#flytta 12 steg åt höger
    andi  t0, t0, 0xF #säkerställa att bara en nibble är kvar
    mv    a0, t0	#flytta argument till a0 eftersom hexasc förväntar sig argument i a0
    jal   hexasc	#konverteringen
    sb    a0, 0(s0) #skriver tecknet i a0 på platsen som s0 pekar på. so pekar på början av bufferten timstr. så alltså timst[0] = '5'
    addi  s0, s0, 1	#sedan flyttar vi pekaren framåt så nästa tecken hamanr i timstr[1]

    # M1: (a1 >> 8) & 0xF
    srli  t0, s1, 8
    andi  t0, t0, 0xF
    mv    a0, t0
    jal   hexasc
    sb    a0, 0(s0)
    addi  s0, s0, 1

    # ':'
    li    t5, ':'
    sb    t5, 0(s0)
    addi  s0, s0, 1
    
    # S10: (a1 >> 4) & 0xF
    srli  t0, s1, 4
    andi  t0, t0, 0xF
    mv    a0, t0
    jal   hexasc
    sb    a0, 0(s0)
    addi  s0, s0, 1

    # S1: a1 & 0xF
    andi  t0, s1, 0xF
    mv    a0, t0
    jal   hexasc
    sb    a0, 0(s0)
    addi  s0, s0, 1

    # NUL-terminator
    sb    x0, 0(s0) #sätter s0 att peka på 0 (eftersom den just nu pekar på timstr[4])

    # Epilog
    lw    s1, 0(sp)
    lw    s0, 4(sp)
    lw    ra, 8(sp)
    addi  sp, sp, 12
    jr    ra
	
	#hexasc från uppgift 2
	hexasc:
    andi  a0, a0, 0x0F	#maskar igen kanske lite onödigt att göra igen
    li    t0, 9
    ble   a0, t0, .digit
    addi  a0, a0, 55	#öka värdet så vi får ASCII
    andi  a0, a0, 0x7F #säkerhetsåtgärd maskning igen
    jr    ra
.digit:
    addi  a0, a0, 48
    andi  a0, a0, 0x7F
    jr    ra
	


delay:
    mv    t0, a0                # t0 = ms

.outer:
    bge   x0, t0, .done         # om (0 >= ms) -> klart  (motsvarar while(ms > 0))
    li    t1, TICKS_PER_MS     # innerloop-counter

.inner:
    addi  t1, t1, -1
    bnez  t1, .inner            # for(i=0; i<14550; i++)

    addi  t0, t0, -1            # ms--
    j     .outer

.done:
    jr    ra

	
	
	
	

#delay:
#	mv t0, a0
#.L1: 
#	li t1, 4	#4 loopar
#.L2: 
#	addi t1, t1, -1
#	bnez t1, .L2
#	addi t0, t0, -1
#	bnez t0, .L1	#starta hela innerloopen igen om det finns ms kvar i t0
#	jr ra
