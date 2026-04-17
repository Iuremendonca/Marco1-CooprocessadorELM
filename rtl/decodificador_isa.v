module decodificador_isa (
    input clk,
    input rst_n,
    
    input [31:0] instrucao,          // Instrução de 32 bits do HPS
    input         hps_write,         // 0 = leitura/execução; 1 = o HPS está escrevendo (ignora)
    output reg [31:0] hps_readdata,  // Dado de retorno para o HPS (status/resultado)
    
    // Interface com a FSM
    input         fsm_busy,          // 1 = acelerador ocupado (não aceita novos comandos)
    input         fsm_done,          // 1 = inferência concluída
    input  [3:0]  elm_result,        // Classe predita pelo argmax (0..9)
    output reg    start_pulse,       // Pulso de início de inferência → FSM
    
    // Interfaces de escrita nas RAMs
    output reg [16:0] w_addr,        // Endereço na RAM de pesos (0..100351)
    output reg [9:0]  img_addr,      // Endereço na RAM de imagem (0..783)
    output reg [6:0]  bias_addr,     // Endereço na RAM de bias (0..127)
    output reg [10:0] beta_addr,     // Endereço na RAM de beta (0..1279)
    output reg signed [15:0] data_to_mem, // Dado a ser escrito na RAM selecionada
    output reg wren_w, wren_img, wren_bias, wren_beta // Sinais de habilitação de escrita

);

    reg [31:0] save_instrucao;  // Instrução registrada na borda do clock
    reg        error_flag;      // Flag de erro persistente (mantém até reset)

    // Decodificação dos campos da instrução registrada
    wire [3:0]  opcode  = save_instrucao[31:28]; // Tipo de operação
    wire [11:0] addr_in = save_instrucao[27:16]; // Endereço genérico (12 bits)
    wire [15:0] data_in = save_instrucao[15:0];  // Dado a escrever (16 bits)
    wire [16:0] addr_win = save_instrucao[16:0]; // Endereço longo para pesos W (17 bits)

    reg [16:0] temp_w_addr;	// Endereço W configurado previamente por opcode 0x6

	 reg [31:0] ciclo_count;	//

	// Lógica do contador de ciclos
	always @(posedge clk) begin
		 if (!rst_n || start_pulse) begin
			  ciclo_count <= 32'b0; // Reseta ao iniciar nova inferência
		 end else if (fsm_busy) begin
			  ciclo_count <= ciclo_count + 1'b1; // Incrementa enquanto a FSM trabalha
		 end
	end
	 
	 
    // Captura e validação da instrução recebida
    always @(posedge clk) begin
        if (!rst_n) begin
            save_instrucao <= 32'b0;
            error_flag     <= 1'b0;
        end else begin
            save_instrucao <= instrucao;	// Registra instrução a cada ciclo
            // Detecta opcode inválido (> 6) quando o HPS está escrevendo
            if (!hps_write && (instrucao[31:28] > 4'h7))
                error_flag <= 1'b1;	// Seta flag e mantém até reset
					// Limpa erro apenas com reset
        end
    end

    // Decodificação e execução das instruções
    always @(posedge clk) begin
        if (!rst_n) begin
            w_addr        <= 0;
            img_addr      <= 0;
            bias_addr     <= 0;
            beta_addr     <= 0;
            temp_w_addr   <= 0;
            data_to_mem   <= 0;
            hps_readdata  <= 32'b0;
				// Desativa todos os sinais de escrita e start
            {wren_w, wren_img, wren_bias, wren_beta, start_pulse} <= 5'b0;
        end else begin
				// Default: desativa todos os enables (pulsos de 1 ciclo)
            {wren_w, wren_img, wren_bias, wren_beta, start_pulse} <= 5'b0;
				
				//Só executa quando: HPS está em modo write E FSM não está ocupada
            if (!hps_write && !fsm_busy) begin
                case (opcode)
                    // STATUS: retorna palavra de estado ao HPS
						  // Formato: [31:8]=0, [7:4]=resultado, [3]=0, [2]=error, [1]=done, [0]=busy
                    4'h0: begin
                        hps_readdata <= {
                            24'b0,
                            elm_result,   // Dígito predito (bits 7:4)
                            1'b0,
                            error_flag,   // Bit de erro persistente
                            fsm_done,     // Inferência concluída
                            fsm_busy      // Acelerador ocupado
                        };
                    end

                    // STORE IMG: escreve 1 pixel na RAM de imagem
                    4'h1: begin
                        img_addr    <= addr_in[9:0]; // Endereço do pixel (0..783)
                        data_to_mem <= data_in;       // Valor do pixel (uint8)
                        wren_img    <= 1'b1;          // Habilita escrita
                    end

                    // STORE W: escreve 1 peso na RAM de pesos
                    // O endereço vem de temp_w_addr configurado pelo opcode 0x6
                    4'h2: begin
                        w_addr      <= temp_w_addr; // Endereço longo previamente configurado
                        data_to_mem <= data_in;		 // Peso em Q4.12
                        wren_w      <= 1'b1;
                    end

                    // STORE B: escreve 1 bias na RAM de bias
                    4'h3: begin
                        bias_addr   <= addr_in[6:0]; // Índice do neurônio (0..127)
                        data_to_mem <= data_in;		  // Bias em Q4.12
                        wren_bias   <= 1'b1;
                    end

                    // STORE BETA: escreve 1 peso da camada de saída
                    4'h4: begin
                        beta_addr   <= addr_in[10:0];	// Índice do peso beta (0..1279)
                        data_to_mem <= data_in;		  	// Peso beta em Q4.12
                        wren_beta   <= 1'b1;
                    end

                    // START: dispara inferência
                    4'h5: begin
                        start_pulse <= 1'b1;	// Pulso de 1 ciclo para FSM
                    end

                    // STORE W ADDR: configura o endereço base para próximas escritas de W
                    // Necessário pois W usa 17 bits (acima do addr_in de 12 bits)
                    4'h6: begin
                        temp_w_addr <= addr_win; // Guarda endereço para uso no opcode 0x2
                    end
						  
						  4'h7: begin
								// CYCLE: Retorna a quantidade de ciclos da inferencia
								hps_readdata <= ciclo_count;
						  end

                    default: begin
                        // Opcode inválido: erro já registrado no bloco de captura acima
                    end
                endcase
            end
        end
    end

endmodule