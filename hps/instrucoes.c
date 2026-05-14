#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Protótipo: r0 = buffer, r1 = opcode, r2 = limite
extern uint32_t processar_hardware_asm(void *buffer, uint32_t opcode, uint32_t limite);

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Uso: ./driver <img|bias|beta|w|start|status>\n");
        return 1;
    }

    char *tipo = argv[1];
    uint32_t opcode = 0, limite = 0;
    char *filename = NULL;

    // --- Chamadas Diretas de Função ---
    if (strcmp(tipo, "start") == 0) {
        processar_hardware_asm(NULL, 5, 1);
        printf("Inferência disparada.\n");
        return 0;
    } 

    if (strcmp(tipo, "status") == 0) {
        uint32_t resultado = processar_hardware_asm(NULL, 0, 1);
        printf("Resultado do hardware: %u\n", resultado);
        return 0;
    }

    // --- Mapeamento de Arquivos e Opcodes ---
    if (strcmp(tipo, "img") == 0)       { filename = "quatro.bin"; opcode = 1; limite = 784; }
    else if (strcmp(tipo, "w") == 0)    { filename = "pesos.bin";  opcode = 2; limite = 100352; }
    else if (strcmp(tipo, "bias") == 0) { filename = "bias.bin";   opcode = 3; limite = 128; }
    else if (strcmp(tipo, "beta") == 0) { filename = "beta.bin";   opcode = 4; limite = 1280; }
    else { return 1; }

    // --- Conversão e Carga de Arquivos ---
    FILE *f = fopen(filename, "rb");
    if (!f) { perror("Erro ao abrir arquivo"); return 1; }

    // Imagem (8-bit), demais (16-bit)
    size_t sz = (opcode == 1) ? 1 : 2; 
    void *data_buffer = malloc(limite * sz);
    fread(data_buffer, sz, limite, f);
    fclose(f);

    // Envio direto ao driver
    processar_hardware_asm(data_buffer, opcode, limite);

    free(data_buffer);
    printf("Carga de %s concluída.\n", tipo);
    return 0;
}