module camada_saida (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        calcula_saida,     // Habilitador de operação (vindo da FSM)
    output reg         ultimo_neuronio,   // Pulso: todas as 10 classes concluídas
    // Endereços para as RAMs
    output reg  [6:0]  addr_h,            // Endereço do neurônio oculto na RAM (0..127)
    output reg  [10:0] addr_peso_saida,   // Endereço do peso beta na RAM (0..1279)
    // Dados das RAMs
    input  wire signed [15:0] dado_h,    // Ativação h[j] lida da RAM (Q4.12, pós-sigmoid)
    input  wire signed [15:0] dado_peso_s, // Peso beta[j][i] lido da RAM (Q4.12)
    // Saída para argmax
    output wire signed [15:0] y_saida,   // Saída y[i] da classe atual (Q4.12)
    output wire               y_valida   // Pulso: y_saida pronto → argmax deve ler
);

    // Contadores
    reg [6:0]  cnt_h;       // Índice do neurônio oculto atual (0..127)
    reg [3:0]  cnt_classe;  // Índice da classe de saída atual (0..9)

	 // Flags de fim de iteração
    wire fim_h      = (cnt_h     == 7'd127); // Último neurônio oculto desta classe
    wire fim_classe = (cnt_classe == 4'd9);  // Última classe (dígito 9)

    // Pipeline de 1 ciclo para alinhar com a latência de leitura das RAMs síncronas
    reg calcula_d; // calcula_saida atrasado 1 ciclo → valida dados lidos
    reg fim_h_d;   // fim_h atrasado 1 ciclo → sinaliza fechamento de classe ao MAC

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calcula_d    <= 1'b0;
            fim_h_d      <= 1'b0;
        end else begin
            calcula_d    <= calcula_saida;
            fim_h_d      <= fim_h & calcula_saida;	// Fecha classe somente se ativo
        end
    end

    // Lógica de contagem e geração de controle
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_h           <= 7'd0;
            cnt_classe      <= 4'd0;
            ultimo_neuronio <= 1'b0;
        end else if (calcula_saida) begin
            ultimo_neuronio <= 1'b0;
            if (fim_h) begin
					 // Fim de uma classe: reinicia h, avança classe
                cnt_h <= 7'd0;
                if (fim_classe) begin
						  // Fim de todas as classes: sinaliza FSM e reinicia
                    cnt_classe      <= 4'd0;
                    ultimo_neuronio <= 1'b1; // Pulso para FSM ir ao estado FIM
                end else begin
                    cnt_classe <= cnt_classe + 4'd1;
                end
            end else begin
                cnt_h <= cnt_h + 7'd1;
            end
        end else begin
				// Idle: mantém contadores zerados
            cnt_h           <= 7'd0;
            cnt_classe      <= 4'd0;
            ultimo_neuronio <= 1'b0;
        end
    end

    // Endereços para as RAMs (combinacional)
    always @(*) begin
        addr_h          = cnt_h;
        addr_peso_saida = (cnt_h * 10) + cnt_classe;	//Calculo do endereço para percorrer a matriz pelas colunas
    end

	 
    // Instância do MAC
    mac u_mac_saida (
        .clk            (clk),
        .rst_n          (rst_n),
        .dado_valido    (calcula_d),     // Dado da RAM disponível após 1 ciclo
        .fim_neuronio   (fim_h_d),       // Fecha classe após h[127]
        .valor          (dado_h),        // Ativação h[j] pós-sigmoid
        .peso           (dado_peso_s),   // Peso beta[j][i]
        .bias           (16'sd0),        // Sem bias na camada de saída
        .saida          (y_saida),       // Score da classe i (Q4.12) → argmax
        .ativacao       (y_valida)       // Pulso por classe: argmax deve registrar y_saida
    );

endmodule