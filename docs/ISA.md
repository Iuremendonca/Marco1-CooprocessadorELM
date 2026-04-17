# ISA — ELM Acelerador
**Referência atualizada** · **RTL:** módulo `isa`

## Formato da instrução (32 bits)

| [31:28] | [27:16] | [15:0] |
| :--- | :--- | :--- |
| **OPCODE** | **ADDR** | **DATA** |
| 4 bits | 12 bits | 16 bits |

---

## Tabela de opcodes

| Instrução | Opcode | Descrição |
|-----------|--------|-----------|
| `STORE_IMG` | `0x1` | Escreve pixel na `ram_img[ADDR]` = `DATA[7:0]` |
| `STORE_WEIGHTS` | `0x2` | Escreve peso em `ram_pesos[ADDR]` = `DATA` (Q4.12) |
| `STORE_BIAS` | `0x3` | Escreve bias em `ram_bias[ADDR]` = `DATA` (Q4.12) |
| `STORE_BETA` | `0x4` | Escreve peso de saída em `ram_beta[ADDR]` = `DATA` |
| `START` | `0x5` | Dispara pulso `start` para a FSM |
| `STATUS` | `0x6` | Lê estado (`hps_readdata`): `[7:4]` = resultado, `[2:0]` = estado FSM |


---

## Registro STATUS — `hps_readdata`

| Bits | Nome | Fonte RTL | Descrição |
| :--- | :--- | :--- | :--- |
| [31:8] | — | `24'b0` | Reservado, sempre 0 |
| [7:4] | **pred** | `elm_result` | Dígito predito BCD (0–9) |
| [3] | — | `1'b0` | Reservado |
| [2] | **ERROR** | `error_flag` | Erro persistente (opcode inválido). **Não limpa sozinho** — requer reset. |
| [1] | **DONE** | `fsm_done` | Inferência concluída |
| [0] | **BUSY** | `fsm_busy` | FSM em processamento |

---

## Condição de execução

Todos os opcodes são executados apenas quando:
`!hps_write && !fsm_busy`

> [!IMPORTANT]
> Escritas com `hps_write=1` são apenas capturadas no registrador. A execução ocorre no ciclo seguinte quando `hps_write=0`.

---

## Sequência de escrita de pesos (2 ciclos)

| Ciclo | Instrução | Efeito |
| :--- | :--- | :--- |
| 1 | `0x6 << 28 \| addr[16:0]` | `temp_w_addr ← addr` |
| 2 | `0x2 << 28 \| data` | `ram_pesos[temp_w_addr] ← data` |

**Nota:** O campo ADDR da instrução `STORE_WEIGHTS` é ignorado. O endereço real é definido no Ciclo 1 através do opcode `0x6`.
