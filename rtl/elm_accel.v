module elm_accel (
    input  wire clk,
    input  wire rst_n,
    input  wire [31:0] instrucao, // Instrução de 32 bits vinda do HPS
    input  wire        hps_write, // Sinal de modo: 0=ler/executar, 1=HPS escrevendo
    output [31:0] hps_readdata    // Dado de retorno ao HPS (status/resultado)
);

    // Sinais internos - FSM
    wire        calcular;      // FSM → camada oculta: habilita cálculo
    wire        calcula_saida; // FSM → camada de saída: habilita cálculo
    wire [2:0]  estado;        // Estado atual da FSM (usado para mux de endereços)
    wire        pronto;        // FSM → ISA/argmax: inferência concluída
    
    // Sinais internos - Camada Oculta
    wire        ultimo_neuronio; // Camada oculta → FSM: todos 128 neurônios prontos
    wire        ativacao;        // MAC oculto → FSM/sigmoid: neurônio calculado
    wire [9:0]  addr_img;        // Endereço do pixel para ram_img
    wire [16:0] addr_peso;       // Endereço do peso W para ram_pesos
    wire [6:0]  addr_bias;       // Endereço do bias para ram_bias
    wire signed [15:0] h_saida;  // Saída pré-ativação do neurônio oculto (Q4.12)

    // Sinais internos - RAMs
    wire [7:0]         dado_img;      // Pixel lido da ram_img
    wire signed [15:0] dado_peso;     // Peso W lido da ram_pesos
    wire signed [15:0] dado_bias;     // Bias lido da ram_bias
    wire signed [15:0] dado_neuronio; // Ativação h[j] lida da ram_neuroniosativos
	 
    // Sinais internos - Camada Saída
    wire        ultimo_neuronio_saida; // Camada saída → FSM: todas 10 classes prontas
    wire        y_valida;              // MAC saída → argmax: score y[i] disponível
    wire signed [15:0] y_saida;        // Score da classe atual (Q4.12)
    wire [6:0]  addr_h;                // Endereço de h[j] para ram_neuroniosativos
    wire [10:0] addr_peso_saida;       // Endereço de beta para ram_beta
    wire signed [15:0] dado_peso_s;   // Peso beta lido da ram_beta
    wire [3:0]  resultado;            // Classe predita (saída do argmax, 0..9)
	 
    // Ativação Sigmoid
    wire signed [15:0] h_ativado; // Saída pós-sigmoid do neurônio oculto (Q4.12)
    wire [6:0]         addr_neur; // Endereço para escrita na ram_neuroniosativos
	 
    // Sinais internos - Decoder ISA
    wire [31:0] hps_data;
    assign hps_readdata = hps_data; // Passa dado de status ao HPS

    wire start;       // Pulso de início de inferência (ISA → FSM)
	 
    // Sinais de escrita nas RAMs pelo HPS
    wire wren_w, wren_img, wren_bias, wren_beta; // Enables de escrita por RAM
    wire [16:0] w_addr;   // Endereço de escrita na ram_pesos
    wire [9:0]  img_addr; // Endereço de escrita na ram_img
    wire [6:0]  bias_addr;// Endereço de escrita na ram_bias
    wire [10:0] beta_addr;// Endereço de escrita na ram_beta
    wire signed [15:0] data_to_mem; // Dado a ser escrito (compartilhado entre RAMs)
	 
	 // ---------------------------------------------------------------
    // Decodificador ISA — interface HPS ↔ acelerador
	 // ---------------------------------------------------------------
	 decodificador_isa isa (
		 .clk(clk),
		 .rst_n(rst_n),
		 
		 .instrucao(instrucao),
		 .hps_write(hps_write),
		 .hps_readdata(hps_data),
		 
		 // Status da FSM para leitura pelo HPS
		 .fsm_busy(estado != 1'b0 ? 1'b1: 1'b0),	// Qualquer estado != REPOUSO = busy
		 .fsm_done(pronto),
		 .elm_result(resultado),
		 .start_pulse(start),
		 
		 // Endereços e dados para carga das RAMs
		 .w_addr(w_addr),
		 .img_addr(img_addr),
		 .bias_addr(bias_addr),
		 .beta_addr(beta_addr),
		 .data_to_mem(data_to_mem),
		 .wren_w(wren_w),
		 .wren_img(wren_img),
		 .wren_bias(wren_bias),
		 .wren_beta(wren_beta)
	 );
	 
	 
	 
    // ---------------------------------------------------------------
    // FSM — sequencia os estados de inferência
    // ---------------------------------------------------------------
    fsm_elm u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .ultimo_neuronio (ultimo_neuronio),
		  .ultimo_neuronio_saida (ultimo_neuronio_saida),
        .ativacao        (ativacao),
        .pronto          (pronto),
        .calcular        (calcular),
        .calcula_saida   (calcula_saida),
        .estado          (estado)
    );
    // ---------------------------------------------------------------
    // Camada Oculta — 128 neurônios, 784 entradas cada
    // ---------------------------------------------------------------
    camada_oculta u_oculta (
        .clk            (clk),
        .rst_n          (rst_n),
        .calcular       (calcular),
        .ultimo_neuronio(ultimo_neuronio),
        .addr_img       (addr_img),
        .addr_peso      (addr_peso),
        .addr_bias      (addr_bias),
        .dado_img       (dado_img),
        .dado_peso      (dado_peso),
        .dado_bias      (dado_bias),
        .h_saida        (h_saida),	// Pré-ativação → sigmoid
        .ativacao       (ativacao)	// Pulso de saída válida
    );

	 // ---------------------------------------------------------------
	 // Função de Ativação Sigmoid (aproximação linear por partes)
	 // Também gera endereço sequencial para escrita em ram_neuroniosativos
	 // ---------------------------------------------------------------
    ativacao_sigmoid u_sigmoid (
        .clk      (clk),
        .rst_n    (rst_n),
        .d_in     (h_saida),     // Recebe saída do MAC da camada oculta
        .ativacao (ativacao),    // Habilita cálculo e conta endereço
        .d_out    (h_ativado),   // Saída pós-sigmoid → RAM de neurônios ativos
        .addr_out (addr_neur)    // Endereço sequencial para escrita
    );
	 
    // ---------------------------------------------------------------
    // Camada de Saída — 10 classes (linear, sem ativação)
    // ---------------------------------------------------------------
    camada_saida u_saida (
        .clk            (clk),
        .rst_n          (rst_n),
        .calcula_saida  (calcula_saida),
        .ultimo_neuronio(ultimo_neuronio_saida),
        .addr_h         (addr_h),
        .addr_peso_saida(addr_peso_saida),
        .dado_h         (dado_neuronio),   // Ativações h[j] da RAM
        .dado_peso_s    (dado_peso_s),     // Pesos beta da RAM
        .y_saida        (y_saida),         // Score y[i] da classe atual
        .y_valida       (y_valida)         // Pulso: y_saida válido → argmax
    );
    // ---------------------------------------------------------------
    // Argmax — determina classe com maior score
    // ---------------------------------------------------------------
    argmax u_argmax (
        .clk      (clk),
        .rst_n    (rst_n),
        .pronto   (pronto),    // Captura resultado final ao término da inferência
        .clear    (start),     // Reinicia comparação a cada nova inferência
        .y_in     (y_saida),   // Score da classe atual
        .update_en(y_valida),  // Pulso por classe
        .saida    (resultado)  // Dígito predito → ISA (retorna ao HPS)
    );
	 
	 
	 // ---------------------------------------------------------------
    // RAMs — Mux de endereço: HPS (carga) vs acelerador (inferência)
    // Quando estado != REPOUSO (estado[0] != 0), acelerador controla, caso contrário, o HPS escreve via ISA.
    // ---------------------------------------------------------------
    
	 // RAM de imagem: 784 × 8 bits
	 ram_img u_ram_img (
        .clock   (clk),
        .address (estado != 1'b0 ? addr_img: img_addr),  // Mux: inferência vs carga
        .data    (data_to_mem[7:0]),                         // Apenas 8 bits do dado HPS
        .rden    (calcular),
        .wren    (wren_img),
        .q       (dado_img)
    );
	 
	 // RAM de pesos W: 100352 × 16 bits (camada oculta)
    ram_pesos u_ram_pesos (
        .clock   (clk),
        .address (estado != 1'b0 ? addr_peso: w_addr),
        .data    (data_to_mem),
        .rden    (calcular),
        .wren    (wren_w),
        .q       (dado_peso)
    );
	 
	 // RAM de bias: 128 × 16 bits (camada oculta)
    ram_bias u_ram_bias (
        .clock   (clk),
        .address (estado != 1'b0 ? addr_bias: bias_addr),
        .data    (data_to_mem),
        .rden    (calcular),
        .wren    (wren_bias),
        .q       (dado_bias)
    );
	 
	 // RAM de neurônios ativos: 128 × 16 bits (armazena h[j] pós-sigmoid)
	 // Escrita: feita pelo módulo sigmoid durante CALC_OCULTO
    // Leitura: feita pela camada de saída durante CALC_SAIDA
    ram_neuroniosativos u_ram_neur (
        .clock   (clk),
        .address (calcula_saida ? addr_h : addr_neur),	// Mux: leitura vs escrita
        .data    (h_ativado),										// Saída pós-sigmoid
        .rden    (calcula_saida),
        .wren    (ativacao && (estado == 3'd1)),			// Escreve só em CALC_OCULTO
        .q       (dado_neuronio)
    );
	 
	 // RAM de pesos beta: 1280 × 16 bits (camada de saída)
    ram_beta u_ram_beta (
        .clock   (clk),
        .address (estado != 1'b0 ? addr_peso_saida: beta_addr),
        .data    (data_to_mem),
        .rden    (calcula_saida),
        .wren    (wren_beta),
        .q       (dado_peso_s)
    );

endmodule