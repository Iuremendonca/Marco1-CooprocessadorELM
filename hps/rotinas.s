.syntax unified
.arm
.text
.align 4

@ --- Funções exportadas ---
.global init_hw_asm
.global exit_hw_asm
.global reset_hw_asm
.global carregar_img_asm
.global carregar_w_asm
.global carregar_bias_asm
.global carregar_beta_asm
.global start_asm
.global status_asm

.type init_hw_asm,     %function
.type exit_hw_asm,     %function
.type reset_hw_asm,    %function
.type carregar_img_asm, %function
.type carregar_w_asm,   %function
.type carregar_bias_asm,%function
.type carregar_beta_asm,%function
.type start_asm,       %function
.type status_asm,      %function

@ --- Constantes de Endereço (Offsets do Lightweight Bridge) ---
.equ PIO_READ_OFFSET, 0x00
.equ PIO_CTRL_OFFSET, 0x10
.equ PIO_INST_OFFSET, 0x20

@ --- Bits do pio_hpswrite ---
.equ CTRL_CLK_BIT,   2
.equ CTRL_RESET_BIT, 1

@ --- Syscalls ---
.equ SYS_OPEN,   5
.equ SYS_MMAP2,  192
.equ SYS_MUNMAP, 91
.equ SYS_CLOSE,  6

@ limites for
.equ LIM_IMG,   784
.equ LIM_W,  100352
.equ LIM_BETA, 1280
.equ LIM_BIAS,  128

@ =================================================================
@ Variáveis globais (BSS)
@ =================================================================
.section .bss
.align 4
hw_fd:   .space 4
hw_base: .space 4

@ =================================================================
@ Macro: carrega hw_base e deriva os 3 ponteiros de registrador.
@ Usa r8=base, r1=pio_instrucao, r2=pio_hpswrite, r12=pio_readdata.
@ Salta para err_ret se hw não foi inicializado.
@ =================================================================
.macro setup_hw
    ldr     r8, =hw_base
    ldr     r8, [r8]
    cmp     r8, #0
    beq     err_ret
    add     r1,  r8, #PIO_INST_OFFSET
    add     r2,  r8, #PIO_CTRL_OFFSET
    add     r12, r8, #PIO_READ_OFFSET
.endm

@ =================================================================
@ init_hw_asm — abre /dev/mem e mapeia o LW bridge.
@ Retorno: 0 = sucesso, -1 = falha.
@ =================================================================
.section .text
init_hw_asm:
    push    {r4-r7, lr}

    ldr     r0, =dev_mem_path
    ldr     r1, =0x101002
    mov     r7, #SYS_OPEN
    svc     #0
    cmp     r0, #0
    blt     init_fail

    ldr     r1, =hw_fd
    str     r0, [r1]
    mov     r4, r0

    mov     r0, #0
    mov     r1, #0x1000
    mov     r2, #3
    mov     r3, #1
    ldr     r5, =0xff200
    mov     r7, #SYS_MMAP2
    svc     #0

    cmn     r0, #4096
    bhi     init_fail_close

    ldr     r1, =hw_base
    str     r0, [r1]

    mov     r0, #0
    pop     {r4-r7, pc}

init_fail_close:
    ldr     r0, =hw_fd
    ldr     r0, [r0]
    mov     r7, #SYS_CLOSE
    svc     #0
init_fail:
    mov     r0, #-1
    pop     {r4-r7, pc}

@ =================================================================
@ exit_hw_asm — munmap + close.
@ =================================================================
exit_hw_asm:
    push    {r4-r7, lr}

    ldr     r4, =hw_base
    ldr     r0, [r4]
    cmp     r0, #0
    beq     exit_done

    mov     r1, #0x1000
    mov     r7, #SYS_MUNMAP
    svc     #0
    mov     r0, #0
    str     r0, [r4]

    ldr     r4, =hw_fd
    ldr     r0, [r4]
    mov     r7, #SYS_CLOSE
    svc     #0
    mov     r0, #-1
    str     r0, [r4]

exit_done:
    pop     {r4-r7, pc}

@ =================================================================
@ reset_hw_asm — pulso de reset no pio_hpswrite (bit 0).
@ =================================================================
reset_hw_asm:
    push    {r0-r3, lr}

    ldr     r0, =hw_base
    ldr     r0, [r0]
    add     r0, r0, #PIO_CTRL_OFFSET

    mov     r1, #CTRL_RESET_BIT
    str     r1, [r0]

    mov     r2, #150
1:  subs    r2, r2, #1
    bne     1b

    mov     r1, #0
    str     r1, [r0]

    pop     {r0-r3, pc}

@ =================================================================
@ carregar_img_asm — opcode 1, lê uint8 por elemento.
@ Protótipo C: void carregar_img_asm(void *buffer, uint32_t limite)
@
@ Instrução por elemento i:
@   [31:28] = 1  (IMG)
@   [27:16] = i
@   [15:0]  = pixel (uint8)
@ =================================================================
carregar_img_asm:
    push    {r4-r12, lr}
    mov     r10, r0             @ buffer
    mov     r9,  #LIM_IMG
    mov     r5,  #0
    setup_hw

    mov     r4, #0
img_loop:
    cmp     r4, r9
    bge     proc_done

    ldrb    r3, [r10], #1       @ lê 1 byte

    mov     r7, #1              @ opcode IMG hardcoded
    lsl     r7, r7, #28
    orr     r7, r7, r4, lsl #16
    uxth    r3, r3
    orr     r7, r7, r3
    str     r7, [r1]
    bl      pulse_hw

    add     r4, r4, #1
    b       img_loop

@ =================================================================
@ carregar_bias_asm — opcode 3, lê uint16 por elemento.
@ Protótipo C: void carregar_bias_asm(void *buffer, uint32_t limite)
@
@ Instrução por elemento i:
@   [31:28] = 3  (BIAS)
@   [27:16] = i
@   [15:0]  = valor (uint16)
@ =================================================================
carregar_bias_asm:
    push    {r4-r12, lr}
    mov     r10, r0
    mov     r9,  #LIM_BIAS
    mov     r5,  #0
    setup_hw

    mov     r4, #0
bias_loop:
    cmp     r4, r9
    bge     proc_done

    ldrh    r3, [r10], #2       @ lê 2 bytes

    mov     r7, #3              @ opcode BIAS hardcoded
    lsl     r7, r7, #28
    orr     r7, r7, r4, lsl #16
    uxth    r3, r3
    orr     r7, r7, r3
    str     r7, [r1]
    bl      pulse_hw

    add     r4, r4, #1
    b       bias_loop

@ =================================================================
@ carregar_beta_asm — opcode 4, lê uint16 por elemento.
@ Protótipo C: void carregar_beta_asm(void *buffer, uint32_t limite)
@
@ Instrução por elemento i:
@   [31:28] = 4  (BETA)
@   [27:16] = i
@   [15:0]  = valor (uint16)
@ =================================================================
carregar_beta_asm:
    push    {r4-r12, lr}
    mov     r10, r0
    mov     r9,  #LIM_BETA
    mov     r5,  #0
    setup_hw

    mov     r4, #0
beta_loop:
    cmp     r4, r9
    bge     proc_done

    ldrh    r3, [r10], #2

    mov     r7, #4              @ opcode BETA hardcoded
    lsl     r7, r7, #28
    orr     r7, r7, r4, lsl #16
    uxth    r3, r3
    orr     r7, r7, r3
    str     r7, [r1]
    bl      pulse_hw

    add     r4, r4, #1
    b       beta_loop

@ =================================================================
@ carregar_w_asm — opcodes 6+2, protocolo 2 etapas, uint16.
@ Protótipo C: void carregar_w_asm(void *buffer, uint32_t limite)
@
@ Por elemento i:
@   Etapa 1: [31:28]=6, [16:0]=i & 0x1FFFF  (endereço)
@   Etapa 2: [31:28]=2, [15:0]=valor         (dado)
@ =================================================================
carregar_w_asm:
    push    {r4-r12, lr}
    mov     r10, r0
    mov     r9,  #LIM_W
    mov     r5,  #0
    setup_hw

    mov     r4, #0
w_loop:
    cmp     r4, r9
    bge     proc_done

    ldrh    r3, [r10], #2

    @ Etapa 1: endereço
    mov     r7, #6              @ opcode W_ADDR hardcoded
    lsl     r7, r7, #28
    ldr     r6, =0x1FFFF
    and     r6, r4, r6
    orr     r7, r7, r6
    str     r7, [r1]
    bl      pulse_hw

    @ Etapa 2: dado
    mov     r7, #2              @ opcode W hardcoded
    lsl     r7, r7, #28
    uxth    r3, r3
    orr     r7, r7, r3
    str     r7, [r1]
    bl      pulse_hw

    add     r4, r4, #1
    b       w_loop

@ =================================================================
@ start_asm — opcode 5, dispara a FSM.
@ Protótipo C: void start_asm(void)
@ =================================================================
start_asm:
    push    {r4-r12, lr}
    mov     r5, #0
    setup_hw
 
    @ Dispara a FSM: instrução com opcode 5
    mov     r7, #5
    lsl     r7, r7, #28
    str     r7, [r1]
    bl      pulse_hw
 
    @ Polling: lê status até bit 1 (done) = 1
wait_done:
    mov     r7, #0              @ opcode STATUS
    str     r7, [r1]
    bl      pulse_hw
    ldr     r7, [r12]           @ lê pio_readdata
    ubfx    r3, r7, #0, #1      @ extrai bit 1 (done)
    cmp     r3, #1
    beq     wait_done           @ se done=0, continua polling
 
    @ Guarda o valor bruto final em r5 (retorno da função)
    mov     r5, r7
    b       proc_done
 

@ =================================================================
@ status_asm — opcode 0, lê pio_readdata e preenche array[5].
@ Protótipo C: uint32_t status_asm(uint32_t *dados)
@
@ dados[0] = busy   (bit  0)
@ dados[1] = done   (bit  1)
@ dados[2] = error  (bit  2)
@ dados[3] = digito (bits 7:4)
@ dados[4] = ciclos (bits 31:8)
@ Retorno  = valor bruto de 32 bits
@ =================================================================
status_asm:
    push    {r4-r12, lr}
    mov     r10, r0             @ ponteiro para o array
    mov     r5,  #0
    setup_hw

    mov     r7, #0              @ opcode STATUS hardcoded
    str     r7, [r1]
    bl      pulse_hw

    ldr     r7, [r12]           @ lê pio_readdata
    mov     r5, r7              @ valor bruto = retorno

    ubfx    r3, r7, #0, #1
    str     r3, [r10, #0]

    ubfx    r3, r7, #1, #1
    str     r3, [r10, #4]

    ubfx    r3, r7, #2, #1
    str     r3, [r10, #8]

    ubfx    r3, r7, #4, #4
    str     r3, [r10, #12]

    ubfx    r3, r7, #8, #24
    str     r3, [r10, #16]

    b       proc_done

@ =================================================================
@ Saída comum de todas as funções de carga/controle
@ =================================================================
proc_done:
    mov     r0, r5
err_ret:
    pop     {r4-r12, pc}

@ =================================================================
@ pulse_hw — sub-rotina interna.
@ Convenção: r2 aponta para pio_hpswrite antes do BL.
@ =================================================================
pulse_hw:
    push    {r3}
    mov     r3, #CTRL_CLK_BIT
    str     r3, [r2]
    mov     r3, #150
1:  subs    r3, r3, #1
    bne     1b
    mov     r3, #0
    str     r3, [r2]
    pop     {r3}
    bx      lr

.section .rodata
dev_mem_path: .asciz "/dev/mem"
