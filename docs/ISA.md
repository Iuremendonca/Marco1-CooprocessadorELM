# Especificação da ISA — ELM Acelerador

## Formato da instrução (32 bits)

```
 31      28  27     16  15       0
 ┌─────────┬──────────┬──────────┐
 │ OPCODE  │  ADDR    │   DATA   │
 │ (4 bits)│ (12 bits)│ (16 bits)│
 └─────────┴──────────┴──────────┘
```

## Tabela de opcodes

| Mnemônico | Opcode (hex) | ADDR | DATA | Efeito |
|-----------|-------------|------|------|--------|
| `STORE_IMG` | `0x1` | pixel index [0..783] | pixel [7:0] | `ram_img[ADDR] ← DATA[7:0]` |
| `STORE_WEIGHTS` | `0x2` | weight index [0..100351] | peso Q4.12 | `ram_pesos[ADDR] ← DATA` |
| `STORE_BIAS` | `0x3` | bias index [0..127] | bias Q4.12 | `ram_bias[ADDR] ← DATA` |
| `STORE_BETA` | `0x4` | beta index [0..1279] | peso Q4.12 | `ram_beta[ADDR] ← DATA` |
| `START` | `0x5` | — | — | Dispara pulso `start` na FSM |
| `STATUS` | `0x6` | — | — | Lê `hps_readdata` (ver abaixo) |

## Registro STATUS (hps_readdata)

```
 31       8   7    4   3    2    1    0
 ┌─────────┬──────┬───┬────┬────┬────┐
 │ reserva │ pred │ ? │ERR │DONE│BUSY│
 └─────────┴──────┴───┴────┴────┴────┘
```

| Bits | Nome | Descrição |
|------|------|-----------|
| [31:8] | — | Reservado, sempre 0 |
| [7:4] | `pred` | Dígito predito BCD (0–9) |
| [3] | — | Reservado |
| [2] | `ERROR` | 1 = erro no processamento |
| [1] | `DONE` | 1 = inferência concluída (`pronto`) |
| [0] | `BUSY` | 1 = FSM em processamento (estado ≠ REPOUSO) |

## Sequência de uso (pseudo-código)

```c
// 1. Armazenar imagem (784 bytes)
for (i = 0; i < 784; i++)
    write32( (0x1 << 28) | (i << 16) | image[i] );

// 2. Disparar inferência
write32( 0x5 << 28 );

// 3. Polling até DONE
do {
    write32( 0x6 << 28 );
    status = read32();
} while ( !(status & 0x2) );

// 4. Ler predição
pred = (status >> 4) & 0xF;
```

## Notas de temporização

- Cada `write32` (hps_write=1) ocupa 1 ciclo de clock.
- O sinal `start` é um pulso de 1 ciclo gerado pelo módulo `isa`.
- A latência de inferência é de aproximadamente 101.770 ciclos a 50 MHz (~2 ms).
- O polling de STATUS pode ser feito a cada ciclo sem overhead.
