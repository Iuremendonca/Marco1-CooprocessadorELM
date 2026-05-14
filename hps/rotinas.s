.syntax unified
.arm
.text
.align 4
.global processar_hardware_asm
.type processar_hardware_asm, %function

@ --- Constantes de Endereço (Offsets do Lightweight Bridge) ---
.equ PIO_READ_OFFSET, 0x00   @ pio_readdata (BASE 0x0)
.equ PIO_CTRL_OFFSET, 0x10   @ pio_hpswrite (BASE 0x10)
.equ PIO_INST_OFFSET, 0x20   @ pio_instrucao (BASE 0x20)

@ --- Syscalls ---
.equ SYS_OPEN,  5
.equ SYS_MMAP2, 192
.equ SYS_MUNMAP, 91
.equ SYS_CLOSE, 6

processar_hardware_asm:
    push    {r4-r11, lr}
    mov     r10, r0             @ r10 = Buffer de dados vindo do C
    mov     r11, r1             @ r11 = Opcode vindo do C
    mov     r9, r2              @ r9 = Limite do Loop (n elementos)
    mov     r5, #0              @ r5 = Inicializa valor de retorno

    @ 1. Abrir /dev/mem
    ldr     r0, =dev_mem_path
    ldr     r1, =0x101002       @ O_RDWR | O_SYNC
    mov     r7, #SYS_OPEN
    svc     #0
    mov     r6, r0              @ r6 = fd
    cmp     r6, #0
    blt     err_ret

    @ 2. Mapear Memória (mmap2)
    mov     r0, #0
    mov     r1, #0x1000         @ Span
    mov     r2, #3              @ PROT_READ | PROT_WRITE
    mov     r3, #1              @ MAP_SHARED
    mov     r4, r6              @ fd
    ldr     r5, =0xff200    @ Offset (0xff200000 / 4096)
    mov     r7, #SYS_MMAP2
    svc     #0
    mov     r8, r0              @ r8 = Base Virtual

    @ Verifica falha no mmap
    cmn     r8, #4096
    bhi     err_ret

    @ --- Configuração de Ponteiros Físicos ---
    add     r1, r8, #PIO_INST_OFFSET @ r1 = Registrador de Escrita (pio_instrucao)
    add     r2, r8, #PIO_CTRL_OFFSET @ r2 = Registrador de Pulso (pio_hpswrite)
    add     r12, r8, #PIO_READ_OFFSET @ r12 = Registrador de Leitura (pio_readdata)

    @ --- SELEÇÃO DE TAREFA ---
    cmp     r11, #0
    beq     do_status           @ Opcode 0: Ler Status/Dígito

    cmp     r11, #5
    beq     do_start            @ Opcode 5: Disparar FSM

    cmp     r11, #2
    beq     do_weight           @ Opcode 2: Pesos W (Protocolo 2 etapas)

    @ --- LOOPS DE CARGA PADRÃO (IMG, BIAS, BETA) ---
    mov     r4, #0              @ i = 0
load_loop:
    cmp     r11, #1
    beq     read_8
    ldrh    r3, [r10], #2       @ Lê 16-bit (Bias/Beta)
    b       send_val
read_8:
    ldrb    r3, [r10], #1       @ Lê 8-bit (Imagem)
send_val:
    mov     r7, r11             @ Monta instrução
    lsl     r7, r7, #28
    orr     r7, r7, r4, lsl #16
    uxth    r3, r3
    orr     r7, r7, r3
    str     r7, [r1]            @ Escreve no pio_instrucao
    bl      pulse_hw
    add     r4, r4, #1
    cmp     r4, r9
    blt     load_loop
    b       cleanup

@ --- LÓGICA DE STATUS (Leitura do Offset 0x0) ---
do_status:
    @ Envia Opcode 0 para o decodificador
    mov     r7, #0
    str     r7, [r1]   
    bl      pulse_hw  @ Pulso para registrar o opcode 0

    @ Lê o valor vindo da FPGA através do pio_readdata
    ldr     r7, [r12]           @ r12 aponta para o offset 0x0
    
    @ Verifica se a FSM está Busy (Bit 0)
    tst     r7, #1              
    movne   r5, #0xFFFFFFFF     @ Retorna -1 se busy
    bne     cleanup

    @ Extrai o dígito do elm_result (Bits 7:4)
    lsr     r5, r7, #4          
    and     r5, r5, #0xF        @ Isola o dígito 0-9
    b       cleanup

do_start:
    mov     r7, #5
    lsl     r7, r7, #28
    str     r7, [r1]            @ Escreve Start
    bl      pulse_hw
    b       cleanup

@ --- LÓGICA DE PESOS W (Duas Etapas) ---
do_weight:
    mov     r4, #0              @ i = 0
weight_loop:
    ldrh    r3, [r10], #2
    @ Passo 1: Opcode 6 (Endereço 17-bit)
    mov     r7, #6
    lsl     r7, r7, #28
    ldr     r5, =0x1FFFF    @ Usando r5 como temporário (ele será sobrescrito no final)
    and     r5, r4, r5
    orr     r7, r7, r5
    str     r7, [r1]
    bl      pulse_hw
    @ Passo 2: Opcode 2 (Dado)
    mov     r7, #2
    lsl     r7, r7, #28
    uxth    r3, r3
    orr     r7, r7, r3
    str     r7, [r1]
    bl      pulse_hw
    add     r4, r4, #1
    cmp     r4, r9
    blt     weight_loop
    mov     r5, #0              @ Sucesso na carga
    b       cleanup

cleanup:
    @ Syscalls de encerramento
    mov     r0, r8              @ Base virtual
    mov     r1, #0x1000
    mov     r7, #SYS_MUNMAP
    svc     #0
    mov     r0, r6              @ fd
    mov     r7, #SYS_CLOSE
    svc     #0
    mov     r0, r5              @ Valor de retorno para o C (Status ou 0)

err_ret:
    pop     {r4-r11, pc}

pulse_hw:
    push    {r3}
    mov     r3, #2              @ Clock High
    str     r3, [r2]
    mov     r3, #150          @ Delay
1:  subs    r3, r3, #1
    bne     1b
    mov     r3, #0              @ Clock Low
    str     r3, [r2]
    pop     {r3}
    bx      lr

.section .rodata
dev_mem_path: .asciz "/dev/mem"
