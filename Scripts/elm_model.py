"""
elm_hw_model.py
===============
Modelo Python bit-accurate da inferência ELM implementada em hardware.

Segue exatamente a mesma lógica dos módulos Verilog:
  • Representação em ponto fixo Q4.12  (int16, 12 bits fracionários)
  • Normalização de imagem: uint8 → Q4.12  (shift left 4 bits)
  • MAC com acumulador de 40 bits e saturação para int16
  • Sigmoid aproximada por partes (4 segmentos, aritmética inteira)
  • Camada de saída: MAC sem sigmoid, bias = 0
  • Argmax para obter o dígito predito

Uso rápido
----------
    python elm_hw_model.py \\
        --weights weights.txt \\
        --beta    beta.txt    \\
        --bias    bias.txt    \\
        --image   image.txt   \\
        --label   label.txt
"""

import argparse
import sys
import numpy as np


# =============================================================================
# Constantes de ponto fixo (espelham os localparam do Verilog)
# =============================================================================
FRAC_BITS   = 12          # Q4.12
SCALE       = 1 << FRAC_BITS   # 4096

INT16_MAX   =  32767      # 16'h7FFF
INT16_MIN   = -32768      # 16'h8000

# Sigmoid por partes — constantes em Q4.12 (hex → decimal)
V_0_5       = 0x0800      # 2048   → 0.5
V_0_625     = 0x0A00      # 2560   → 0.625
V_0859375   = 0x0DC0      # 3520   → 0.859375
V_1_0       = 0x1000      # 4096   → 1.0

LIMIT_1_0   = 0x1000      # 4096   → |x| < 1.0
LIMIT_2_5   = 0x2800      # 10240  → |x| < 2.5
LIMIT_4_5   = 0x4800      # 18432  → |x| < 4.5


# =============================================================================
# Utilitários de ponto fixo
# =============================================================================

def to_int16(value: int) -> int:
    """Trunca para 16 bits com sinal (simula [15:0] Verilog)."""
    value = int(value) & 0xFFFF
    if value >= 0x8000:
        value -= 0x10000
    return value


def saturate_int16(value: int) -> int:
    """Saturação idêntica ao MAC do hardware."""
    if value > INT16_MAX:
        return INT16_MAX
    if value < INT16_MIN:
        return INT16_MIN
    return int(value)


def float_to_q412(value: float) -> int:
    """Converte float → int16 Q4.12 (para geração de pesos externos)."""
    return saturate_int16(round(value * SCALE))


def q412_to_float(value: int) -> float:
    """Converte int16 Q4.12 → float (apenas para exibição)."""
    return value / SCALE


# =============================================================================
# MAC — 40 bits, ponto fixo Q4.12
# =============================================================================

def mac(valores: list[int], pesos: list[int], bias: int) -> int:
    """Executa o MAC de um neurônio inteiro."""
    assert len(valores) == len(pesos), "MAC: tamanhos incompatíveis"

    acumulador: int = 0

    for i, (v, p) in enumerate(zip(valores, pesos)):
        mult_atual = int(v) * int(p) 

        fim_neuronio = (i == len(valores) - 1)

        if fim_neuronio:
            bias_alinhado = int(bias) << FRAC_BITS
            soma_final = acumulador + mult_atual + bias_alinhado
            resultado_shiftado = soma_final >> FRAC_BITS 
            saida = saturate_int16(resultado_shiftado)
        else:
            acumulador += mult_atual

    return saida


# =============================================================================
# Sigmoid aproximada por partes
# =============================================================================

def sigmoid_hw(x: int) -> int:
    """Sigmoid por partes em aritmética inteira Q4.12."""
    x = to_int16(x)

    e_negativo     = (x < 0)
    valor_absoluto = (-x) & 0xFFFF if e_negativo else x & 0xFFFF

    if valor_absoluto < LIMIT_1_0:
        d_out_comb = (valor_absoluto >> 2) + V_0_5
    elif valor_absoluto < LIMIT_2_5:
        d_out_comb = (valor_absoluto >> 3) + V_0_625
    elif valor_absoluto < LIMIT_4_5:
        d_out_comb = (valor_absoluto >> 5) + V_0859375
    else:
        d_out_comb = V_1_0

    if e_negativo:
        d_out_comb = V_1_0 - d_out_comb

    return to_int16(d_out_comb)


# =============================================================================
# Normalização de imagem
# =============================================================================

def normalizar_pixel(pixel: int) -> int:
    """uint8 [0,255] → int16 Q4.12 (shift left 4)."""
    return to_int16(int(pixel) << 4)


# =============================================================================
# Camadas e Inferência
# =============================================================================

def camada_oculta(img_norm: list[int], W: list[list[int]], bias: list[int]) -> list[int]:
    h = []
    for j in range(len(W)):
        mac_out = mac(img_norm, W[j], bias[j])
        h_j     = sigmoid_hw(mac_out)
        h.append(h_j)
    return h


def camada_saida(h: list[int], beta: list[list[int]]) -> list[int]:
    n_classes  = len(beta[0])
    n_neuronios = len(h)
    y = []
    for c in range(n_classes):
        pesos_c = [beta[n][c] for n in range(n_neuronios)]
        y_c = mac(h, pesos_c, bias=0)
        y.append(y_c)
    return y


def argmax_hw(y: list[int]) -> int:
    max_val    = INT16_MIN
    max_idx    = 0
    for idx, val in enumerate(y):
        val = to_int16(val)
        if val > max_val:
            max_val = val
            max_idx = idx
    return max_idx


def inferencia(image: list[int], W: list[list[int]], beta: list[list[int]], bias: list[int], verbose: bool = False) -> int:
    img_norm = [normalizar_pixel(p) for p in image]
    h = camada_oculta(img_norm, W, bias)
    y = camada_saida(h, beta)
    return argmax_hw(y)


# =============================================================================
# Carregamento de arquivos (CORRIGIDO PARA SUPORTAR HEX NA IMAGEM)
# =============================================================================

def carregar_txt(path: str, base: int = 10) -> list:
    """Lê arquivo .txt convertendo para inteiro na base especificada."""
    with open(path, "r") as f:
        return [int(linha.strip(), base) for linha in f if linha.strip()]


def carregar_pesos(path: str, n_neuronios: int = 128, n_pixels: int = 784) -> list[list[int]]:
    flat = carregar_txt(path, base=10)
    assert len(flat) == n_neuronios * n_pixels
    return [flat[j * n_pixels:(j + 1) * n_pixels] for j in range(n_neuronios)]


def carregar_beta(path: str, n_neuronios: int = 128, n_classes: int = 10) -> list[list[int]]:
    flat = carregar_txt(path, base=10)
    assert len(flat) == n_neuronios * n_classes
    return [flat[j * n_classes:(j + 1) * n_classes] for j in range(n_neuronios)]


# =============================================================================
# CLI e Main
# =============================================================================

def parse_args():
    p = argparse.ArgumentParser(description="Modelo Python bit-accurate do ELM (Q4.12).")
    p.add_argument("--weights", default="weights.txt")
    p.add_argument("--beta",    default="beta.txt")
    p.add_argument("--bias",    default="bias.txt")
    p.add_argument("--image",   default="image.txt")
    p.add_argument("--label",   default="label.txt")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args()


def main():
    args = parse_args()

    print("=" * 50)
    print("  ELM Hardware Model — Python bit-accurate")
    print("=" * 50)

    # Carregamento
    W    = carregar_pesos(args.weights)
    beta = carregar_beta(args.beta)
    bias = carregar_txt(args.bias, base=10)
    
    # Imagem carregada em base 16 (Hexadecimal)
    print(f"[*] Carregando imagem (HEX): {args.image}")
    image = carregar_txt(args.image, base=16)
    
    assert len(bias) == 128
    assert len(image) == 784

    label_esperado = carregar_txt(args.label, base=10)[0]

    # Inferência
    digito = inferencia(image, W, beta, bias, verbose=args.verbose)

    # Resultado
    print("\n" + "=" * 50)
    print(f"  Resultado HW (Python) : {digito}")
    print(f"  Label esperado        : {label_esperado}")
    status = "PASS ✓" if digito == label_esperado else "FAIL ✗"
    print(f"  Status                : {status}")
    print("=" * 50)

    sys.exit(0 if digito == label_esperado else 1)


if __name__ == "__main__":
    main()