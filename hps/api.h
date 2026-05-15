#ifndef HW_API_H
#define HW_API_H

#include <stdint.h>

/* Ciclo de vida */
int  init_hw_asm(void);     /* 0 = sucesso, -1 = falha */
void exit_hw_asm(void);

/* Controle */
void reset_hw_asm(void);
void start_asm(void);

/* Carga de dados */
void carregar_img_asm (void *buffer);
void carregar_w_asm   (void *buffer);
void carregar_bias_asm(void *buffer);
void carregar_beta_asm(void *buffer);

/* Status — retorna valor bruto; preenche dados[0..4] */
uint32_t status_asm(uint32_t *dados);

#endif
