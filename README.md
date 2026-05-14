# 🧠 ELM Acelerador — TEC 499 MI Sistemas Digitais 2026.1

> **Marco 1 — Co-processador ELM em FPGA + Simulação**
> Universidade Estadual de Feira de Santana · Departamento de Tecnologia

<div align="center">

[![Simulation](https://img.shields.io/badge/simulação-Icarus%20Verilog-blue)](#simulação)
[![Target](https://img.shields.io/badge/alvo-DE1--SoC%20(Cyclone%20V)-orange)](#hardware)
[![Format](https://img.shields.io/badge/ponto%20fixo-Q4.12-green)](#formato-numérico)
[![License](https://img.shields.io/badge/disciplina-TEC%20499-purple)](#)
[![UEFS](https://img.shields.io/badge/UEFS-DEXA-red)](#)

</div>

---

## 📋 Sumário

### Marco 1 — Co-processador ELM em FPGA + Simulação
1. [Visão Geral do Projeto](#1-visão-geral-do-projeto)
2. [Levantamento de Requisitos](#2-levantamento-de-requisitos)
3. [Arquitetura do Hardware](#3-arquitetura-do-hardware)
4. [Formato Numérico Q4.12](#4-formato-numérico-q412)
5. [Descrição dos Módulos RTL](#5-descrição-dos-módulos-rtl)
6. [Mapa de Registradores / ISA](#6-mapa-de-registradores--isa)
7. [Uso de Recursos FPGA](#7-uso-de-recursos-fpga)
8. [Ambiente de Desenvolvimento](#8-ambiente-de-desenvolvimento)
9. [Instalação e Configuração](#9-instalação-e-configuração)
10. [Processo de Desenvolvimento](#10-processo-de-desenvolvimento)
11. [Simulação e Testes](#11-simulação-e-testes)
12. [Análise dos Resultados](#12-análise-dos-resultados)
13. [Estrutura do Repositório](#13-estrutura-do-repositório)
14. [Equipe](#14-equipe)
15. [Referências](#15-referências)

### Marco 2 — Comunicação HPS↔FPGA
16. [Visão Geral do Marco 2](#16-visão-geral-do-marco-2)
17. [Configuração do Platform Designer](#17-configuração-do-platform-designer)
18. [Geração do Cabeçalho de Endereços](#18-geração-do-cabeçalho-de-endereços)
19. [Driver em C e Rotinas Assembly](#19-driver-em-c-e-rotinas-assembly)
20. [Estrutura da Pasta `hps/`](#20-estrutura-da-pasta-hps)


---

## 1. Visão Geral do Projeto

Este repositório contém a implementação RTL (Register-Transfer Level) em **Verilog** de um co-processador dedicado à inferência de dígitos manuscritos (0–9) utilizando uma **Extreme Learning Machine (ELM)** [[3]](#15-referências) sobre a plataforma **DE1-SoC** (Intel Cyclone V SoC) [[1]](#15-referências).

O sistema classifica imagens 28×28 pixels (MNIST) em escala de cinza, executando os seguintes estágios sequenciais:

<img width="665" height="294" alt="image" src="https://github.com/user-attachments/assets/206e8c31-1b12-4c8d-b218-a92a96730bfc" />

---

### 1.1 Entrada de Dados

O processo inicia com a leitura do vetor de entrada que representa a imagem.

* **Tamanho:** 784 bytes (ex: matriz $28 \times 28$).
* **Ação:** Os dados são carregados para a memória interna do acelerador.

---

### 1.2 Camada Oculta (Hidden Layer)

Processamento da transformação não-linear dos dados de entrada [[3]](#15-referências)[[4]](#15-referências).

* **Equação:** $$h = \sigma(W_n \cdot x + b)$$
* **Onde:**
  * $W_n$: Matriz de pesos.
  * $x$: Pixel.
  * $b$: Vetor de bias.
  * $\sigma$: Função de ativação.

---

### 1.3 Camada de Saída (Output Layer)

Cálculo da combinação linear dos neurônios ocultos com os pesos de saída [[3]](#15-referências).

* **Equação:** $$y = \beta \cdot h$$
* **Onde:**
  * $\beta$: Matriz de pesos de saída (obtida no pré-treino).

---

### 1.4 Cômputo da Predição

Fase final onde a rede decide qual classe o dado pertence.

* **Lógica:** $$\text{pred} = \text{argmax}(y)$$
* **Resultado:** O sistema retorna um valor no intervalo **0..9**, indicando o dígito identificado.

---

**Parâmetros do modelo:**

| Parâmetro | Dimensão | Memória |
|-----------|----------|---------|
| W (pesos oculta) | 128 × 784 | ~200 KB (Q4.12) |
| b (bias oculta) | 128 × 1 | 256 B |
| β (pesos saída) | 10 × 128 | ~2,5 KB (Q4.12) |

---

## 2. Levantamento de Requisitos

### 2.1 Requisitos Funcionais

| ID | Requisito |
|----|-----------|
| RF-01 | O co-processador deve aceitar uma imagem 28×28 pixels, 8 bits por pixel (0–255) |
| RF-02 | Deve implementar a camada oculta: `h = sigmoid(W · x + b)` com 128 neurônios |
| RF-03 | Deve implementar a camada de saída: `y = β · h` com 10 neurônios (classes) |
| RF-04 | Deve retornar a predição `pred = argmax(y)` no intervalo [0, 9] |
| RF-05 | Todos os valores internos devem ser representados em ponto fixo Q4.12 |
| RF-06 | A arquitetura deve ser sequencial com FSM de controle |
| RF-07 | Deve haver um datapath MAC (Multiply-Accumulate) |
| RF-08 | A ativação da camada oculta deve ser approximada (piecewise linear) |
| RF-09 | Deve possuir memórias para imagem, pesos W, bias b e pesos β |
| RF-10 | A ISA deve incluir: STORE_IMG, STORE_WEIGHTS, STORE_BIAS, START, STATUS |

### 2.2 Requisitos Não-Funcionais

| ID | Requisito |
|----|-----------|
| RNF-01 | Sintetizável para DE1-SoC (Cyclone V — 5CSEMA5F31C6) |
| RNF-02 | Clock alvo: 50 MHz |
| RNF-03 | Testbench com ao menos K vetores de teste comparando com golden model |
| RNF-04 | Código Verilog com comentários e estilo consistente |

### 2.3 Restrições

- Representação exclusiva em ponto fixo Q4.12 (sem ponto flutuante)
- Pesos devem residir em blocos RAM/ROM inicializados (arquivos `.mif`)
- Arquitetura estritamente sequencial (sem paralelismo entre camadas)

---

## 3. Arquitetura do Hardware

### 3.1 Diagrama de Blocos (Datapath + FSM)

A arquitetura segue os princípios de co-processadores para aceleração de redes neurais em FPGA [[2]](#15-referências)[[7]](#15-referências).

<img width="591" height="940" alt="image" src="https://github.com/user-attachments/assets/adea536d-085e-491e-bc11-897d8a7fea6b" />


### 3.2 Estados da FSM

<img width="419" height="512" alt="image" src="https://github.com/user-attachments/assets/63d76b3d-a681-4fe9-89ca-9a10e4b5651c" />

---

## 4. Formato Numérico Q4.12

Todos os valores internos utilizam ponto fixo **Q4.12** (signed, 16 bits):

```
  Bit 15   │  Bits 14–12  │  Bits 11–0
  ─────────┼──────────────┼────────────
  Sinal    │  Parte int.  │  Parte frac.
  (1 bit)  │   (3 bits)   │  (12 bits)
```

- **Resolução:** `1/4096 ≈ 0.000244`
- **Faixa representável:** `[-8.0, +7.999756...]`
- **Conversão:** valor_real = valor_inteiro / 4096

### Saturação no MAC

O acumulador interno usa 40 bits para evitar overflow durante a soma. O resultado final é saturado para a faixa Q4.12:

```verilog
if (resultado > 40'sd32767) saida <= 16'h7FFF;  // +7.999...
else if (resultado < -40'sd32768) saida <= 16'h8000;  // -8.0
else saida <= resultado [15:0];
```

---

## 5. Descrição dos Módulos RTL

| Arquivo | Módulo | Função |
| :--- | :--- | :--- |
| `elm_accel.v` | `elm_accel` | **Top-level;** integra todos os submódulos e gerencia o barramento global. |
| **Controle e Decodificação** | | |
| `fsm_elm.v` | `fsm_elm` | FSM de 4 estados; coordena o fluxo de dados e sinais de controle. |
| `decodificador_isa.v` | `decodificador_isa` | Decodifica instruções de 32 bits, extraindo Opcode, ADDR e DATA. |
| **Datapath (Cálculo)** | | |
| `camada_oculta.v` | `camada_oculta` | Gerencia o processamento da primeira camada ($784 \times 128$). |
| `camada_saida.v` | `camada_saida` | Gerencia o processamento da camada de saída ($128 \times 10$). |
| `mac.v` | `mac` | Unidade Multiply-Accumulate de 40 bits com saturação em **Q4.12**. |
| `ativacao_sigmoid.v` | `ativacao_sigmoid` | Implementa a função Sigmóide via aproximação linear (4 segmentos). |
| `argmax.v` | `argmax` | Compara os 10 resultados finais e identifica o índice da classe vencedora. |
| **Memórias (RAM)** | | |
| `ram_img.v` | `ram_img` | Armazena o vetor da imagem de entrada (784 bytes). |
| `ram_pesos.v` | `ram_pesos` | Armazena a matriz de pesos $W$ (100K x 16 bits). |
| `ram_bias.v` | `ram_bias` | Armazena o vetor de bias $b$ (128 x 16 bits). |
| `ram_neuroniosativos.v` | `ram_neuroniosativos` | RAM para armazenar os resultados ativados ($h$) da camada oculta. |
| `ram_beta.v` | `ram_beta` | Armazena a matriz de pesos de saída $\beta$ (1280 x 16 bits). |
| **Interface e Visualização** | | |
| `decodificador_7seg.v` | `decodificador_7seg` | Converte a predição para os displays de 7 segmentos da DE1-SoC. |
| `instrucoes.v` | `instrucoes` | Interface para mapear chaves e botões físicos em instruções ISA. |

---
### 5.1 `decodificador_isa.v` — decodificador de instruções

Faz a ponte entre o processador ARM (HPS) e o hardware de inferência. O HPS envia um barramento de 32 bits (`instrucao`) junto com um pulso de escrita (`hps_write`), e o módulo ISA decodifica o opcode para determinar a operação:

- **Escrita nas RAMs** — distribui o dado (`data_to_mem`) e o endereço correto (`w_addr`, `img_addr`, `bias_addr`, `beta_addr`) para cada memória, ativando o sinal de escrita correspondente (`wren_w`, `wren_img`, `wren_bias`, `wren_beta`).
- **Início da inferência** — gera o pulso `start_pulse` que coloca a FSM em movimento.
- **Leitura do resultado** — disponibiliza o dígito predito pelo argmax em `hps_readdata`, com informações de status (busy/done) para que o HPS saiba quando o resultado é válido.

O módulo também monitora os sinais `fsm_busy` e `fsm_done` para evitar que o HPS inicie uma nova inferência enquanto a anterior ainda está em execução.

---

### 5.2 `fsm_elm.v` — máquina de estados

Controla o sequenciamento das duas fases de cálculo. Possui quatro estados:

| Estado | Descrição |
|---|---|
| `REPOUSO` | Aguarda o pulso `start`. |
| `CALC_OCULTO` | Habilita `calcular`, ativando a camada oculta. Permanece neste estado até que o sinal `ultimo_neuronio` indique que todos os 128 neurônios foram processados. |
| `CALC_SAIDA` | Habilita `calcula_saida`, ativando a camada de saída. Permanece até `ultimo_neuronio_saida`, que sinaliza o fim das 10 classes. |
| `FIM` | Pulsa `pronto` por um ciclo, notificando o ISA de que o resultado está disponível, e retorna ao `REPOUSO`. |

A FSM utiliza registradores auxiliares (`foi_ultimo_oculto`, `foi_ultimo_saida`) para capturar as bordas dos sinais de fim de camada e evitar transições espúrias.

---

### 5.3 `mac.v` — multiply-accumulate

Núcleo aritmético reutilizado pelas duas camadas. Opera em **ponto fixo Q4.12** (12 bits fracionários) e segue o seguinte protocolo:

1. A cada ciclo em que `dado_valido` está ativo, calcula `mult_atual = valor × peso` (resultado de 32 bits) e acumula em um registrador de **40 bits** com sinal.
2. Quando `fim_neuronio` é assinalado (último pixel do neurônio atual), soma o `bias` alinhado ao ponto fixo (`bias << 12`) e aplica um **shift aritmético de 12 bits à direita** para converter de volta à representação Q4.12.
3. O resultado é **saturado** para o intervalo `[−32768, 32767]` (int16) antes de ser registrado em `saida`.
4. O sinal `ativacao` é pulsado por um ciclo para indicar que `saida` é válido.

O acumulador de 40 bits garante que produtos intermediários não transbordem, mesmo com 784 multiplicações acumuladas.

---

### 5.4 `camada_oculta.v` — camada oculta (128 neurônios)

Gerencia os contadores de endereço e alimenta o MAC com os dados corretos para calcular a saída dos 128 neurônios ocultos.

**Normalização do pixel:** antes de entrar no MAC, cada pixel `uint8` é convertido para Q4.12 com um shift de 4 bits à esquerda (`pixel << 4`), mapeando o intervalo `[0, 255]` para `[0.0, ~1.0]` em ponto fixo.

**Endereçamento:** dois contadores controlam o acesso às RAMs:
- `cnt_pixel` (0–783): percorre os 784 pixels de uma imagem para cada neurônio.
- `cnt_neuronio` (0–127): avança para o próximo neurônio após todos os pixels serem processados.
- `cnt_peso` (0–100351): avança continuamente sem reset parcial, apontando diretamente para o peso `W[neurônio][pixel]` na `ram_pesos`.

Um pipeline de 1 ciclo (`calcular_d`, `fim_pixel_d`) sincroniza os dados lidos da RAM com o MAC, compensando a latência de leitura das memórias síncronas.

---

### 5.5 Otimização da Função de Ativação (Sigmoid Piecewise Linear)

Para garantir a eficiência do acelerador na FPGA e evitar o uso de multiplicadores proprietários (blocos aritméticos integrados diretamente na arquitetura física de uma FPGA), a função de ativação foi implementada via aproximação linear por partes (**PWL**). 

Se a entrada for negativa, aplica a simetria da sigmoid: `resultado = 1.0 − sigmoid(|x|)`. As divisões são implementadas como shifts aritméticos à direita, e todas as constantes estão representadas em Q4.12. O módulo também mantém um contador `addr_out` que incrementa a cada ativação, gerando automaticamente o endereço de escrita na `ram_neuroniosativos`

#### Aproximação da Função Sigmóide Logística

| Intervalo de $\|x\|$ | Equação (Aproximação) | Operação RTL (Q4.12) |
| :--- | :--- | :--- |
| $[0, 1.0)$ | $f(x) = 0.25x + 0.5$ | `(abs >> 2) + 16'h0800` |
| $[1.0, 2.5)$ | $f(x) = 0.125x + 0.625$ | `(abs >> 3) + 16'h0A00` |
| $[2.5, 4.5)$ | $f(x) = 0.03125x + 0.859375$ | `(abs >> 5) + 16'h0DC0` |
| $\ge 4.5$ | $f(x) = 1.0$ (Saturação) | `16'h1000` |

> [!TIP]
> De acordo com **Oliveira (2017)** [[7]](#15-referências), essa abordagem minimiza o uso de elementos lógicos e blocos de DSP, permitindo que o sistema atinja maiores frequências de operação ($F_{max}$) ao reduzir o caminho crítico do datapath. O trabalho completo está disponível em: https://repositorio.unifei.edu.br/xmlui/handle/123456789/861

#### Comparativo entre curva da função original e a aproximação

<img width="972" height="504" alt="image" src="https://github.com/user-attachments/assets/d0fd30d1-a618-4aaf-a1c6-d1342768bbfe" />

---

### 5.6 `camada_saida.v` — camada de saída (10 classes)

Calcula os logits das 10 classes do classificador usando o mesmo módulo MAC, mas com duas diferenças importantes em relação à camada oculta:

- **Sem função de ativação:** os logits `y[c]` são passados diretamente para o argmax, sem passar pela sigmoid.
- **Bias zerado:** o campo de bias é fixado em `16'sd0`, pois os pesos `beta` já incorporam o viés da regressão de saída do ELM.

O endereçamento percorre `cnt_h` (0–127) e `cnt_classe` (0–9), com o endereço do peso calculado como `addr_peso_saida = cnt_h × 10 + cnt_classe`, refletindo o layout linha-maior da `ram_beta`. Ao final de cada classe, o sinal `y_valida` é pulsado para notificar o argmax.

---

### 5.7 `argmax.v` — seleção da classe predita

Percorre as 10 classes `y[0..9]` à medida que chegam (um por pulso de `y_valida`) e mantém o valor máximo e seu índice em registradores internos. O contador `current_idx` é incrementado automaticamente a cada logit recebido, eliminando a necessidade de um endereço externo.

Ao receber o pulso `pronto` da FSM, o índice vencedor é transferido para a saída `saida[3:0]`, que representa o dígito predito (0–9). O sinal `clear` (gerado pelo pulso `start`) reinicia o módulo antes de cada inferência, garantindo que o resultado anterior não contamine a próxima predição.

---
## 6. Mapa de Registradores / ISA

### 6.1 Banco de registradores

| Registrador | Largura | Acesso | Módulo | Reset | Descrição |
|---|---|---|---|---|---|
| `save_instrucao` | 32 bits | R/W | `decodificador_isa` | `32'b0` | Captura a instrução vinda do HPS a cada borda de subida do clock. Os campos `opcode[31:28]`, `addr_in[27:16]` e `data_in[15:0]` são extraídos diretamente deste registrador. |
| `data_to_mem` | 16 bits | W | `decodificador_isa` | `16'b0` | Registra o campo de dado (`data_in[15:0]`) da instrução para escrita nas RAMs internas. Compartilhado por `ram_img`, `ram_pesos`, `ram_bias` e `ram_beta`, dependendo do opcode ativo. |
| `temp_w_addr` | 17 bits | R/W | `decodificador_isa` | `17'b0` | Armazena o endereço de 17 bits para escrita na `ram_pesos`. Configurado pelo opcode `0x6` (STORE W ADDR) e utilizado na operação seguinte de opcode `0x2` (STORE W). Necessário pois o campo `addr_in` tem apenas 12 bits. |
| `ciclo_count` | 32 bits | R | `decodificador_isa` | `32'b0` | Contador de ciclos de clock decorridos durante a inferência. Incrementado enquanto a FSM está em `CALC_OCULTO` ou `CALC_SAIDA`. Permite medir latência de execução via HPS. |
| `hps_readdata` | 32 bits | R | `decodificador_isa` | `32'b0` | Dado de retorno ao HPS. Populado pelo opcode `0x0` (STATUS): `[7:4]` resultado argmax · `[2]` error · `[1]` fsm_done · `[0]` fsm_busy. |


A ISA utiliza palavras de 32 bits com o seguinte formato:

```
 31      28     27     16  15       0
 ┌─────────┬──────────┬──────────┐
 │ OPCODE  │  ADDR    │   DATA   │
 │ (4 bits)│ (12 bits)│ (16 bits)│
 └─────────┴──────────┴──────────┘
```

### 6.2 Tabela de Opcodes

| Instrução | Opcode | Descrição |
|-----------|--------|-----------|
| `STORE_IMG` | `0x1` | Escreve pixel na `ram_img[ADDR]` = `DATA[7:0]` |
| `STORE_WEIGHTS` | `0x2` | Escreve peso em `ram_pesos[ADDR]` = `DATA` (Q4.12) |
| `STORE_BIAS` | `0x3` | Escreve bias em `ram_bias[ADDR]` = `DATA` (Q4.12) |
| `STORE_BETA` | `0x4` | Escreve peso de saída em `ram_beta[ADDR]` = `DATA` |
| `START` | `0x5` | Dispara pulso `start` para a FSM |
| `STATUS` | `0x6` | Lê estado (`hps_readdata`): `[7:4]` = resultado, `[2:0]` = estado FSM |

### 6.3 Saída STATUS (`hps_readdata`)

```
 31       8   7    4   3    2    1    0
 ┌─────────┬──────┬───┬────┬────┬────┐
 │ reserva │ pred │ ? │ERR │DONE│BUSY│
 └─────────┴──────┴───┴────┴────┴────┘
```

| Bits | Significado |
|------|-------------|
| `[7:4]` | Dígito predito (0–9) em BCD |
| `[2]` | ERROR — erro no processamento |
| `[1]` | DONE — inferência concluída (`pronto`) |
| `[0]` | BUSY — FSM em processamento |

---

## 7. Uso de Recursos FPGA

> Dados obtidos após síntese no Quartus Prime Lite [[5]](#15-referências) para **Cyclone V — 5CSEMA5F31C6** [[1]](#15-referências).

| Recurso | Utilizado | Disponível | % |
|---------|-----------|------------|---|
| ALMs (LUTs) | 655 | 32.070 | 2% |
| Registradores | 691 | 128.280 | 0,005% |
| Pins | 27 | 457 | 5,9% |
| DSP Blocks (18×18) | 2 | 87 | 2% |
| M10K (BRAM) | 203 | 397 | 51% |
| PLLs | 0 | 6 | 0% |

**Estimativa de memória (BRAMs M10K):**

| RAM | Profundidade | Largura | Tamanho | M10K est. |
|-----|-------------|---------|---------|-----------|
| `ram_img` | 1024 | 8 | 8 KB | 1 |
| `ram_pesos` | 131.072 | 16 | 2 MB | ~200 |
| `ram_bias` | 128 | 16 | 256 B | 1 |
| `ram_neuroniosativos` | 128 | 16 | 256 B | 1 |
| `ram_beta` | 1280 | 16 | 2,5 KB | 1 |

---

## 8. Ambiente de Desenvolvimento

### 8.1 Hardware

| Item | Especificação |
|------|--------------|
| Placa FPGA | Terasic DE1-SoC [[1]](#15-referências) |
| FPGA | Intel Cyclone V SoC — 5CSEMA5F31C6 |
| HPS | ARM Cortex-A9 Dual-Core, 800 MHz |
| Memória HPS | 1 GB DDR3 |
| Clock FPGA | 50 MHz (onboard) |

### 8.2 Software

| Ferramenta | Versão | Uso |
|------------|--------|-----|
| Quartus Prime Lite [[5]](#15-referências) | 21.1 | Síntese e place & route |
| ModelSim-Intel | 10.5b | Simulação RTL |
| Icarus Verilog [[6]](#15-referências) | 11.0 | Verificação saída esperada |
| GTKWave | 3.3.x | Visualização de formas de onda |
| Python | 3.10+ | Scripts de geração de vetores de teste e MIF |
| NumPy | 1.24+ | Golden model e geração de dados |
| Git | 2.x | Controle de versão |

---

## 9. Instalação e Configuração

### 9.1 Pré-requisitos

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install iverilog gtkwave python3 python3-pip git

pip3 install numpy
```

> Para síntese e programação da placa: **Quartus Prime Lite 21.1** [[5]](#15-referências) (Windows ou Linux), disponível em [intel.com/content/www/us/en/software/programmable/quartus-prime](https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/download.html).

### 9.2 Clonar o repositório

```bash
git clone https://github.com/<org>/MI-SD.git
cd MI-SD
```

Após clonar, a estrutura já estará pronta para uso:

- Os **arquivos MIF** dos pesos (W\_in, bias e β) estão em `quartus/mif/` — não é necessário gerá-los;
- As **imagens de teste** PNG estão em `assets/images_png/` e suas versões MIF em `assets/images_mif/`.

### 9.3 Executar simulação (ModelSim / Icarus Verilog)

**ModelSim (Quartus):**

```
1. Abrir Quartus Prime Lite
2. File → Open Project → quartus/<projeto>.qpf
3. Tools → Run Simulation Tool → RTL Simulation
4. No ModelSim: adicionar os sinais de interesse e rodar
```

**Icarus Verilog [[6]](#15-referências) (linha de comando):**

```bash
# Compilar todos os módulos RTL + testbench desejado
iverilog -g2012 -o simulation/elm_sim \
    rtl/*.v testbenches/<modulo>_tb.v

# Executar
vvp simulation/elm_sim

# Visualizar formas de onda
gtkwave simulation/dump.vcd &
```

### 9.4 Sintetizar e gravar na DE1-SoC

```
1. Abrir Quartus Prime Lite
2. File → Open Project → quartus/<projeto>.qpf
3. Processing → Start Compilation
4. Tools → Programmer → selecionar pbl1.sof → Start
```

> Os arquivos MIF em `quartus/mif/` são carregados automaticamente pelo Quartus [[5]](#15-referências) durante a compilação para inicializar as RAMs com os pesos do modelo.

### 9.5 Teste Python (elm_model)

Para testar a inferência em python utilize o seguinte comando juntamente com os arquivos txt, disponiveis em `scripts/txt`.

As imagens de teste disponíveis em `assets/images_png/` podem ser usadas diretamente com os scripts em `scripts/` para gerar vetores de simulação ou para validação na placa via a ISA do co-processador.

O arquivo `label.txt` deve conter uma linha com o digito a ser inferido.

```bash
# Exemplo: rodar golden model Python contra uma imagem
 python elm_model.py \\
        --weights weights.txt \\
        --beta    beta.txt    \\
        --bias    bias.txt    \\
        --image   image.txt   \\
        --label   label.txt
```

---

## 10. Processo de Desenvolvimento

Esta seção descreve a trajetória real da equipe — as decisões tomadas, os problemas encontrados e como cada um foi resolvido. O objetivo é registrar não apenas *o que* foi construído, mas *como* se chegou até aqui.

### 10.1 Fase 1 — Entendimento do problema e elaboração dos diagramas

O ponto de partida foi o estudo da teoria da ELM [[3]](#15-referências)[[4]](#15-referências) e a compreensão das etapas matemáticas envolvidas na inferência: produto matricial da camada oculta, aplicação da ativação não-linear e produto matricial da camada de saída. Antes de escrever qualquer linha de Verilog, a equipe elaborou diagramas de fluxo detalhando cada etapa de cálculo — o que permitiu mapear com clareza quais operações seriam necessárias, quais dados precisariam ser armazenados e em que ordem cada resultado dependia do anterior.

Em retrospecto, percebeu-se que o foco inicial foi direcionado à **corretude da inferência** (os cálculos matemáticos em hardware) antes de consolidar a **arquitetura completa** (ISA, banco de registradores, interface HPS–FPGA). Embora esse caminho tenha gerado um aprendizado sólido sobre a operação do datapath, a ordem ideal seria definir primeiro a arquitetura e depois implementar a inferência dentro dela — lição incorporada nas iterações seguintes.

### 10.2 Fase 2 — Implementação e validação módulo a módulo

Com os diagramas em mãos, a implementação seguiu uma estratégia **bottom-up**: cada módulo foi escrito e validado individualmente antes de ser integrado ao sistema.

Os módulos foram testados na seguinte ordem:

1. `mac.v` — verificação da aritmética Q4.12, saturação e acumulação de 40 bits;
2. `ativacao_sigmoid.v` — validação dos quatro segmentos lineares contra valores esperados em Python;
3. `argmax.v` — verificação do registro correto do máximo entre 10 entradas sequenciais;
4. `camada_saida.v` — validação dos contadores e da sequência de endereçamento;
5. `fsm_elm.v` — verificação das transições de estado e dos sinais de controle gerados.

Cada módulo foi simulado com **testbenches individuais no Icarus Verilog** [[6]](#15-referências) (via playground online) e também no **ModelSim do Quartus** [[5]](#15-referências), onde a visualização das formas de onda permitiu inspecionar ciclo a ciclo o comportamento dos sinais. As saídas foram sistematicamente comparadas com scripts Python que executavam a mesma operação em ponto flutuante de dupla precisão, servindo como golden reference.

### 10.3 Fase 3 — Integração no top-level e sincronização de sinais

Após a validação individual, os módulos foram integrados no top-level `ondeamagicaacontece.v`. Essa etapa revelou a principal dificuldade técnica do projeto: **a sincronização de sinais em presença de latência de acesso às RAMs**.

As memórias inferidas pelo Quartus [[5]](#15-referências) introduzem um ciclo de latência entre a apresentação do endereço e a disponibilização do dado na saída. Isso exigiu que vários sinais de controle fossem **atrasados por registros de pipeline** para garantir que os dados lidos de cada RAM chegassem ao MAC exatamente no ciclo correto — especialmente o sinal `dado_valido` e os pulsos `fim_neuronio` e `ultimo_neuronio`, cujo alinhamento temporal com os dados é crítico para a operação correta do acumulador.

A depuração foi realizada em camadas: primeiro validando a camada oculta isoladamente (comparando `h_saida` ciclo a ciclo com o Python), depois a camada de saída. Em ambos os casos, os resultados intermediários do hardware coincidiam com os do modelo de referência.

### 10.4 Fase 4 — Diagnóstico do erro de inferência e correção do mapeamento dos pesos β

Após a sincronização estar aparentemente correta, a inferência final continuava produzindo resultados incorretos. Um dado relevante foi que **o hardware e o golden model em Python erravam para a mesma classe** — o que indicou que o erro não era de aritmética ou sincronismo, mas de **lógica no acesso aos dados**.

Iniciou-se então um processo de descarte sistemático de hipóteses. Testes específicos foram realizados para verificar:

- Conservação de sinal no formato Q4.12 (complemento de dois) — **passou**;
- Aritmética do MAC com vetores de entrada controlados — **passou**;
- Sincronismo dos pulsos de controle — **passou**;
- Valores intermediários de `h_saida` e `h_ativado` — **corretos**;
- Valores de `y_saida` para cada classe — **incorretos em relação à referência**.

A causa raiz foi identificada ao comparar a **convenção de linearização** das duas matrizes de pesos:

| Matriz | Convenção | Acesso sequencial |
|--------|-----------|-------------------|
| W\_in (oculta) | Linha = neurônio; coluna = pixel | neurônio 0: pesos 0–783, neurônio 1: pesos 784–1567, ... |
| β (saída) | **Linha = pixel de entrada (h); coluna = classe** | os **primeiros pesos de cada neurônio** estão nas primeiras posições — ou seja, cada coluna é uma classe |

A RAM `ram_beta` havia sido populada seguindo a mesma lógica de W\_in (linha a linha), mas o hardware a endereçava como se cada bloco de 128 posições correspondesse a uma classe. Na prática, o hardware estava lendo os pesos da **coluna** quando deveria ler os da **linha**, e vice-versa — equivalente a usar β transposta no lugar de β.

A correção foi feita no script `gen_mif.py`: a matriz β passou a ser transposta antes de ser linearizada para o arquivo `.mif`, alinhando a convenção de armazenamento ao padrão de acesso do hardware. Após essa correção, a inferência passou a produzir os resultados corretos.

### 10.5 Fase 5 — Integração da ISA e testes na placa

Com a inferência validada por simulação, a ISA e o decodificador de instruções (desenvolvidos em paralelo) foram acoplados ao datapath no módulo `ondeamagicaacontece.v`. Os testes finais foram realizados **diretamente na placa DE1-SoC** [[1]](#15-referências), verificando que:

- A validação individual de cada módulo foi preservada após a integração completa;
- A validação da inferência por simulação se manteve no hardware real;
- A comunicação via instruções (STORE\_IMG, START, STATUS) operou corretamente, com o resultado exibido no display de 7 segmentos da placa.

---

## 11. Simulação e Testes

### 11.1 Estratégia de Verificação

A estratégia de verificação baseou-se na simulação funcional e temporal em múltiplos níveis, com comparação sistemática dos resultados contra um **Golden Model** em Python. As ferramentas utilizadas foram o **ModelSim** [[5]](#15-referências) para análises complexas de integração e o **EDA Playground** para validações rápidas de módulos individuais.

Os arquivos de teste estão localizados na pasta `/testbenchs` e seguem o padrão de nomenclatura `tb_nome_do_modulo.v` para testes de modulos individuais e `tb_camada_nome.v` para testes de integrações.

---

### 11.2 Plataformas de Teste e Passo a Passo

#### A. EDA Playground (Testes Individuais de Módulos)

Utilizado para validação unitária de componentes lógicos (MAC, Sigmoid, Argmax) devido à agilidade de execução via web.

1. Acesse o [EDA Playground](https://www.edaplayground.com/).
2. Faça o upload do arquivo do módulo (ex: `mac.v`) e seu respectivo testbench localizado em `/testbenchs/tb_mac.v`.
3. Selecione o simulador **Icarus Verilog** [[6]](#15-referências) ou **Questa Sim**.
4. Marque a opção "Open EPWave after run" para visualizar os sinais.
5. Clique em **Run** para validar a lógica aritmética e de estados.

#### B. ModelSim (Integração, Acesso à Memória e Barramento)

Plataforma principal para validar a integração entre dois ou mais módulos, fluxos de acesso às memórias RAM e avaliação detalhada de sinais temporais críticos.

1. Abra o **ModelSim** e crie um novo projeto (`File -> New -> Project`).
2. Adicione todos os arquivos `.v` da pasta `/rtl` e o testbench de integração desejado da pasta `/testbenchs` (ex: `tb_camada_oculta.v`).
3. Compile todos os arquivos (`Compile -> Compile All`).
4. Inicie a simulação (`Simulate -> Start Simulation`) e selecione o módulo de testbench na aba *Work*.
5. Adicione os sinais desejados à janela **Wave** (`Add Wave`).
6. Execute o comando `run -all` no console para processar o fluxo completo de dados e verificar a sincronização dos sinais `h_saida`, `y_saida` e os endereçamentos de memória.

---

### 11.3 Casos de Teste

| Caso | Descrição | Ambiente | Resultado |
|------|-----------|----------|-----------|
| TC-01 | Validação individual do MAC (aritmética Q4.12) | EDA Playground | ✅ Passou |
| TC-02 | Validação do sigmoid piecewise (4 segmentos) | EDA Playground | ✅ Passou |
| TC-03 | Validação do argmax (10 entradas sequenciais) | EDA Playground | ✅ Passou |
| TC-04 | Sincronização da camada oculta (h_saida × referência Python) | ModelSim | ✅ Passou |
| TC-05 | Sincronização da camada de saída (y_saida × referência Python) | ModelSim | ✅ Passou |
| TC-06 | Saturação do MAC (overflow e underflow) | EDA Playground | ✅ Passou |
| TC-07 | Reset durante processamento (FSM → REPOUSO) | ModelSim | ✅ Passou |
| TC-08 | Inferência completa — K vetores MNIST | ModelSim | ✅ Passou |
| TC-09 | Dois START consecutivos sem reset | ModelSim | ✅ Passou |
| TC-10 | Validação na placa DE1-SoC | Hardware Real | ✅ Passou |

### 11.4 Automação via Terminal

Para ambientes Linux/WSL, a execução pode ser automatizada via `Makefile`.

---

## 12. Análise dos Resultados

### 12.1 Latência de Inferência

| Etapa | Ciclos |
|-------|--------|
| Camada oculta (784 × 128 MACs) | ~100.352 |
| Ativação sigmoid (128 neurônios) | 128 |
| Camada de saída (128 × 10 MACs) | ~1.280 |
| Argmax (10 comparações) | 10 |
| **Total** | **~101.770 ciclos** |
| **Latência @ 50 MHz** | **~2,03 ms por inferência** |

### 12.2 Principais dificuldades encontradas e como foram superadas

**Sincronização de sinais com latência de RAM**

As memórias inferidas pelo Quartus [[5]](#15-referências) introduzem 1 ciclo de latência. A solução foi adicionar registros de pipeline para atrasar os sinais de controle (`dado_valido`, `fim_neuronio`, `ultimo_neuronio`) de forma que eles cheguem ao MAC no mesmo ciclo que os dados lidos da RAM.

**Inferência incorreta com hardware e software errando para o mesmo valor**

O fato de ambos errarem para a mesma classe foi o indício que levou a equipe a investigar a camada de dados em vez da aritmética. A causa foi a diferença de convenção de linearização entre W\_in e β: enquanto W\_in é armazenada linha a linha (neurônio por neurônio), a matriz β original tinha sua dimensão de classes nas colunas. O hardware endereçava β esperando os pesos de cada classe contíguos, mas a matriz estava transposta. A correção foi realizar a transposição de β no script de geração do MIF, antes de linearizar.

**Integração da ISA ao datapath validado**

O acoplamento da ISA introduziu multiplexadores nos barramentos de endereço das RAMs (selecionando entre o endereço gerado pela FSM durante inferência e o endereço gerado pela ISA durante escrita). A validação foi feita garantindo que os resultados obtidos na simulação prévia continuavam corretos após a integração.

### 12.3 Observações finais

A ativação sigmoid piecewise linear — cuja abordagem é fundamentada em **Oliveira (2017)** [[7]](#15-referências) — introduz erro máximo de `±0.009` em relação ao sigmoid exato, dentro do tolerável para classificação de dígitos. O acumulador interno de 40 bits garante que não há overflow durante a fase de acumulação do MAC, com saturação aplicada apenas na saída para a faixa Q4.12. A validação em placa confirmou que o comportamento observado em simulação foi preservado no hardware real, corroborando os resultados obtidos em trabalhos similares de aceleração de ELM em FPGA [[2]](#15-referências).

---

## 13. Estrutura do Repositório

```
MI-SD/
├── README.md                   ← Este arquivo
│
├── assets/                     ← Recursos de dados do modelo
│   ├── images_mif/             ← Imagens de teste convertidas para formato MIF
│   └── images_png/             ← Imagens de teste no formato PNG (28×28, grayscale)
│
├── docs/                       ← Documentação complementar
│                               ← Diagramas, especificações e relatórios
│
├── quartus/                    ← Projeto Intel Quartus Prime
│                               ← Arquivos de síntese, pinos e saída (.sof)
│
├── rtl/                        ← Código-fonte Verilog (RTL)
│                               ← Todos os módulos do co-processador ELM
│
├── scripts/                    ← Scripts Python de suporte
│   ├── txt/                    ← Arquivos para uso nos testbenchs e elm_model.py 
│
├── simulation/                 ← Artefatos de simulação (ModelSim / Icarus)
│                               ← Testbenches, formas de onda e relatórios
│
└── testbenchs/                 ← Testbenches individuais por módulo
                                ← Validação unitária de cada submódulo RTL
```

---

## 14. Equipe

> _Iure Rocha Moreira Mendonça._
> _João Pedro da Silva Ferreira._
> _Thaylane da Silva._

---

## 15. Referências

1. **DE1-SoC User Manual** — Terasic Technologies. Disponível em: [fpgacademy.org](https://fpgacademy.org/boards.html)
2. **Accelerating Extreme Learning Machine on FPGA** — UTHM Publisher. Disponível em: [publisher.uthm.edu.my](https://publisher.uthm.edu.my/ojs/index.php/ijie/article/view/4431)
3. **Extreme learning machine: algorithm, theory and applications** — ResearchGate. Disponível em: [researchgate.net](https://www.researchgate.net/publication/257512921)
4. **A máquina de aprendizado extremo (ELM)** — Computação Inteligente. Disponível em: [computacaointeligente.com.br](https://computacaointeligente.com.br/algoritmos/maquina-de-aprendizado-extremo/)
5. **Intel Quartus Prime Lite Design Software** — versão 21.1.
6. **Icarus Verilog** — versão 11.0. Disponível em: [iverilog.icarus.com](http://iverilog.icarus.com/)
7. OLIVEIRA, J. G. M. *Uma arquitetura reconfigurável de Rede Neural Artificial utilizando FPGA*. Dissertação (Mestrado) – UNIFEI, Itajubá, 2017. Disponível em: [repositorio.unifei.edu.br/xmlui/handle/123456789/861](https://repositorio.unifei.edu.br/xmlui/handle/123456789/861)

---

## Marco 2 — Comunicação HPS↔FPGA

---

## 16. Visão Geral do Marco 2

Este marco implementa o lado do software: o código que roda no processador ARM (HPS) da DE1-SoC e envia instruções ao co-processador ELM sintetizado na FPGA. A comunicação é feita através do barramento **Lightweight HPS-to-FPGA AXI**, um canal de 32 bits mapeado no endereço físico `0xFF200000` que permite ao ARM escrever e ler registradores da FPGA diretamente via ponteiros de memória.

O fluxo completo de uma inferência a partir do HPS é:

1. Carregar os pesos W (100 352 elementos) na `ram_pesos` via opcode `STORE_WEIGHTS`
2. Carregar o bias (128 elementos) na `ram_bias` via opcode `STORE_BIAS`
3. Carregar os pesos β (1 280 elementos) na `ram_beta` via opcode `STORE_BETA`
4. Carregar a imagem (784 pixels) na `ram_img` via opcode `STORE_IMG`
5. Disparar a FSM com `START`
6. Disparar `STATUS` e ler o dígito predito nos bits `[7:4]` no terminal

> A ordem de carga dos pesos (passos 1–3) é livre entre si, mas todos devem
> ser enviados antes do `START`. O driver não impede disparar a inferência sem
> os pesos carregados — essa responsabilidade é do usuário.

---

## 17. Configuração do Platform Designer

Para que o HPS consiga enxergar o co-processador, três componentes **PIO (Parallel I/O)** foram adicionados ao `soc_system.qsys` no Platform Designer e conectados à porta mestre `h2f_lw_axi_master` do HPS:
<img width="767" height="660" alt="image" src="https://github.com/user-attachments/assets/6e16c395-be9d-4126-b795-340f37011193" />

| Componente | Direção | Offset (LW Bridge) | Função |
|---|---|---|---|
| `pio_readdata` | Input (32 bits) | `0x0000` | Leva o resultado da FPGA ao HPS (`hps_readdata`) |
| `pio_hpswrite` | Output (2 bits) | `0x0010` | Pulso de escrita e reset (`hps_write`) |
| `pio_instrucao` | Output (32 bits) | `0x0020` | Palavra de instrução de 32 bits (`instrucao`) |

Cada PIO foi exportado como `Conduit` e conectado nos fios correspondentes do top-level `ghrd_top.v` (`fio_instrucao`, `fio_hps_write`, `fio_hps_readdata`), que por sua vez chegam às portas do módulo `elm_accel`.

Após configurar os PIOs, o HDL foi regenerado via **Generate > Generate HDL...** e o projeto recompilado no Quartus para gravar o novo `.sof` na placa.

---

## 18. Geração do Cabeçalho de Endereços

Para que o software em C conheça os offsets de cada PIO sem hardcodá-los, o cabeçalho `hps_0.h` foi gerado a partir do arquivo `.sopcinfo` do projeto:

```bash
sopc-create-header-files "./soc_system.sopcinfo" --single hps_0.h --module hps_0
```

O arquivo gerado define constantes como `PIO_INSTRUCAO_BASE`, `PIO_HPSWRITE_BASE` e `PIO_READDATA_BASE` — os offsets de cada PIO dentro do espaço do Lightweight Bridge. São esses valores que as rotinas assembly usam para calcular os endereços virtuais após o `mmap`.

---

## 19. Driver em C e Rotinas Assembly

### 19.1 `/dev/mem` e `mmap` — acesso ao hardware a partir do Linux

O Linux que roda no HPS protege o acesso direto a endereços físicos. O caminho padrão é abrir `/dev/mem` — um arquivo especial que representa toda a memória física do sistema — e usar `mmap` para criar um mapeamento entre o endereço físico do barramento Lightweight HPS-to-FPGA (`0xFF200000`) e um ponteiro virtual acessível pelo processo:

```
/dev/mem  →  mmap(0xFF200000, 4KB)  →  ponteiro virtual
                     ↑
             base do LW Bridge
```

A partir desse ponteiro, somar um offset equivale a acessar diretamente o registrador físico correspondente na FPGA, como se fosse uma escrita no barramento AXI.

### 19.2 Compilação e execução

O driver é compilado cruzando C com Assembly diretamente no HPS:

```bash
gcc instrucoes.c rotinas.s -o driver
sudo ./driver
```

O `sudo` é necessário porque o acesso ao `/dev/mem` exige privilégios de root.

### 19.3 `instrucoes.c` — interface interativa

Ao executar, o programa apresenta um menu interativo onde o usuário escolhe qual instrução enviar ao co-processador. A depender da opção escolhida, o arquivo binário correspondente é aberto, seus dados são carregados em um buffer e a função assembly `processar_hardware_asm` é chamada com esse buffer, o opcode adequado e o número de elementos a enviar:

| Opção no menu | Arquivo lido | Opcode | Elementos |
|---|---|---|---|
| Carregar imagem | `quatro.bin` | `0x1` | 784 (uint8) |
| Carregar pesos W | `pesos.bin` | `0x2` | 100 352 (int16) |
| Carregar bias | `bias.bin` | `0x3` | 128 (int16) |
| Carregar beta | `beta.bin` | `0x4` | 1 280 (int16) |
| Start | — | `0x5` | — |
| Status | — | `0x0` | — |

O fluxo completo de uma inferência exige executar as opções na seguinte ordem: carregar todos os pesos (W, bias, beta), carregar a imagem, disparar o `start` e então consultar o `status` para ler o dígito predito.

A separação entre C e Assembly foi intencional: o C cuida da lógica de alto nível (menu, leitura de arquivos, alocação de buffer) enquanto o assembly lida diretamente com as syscalls e os acessos ao hardware.

### 19.4 `rotinas.s` — rotinas ARM Assembly

A função `processar_hardware_asm(buffer, opcode, limite)` implementa em ARM assembly o ciclo completo de acesso ao hardware:

**1. Abertura do `/dev/mem`** via syscall `SYS_OPEN` com flags `O_RDWR | O_SYNC` — o `O_SYNC` garante que nenhuma escrita seja cacheada pelo kernel antes de chegar ao hardware.

**2. Mapeamento via `mmap2`** — mapeia 4 KB a partir do offset `0xFF200` (endereço físico `0xFF200000`) para um endereço virtual em `r8`. Três ponteiros são calculados a partir dele:

| Registrador | Offset | PIO mapeado | Direção |
|---|---|---|---|
| `r1` | `+0x20` | `pio_instrucao` | HPS → FPGA (instrução 32 bits) |
| `r2` | `+0x10` | `pio_hpswrite` | HPS → FPGA (pulso de clock) |
| `r12` | `+0x00` | `pio_readdata` | FPGA → HPS (resultado/status) |

**3. Despacho por opcode** — um bloco de comparações seleciona o caminho correto:

- **Status (0x0):** escreve opcode 0 no `pio_instrucao`, pulsa, lê `pio_readdata`; verifica o bit `BUSY` e extrai os bits `[7:4]` com o dígito predito
- **Start (0x5):** monta a palavra `0x5000_0000` e pulsa uma vez
- **Pesos W (0x2):** protocolo de duas etapas por elemento — primeiro envia o endereço de 17 bits via opcode `0x6`, depois o dado via opcode `0x2` (necessário porque o campo `ADDR` da ISA tem apenas 12 bits e a `ram_pesos` tem 100 352 posições)
- **Demais (img, bias, beta):** loop que lê 8 bits (imagem) ou 16 bits (pesos) do buffer, monta a palavra `[opcode(4) | addr(12) | data(16)]` e pulsa

**4. `pulse_hw`** — sub-rotina que gera o pulso de escrita: escreve `0x2` em `pio_hpswrite` (borda de subida), aguarda ~150 ciclos de delay e escreve `0x0` (borda de descida). Esse sinal é o `hps_write` que o `decodificador_isa.v` usa para registrar a instrução.

**5. Encerramento** — `munmap` desfaz o mapeamento e `close` fecha o `/dev/mem`.

---

## 20. Estrutura da Pasta `hps/`

```
hps/
├── instrucoes.c   ← driver principal em C
├── rotinas.s      ← rotinas ARM assembly (syscalls + acesso ao hardware)
├── hps_0.h        ← cabeçalho com offsets dos PIOs gerado pelo sopcinfo
└── ghrd_top.v     ← top-level atualizado com os fios HPS↔ELM     
```

**Atenção:** o `ghrd_top.v` é o top-level do projeto Quartus — ele instancia tanto o `soc_system` (gerado pelo Platform Designer) quanto o `elm_accel` (co-processador desenvolvido no Marco 1), substituindo o top-level original do projeto base.
---

<div align="center">

*Universidade Estadual de Feira de Santana — UEFS · Departamento de Tecnologia · TEC 499 MI Sistemas Digitais 2026.1*

</div>
