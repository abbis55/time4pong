    /* =====================================================================
       boot.S – trap/avbrottshantering och global enable för RISC-V på DTEK-V
       ---------------------------------------------------------------------
       MÅL:
       • Sätta upp trap-vektorn (mtvec) till vår egen trap-hanterare.
       • Spara/återställa alla register i en generisk ISR-prolog/epilog.
       • Skilja på "interrupt" (mcause bit 31 = 1) och "exception".
       • För interrupt: anropa C-funktionen handle_interrupt(cause)
         där 'cause' = mcause utan MSB (d.v.s. själva ID:t).
       • Slå på rätt källor i 'mie' och globalt i 'mstatus'.

       VIKTIG DTEK-V-DETALJ:
       • Intel Interval Timer är kopplad till IRQ #16.
         Därför sätter vi mie[16] = 1 i enable_interrupt().

       NOT: Den här filen innehåller också en minimal boot-sekvens (_start).
       ===================================================================== */

    .data
    .align 2
welcome_msg:
    .asciz "================================================\n===== RISC-V Boot-Up Process Now Complete ======\n================================================\n"

    .section .text
    .align 2
    .globl _start

/* -------------------------------------------------------------------------
   Trap-vektor (mtvec) pekar hit. Vi hoppar direkt till _isr_routine som
   sparar register och avgör mcause. Andra hoppet till _start används vid
   "hard reset" i denna mall (behöver normalt inte röras). */
_isr_handler:
    j _isr_routine
    j _start

/* -------------------------------------------------------------------------
   _isr_routine – generisk trap-rutin:
   1) Allokera stackutrymme.
   2) Spara register (utom x2=sp).
   3) Läs mcause och avgör om det är interrupt (bit31=1) eller exception.
   4) För interrupt: hoppa till external_irq.
   5) För exception: (kursdel) anropa handle_exception (om vi använder den).
   6) Återställ register och returnera med mret. */
_isr_routine:
    /* 1) Allokera plats på stacken (32 register × 4 byte) */
    addi sp, sp, -4*32

    /* 2) Spara alla register utom sp (x2) */
    sw x1,  0(sp)
    sw x3,  8(sp)
    sw x4, 12(sp)
    sw x5, 16(sp)
    sw x6, 20(sp)
    sw x7, 24(sp)
    sw x8, 28(sp)
    sw x9, 32(sp)
    sw x10,36(sp)
    sw x11,40(sp)
    sw x12,44(sp)
    sw x13,48(sp)
    sw x14,52(sp)
    sw x15,56(sp)
    sw x16,60(sp)
    sw x17,64(sp)
    sw x18,68(sp)
    sw x19,72(sp)
    sw x20,76(sp)
    sw x21,80(sp)
    sw x22,84(sp)
    sw x23,88(sp)
    sw x24,92(sp)
    sw x25,96(sp)
    sw x26,100(sp)
    sw x27,104(sp)
    sw x28,108(sp)
    sw x29,112(sp)
    sw x30,116(sp)
    sw x31,120(sp)

    /* 3) mcause: bit31=1 innebär "interrupt", bit30..0 = orsak (ID).
          Vi jämför unsigned: t0 >= 0x80000000  ⇒ interrupt. */

    csrr t0, mcause
    li   t1, 0x80000000
    bgeu t0, t1, external_irq   /* hoppa om interrupt */

    /* ---------------- Exception-väg (om vi använder analysdel) ---------- */
    /* Skicka ev. mepc/mcause till C-hanterare (valfritt i denna labb) */
    add  a6, t0, zero           /* a6 = mcause (exceptionkod) */
    addi t1, zero, 11
    beq  t0, t1, skip_init_args /* specialfall: ecall */
    csrr a0, mepc               /* a0 = mepc (felorsakens PC) */
skip_init_args:
    jal  handle_exception       /* C-funktion (är implementerad?) */

    /* Efter exception: hoppa över felande instruktion (mepc += 4) */
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    j    restore

/* ---------------------- Interrupt-väg -------------------------------------
   För interrupt vill vi anropa C-ISR:n med orsaks-ID:t (utan MSB).
   Exempel: för Intel Timer på DTEK-V blir mcause = 0x80000010 → ID = 16. */

external_irq:
    li   t0, 0x7fffffff         /* mask: alla bitar utom MSB */
    csrr t1, mcause
    and  a0, t0, t1             /* a0 = mcause utan MSB (t.ex. 16) */
    jal  handle_interrupt       /* C-ISR: void handle_interrupt(unsigned int cause) */

restore:
    /* 6) Återställ register i omvänd ordning och frigör stacken */
    lw x1,  0(sp)
    lw x3,  8(sp)
    lw x4, 12(sp)
    lw x5, 16(sp)
    lw x6, 20(sp)
    lw x7, 24(sp)
    lw x8, 28(sp)
    lw x9, 32(sp)
    lw x10,36(sp)
    lw x11,40(sp)
    lw x12,44(sp)
    lw x13,48(sp)
    lw x14,52(sp)
    lw x15,56(sp)
    lw x16,60(sp)
    lw x17,64(sp)
    lw x18,68(sp)
    lw x19,72(sp)
    lw x20,76(sp)
    lw x21,80(sp)
    lw x22,84(sp)
    lw x23,88(sp)
    lw x24,92(sp)
    lw x25,96(sp)
    lw x26,100(sp)
    lw x27,104(sp)
    lw x28,108(sp)
    lw x29,112(sp)
    lw x30,116(sp)
    lw x31,120(sp)
    addi sp, sp, 4*32

    /* mret återställer privilegietillstånd och hoppar tillbaka till mepc */
    mret

/* ---------------------- Minimal boot --------------------------------------
   _start: sätter upp stack, skriver välkomsttext, och hoppar till main. */
_start:
    csrw mie, x0               /* se till att avbrott är av innan init */
    la   sp, _stack_end        /* placera stackpekaren (definieras i länk-script) */
    la   gp, __global_pointer  /* global pointer (kompileraren kan utnyttja) */

    /* valfri uppstartstext till terminalen */
    la   a0, welcome_msg
    li   a7, 4
    ecall

    /* hoppa till C-startpunkten */
    jal  main

loop:
    j loop                     /* aldrig hit om main inte returnerar */

/* ---------------------- Global enable-rutin -------------------------------
   enable_interrupt():
   • Pekar mtvec till vår trap-handler (_isr_handler).
   • Sätter mie-bitar:
       - bit 16: DTEK-V Timer IRQ (viktigast i denna labb!)
       - bit 11: MEIE (machine external interrupt) – "generellt bra"
       - bit 7 : MTIE (machine timer interrupt)   – "generellt bra"
     På DTEK-V räcker det kritiskt med bit 16, men vi sätter tre för robusthet.
   • Sätter globalt MIE i mstatus (bit 3).
   • Viktigt: Anropas *sist* i labinit(), efter all hårdvaruinit. */

    .globl enable_interrupt
enable_interrupt:
    /* 1) Sätt trap-vektorn (mtvec) till vår trap-ingång */
    la   t0, _isr_handler
    csrw mtvec, t0			#mtvec pekar nu på _isr_handler

    /* 2) Enable'a rätt interruptkällor i mie:
          - bit 16: plattforms-specifik IRQ för vår Intel Timer
          - bit 11: MEIE (externa avbrott)
          - bit 7 : MTIE (maskin-timer)
       Obs: på DTEK-V krävs *minst* bit 16 för att timer-IRQ ska nå CPU. */

    li   t0, (1 << 16) | (1 << 11) | (1 << 7) | (1 << 17)
    csrs mie, t0

    /* 3) Globalt enable av maskin-interrupts (mstatus.MIE = bit 3) efter detta är globalt avbrott tillåtet. 
När ett interrupt väl triggar:
CPU stänger själv av MIE (för att förhindra att nya interrupts avbryter mitt i vår ISR).
När vi kör mret → återställs MIE automatiskt till vad det var innan trapen.*/

    li   t0, (1 << 3)
    csrs mstatus, t0

    ret
