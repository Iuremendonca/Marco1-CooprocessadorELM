#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "api.h"

static void cleanup(void) { exit_hw_asm(); }

/* Configuração de cada tipo de dado */
typedef struct {
    const char *arquivo;
    size_t      elem_bytes;
    uint32_t    limite;
} dado_t;

static const dado_t dados_cfg[] = {
    { "quatro.bin", 1, 784    },  /* j=0: img  */
    { "pesos.bin",  2, 100352 },  /* j=1: w    */
    { "bias.bin",   2, 128    },  /* j=2: bias */
    { "beta.bin",   2, 1280   },  /* j=3: beta */
};

int main(void) {
    if (init_hw_asm() != 0) {
        fprintf(stderr, "Erro: falha ao mapear /dev/mem.\n");
        return 1;
    }
    atexit(cleanup);

    /* Pré-carrega todos os buffers uma única vez */
    void *bufs[4] = {NULL};
    for (int j = 0; j < 4; j++) {
        const dado_t *cfg = &dados_cfg[j];

        FILE *f = fopen(cfg->arquivo, "rb");
        if (!f) { perror(cfg->arquivo); return 1; }

        bufs[j] = malloc(cfg->limite * cfg->elem_bytes);
        if (!bufs[j]) { fclose(f); fprintf(stderr, "Sem memória.\n"); return 1; }

        fread(bufs[j], cfg->elem_bytes, cfg->limite, f);
        fclose(f);
    }

    /* Loop de 10 inferências */
    for (int i = 0; i < 10; i++) {
        reset_hw_asm();
        printf("\n=== Inferência %d ===\n", i + 1);

        carregar_img_asm (bufs[0]);
        carregar_w_asm   (bufs[1]);
        carregar_bias_asm(bufs[2]);
        carregar_beta_asm(bufs[3]);

        uint32_t status[5] = {0};
        status_asm(status);

        printf("[0]    Busy       : %u\n", status[0]);
        printf("[1]    Done       : %u\n", status[1]);
        printf("[2]    Error      : %u\n", status[2]);
        printf("[7:4]  Resultado  : %u\n", status[3]);
        printf("[31:8] Ciclos     : %u\n\n", status[4]);
        start_asm();

        
        status_asm(status);

      
        printf("[0]    Busy       : %u\n", status[0]);
        printf("[1]    Done       : %u\n", status[1]);
        printf("[2]    Error      : %u\n", status[2]);
        printf("[7:4]  Resultado  : %u\n", status[3]);
        printf("[31:8] Ciclos     : %u\n", status[4]);
    }

    /* Libera buffers */
    for (int j = 0; j < 4; j++)
        free(bufs[j]);

    return 0;
}