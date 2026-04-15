import os

def int_to_16bit_hex(valor_inteiro):
    """
    Converte um número inteiro com sinal para uma string hexadecimal de 16 bits,
    aplicando o complemento de 2 para números negativos.
    """
    # Garante que o valor está dentro do limite de 16 bits com sinal
    if valor_inteiro > 32767:
        valor_inteiro = 32767
    elif valor_inteiro < -32768:
        valor_inteiro = -32768
        
    # Aplica a máscara de 16 bits (0xFFFF) que faz o complemento de 2 automaticamente no Python
    valor_hex = valor_inteiro & 0xFFFF
    
    # Retorna formatado com 4 dígitos hexadecimais maiúsculos
    return f"{valor_hex:04X}"

def processar_arquivo(arquivo_entrada, arquivo_saida_txt, arquivo_saida_mif, depth):
    """
    Lê o TXT com inteiros decimais e gera o TXT hexadecimal e o arquivo MIF.
    """
    try:
        # 1. LER O ARQUIVO ORIGINAL
        with open(arquivo_entrada, 'r') as f:
            # Lê as linhas, remove espaços e ignora linhas vazias
            linhas = [linha.strip() for linha in f.readlines() if linha.strip()]
            
        # Converte as strings para inteiros puros
        valores_inteiros = [int(linha) for linha in linhas]
        
        # 2. GERAR O ARQUIVO TXT HEXADECIMAL (Para o Testbench / $readmemh)
        with open(arquivo_saida_txt, 'w') as f_txt:
            for valor in valores_inteiros:
                f_txt.write(f"{int_to_16bit_hex(valor)}\n")
                
        # 3. GERAR O ARQUIVO .MIF (Para o Quartus / FPGA)
        with open(arquivo_saida_mif, 'w') as f_mif:
            f_mif.write(f"DEPTH = {depth};\n")
            f_mif.write("WIDTH = 16;\n")
            f_mif.write("ADDRESS_RADIX = HEX;\n")
            f_mif.write("DATA_RADIX = HEX;\n")
            f_mif.write("CONTENT\n")
            f_mif.write("BEGIN\n")
            
            for addr, valor in enumerate(valores_inteiros):
                if addr >= depth:
                    break # Evita estourar o limite da memória
                hex_str = int_to_16bit_hex(valor)
                f_mif.write(f"{addr:X} : {hex_str};\n")
                
            # Preenche o resto da memória com zeros, se faltarem dados
            if len(valores_inteiros) < depth:
                inicio = len(valores_inteiros)
                fim = depth - 1
                if inicio == fim:
                    f_mif.write(f"{inicio:X} : 0000;\n")
                else:
                    f_mif.write(f"[{inicio:X}..{fim:X}] : 0000;\n")
                    
            f_mif.write("END;\n")
            
        print(f"SUCESSO: '{arquivo_entrada}' -> Gerou '{arquivo_saida_txt}' e '{arquivo_saida_mif}'.")
        
    except FileNotFoundError:
        print(f"ERRO: Arquivo '{arquivo_entrada}' não encontrado.")
    except ValueError as e:
        print(f"ERRO: Encontrado um valor que não é um número inteiro em '{arquivo_entrada}'. Detalhes: {e}")

# ==========================================
# Execução Principal
# ==========================================
if __name__ == "__main__":
    # Dicionário de arquivos: 
    # "Nome do seu arquivo original" : ("Nome Base da Saída", Profundidade da RAM)
    arquivos = {
        "b_q.txt": ("bias", 128),
        "W_in_q.txt": ("w_in", 100352),
        "beta_q.txt": ("beta", 1280)
    }
    
    print("Iniciando conversões...\n")
    for arq_in, (nome_base_saida, depth) in arquivos.items():
        arq_out_txt = f"{nome_base_saida}_hex.txt"
        arq_out_mif = f"{nome_base_saida}.mif"
        
        processar_arquivo(arq_in, arq_out_txt, arq_out_mif, depth)