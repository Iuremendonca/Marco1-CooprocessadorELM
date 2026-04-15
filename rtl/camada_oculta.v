module camada_oculta (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        calcular,         // Habilitador de operação (vindo da FSM)
    output reg         ultimo_neuronio,  // Pulso: todos os 128 neurônios concluídos
    output reg  [9:0]  addr_img,         // Endereço do pixel atual na RAM de imagem (0..783)
    output reg  [16:0] addr_peso,        // Endereço do peso atual na RAM de pesos (0..100351)
    output reg  [6:0]  addr_bias,        // Endereço do bias atual na RAM de bias (0..127)
    input  wire [7:0]         dado_img,  // Pixel lido da RAM (uint8, 0..255)
    input  wire signed [15:0] dado_peso, // Peso lido da RAM (Q4.12)
    input  wire signed [15:0] dado_bias, // Bias lido da RAM (Q4.12)
    output wire signed [15:0] h_saida,   // Saída do neurônio em Q4.12 (para sigmoid)
	 output wire         ativacao         // Pulso: h_saida é válido (repassado do MAC)
);

    // Normalização: uint8 → Q4.12
    wire signed [15:0] dado_img_norm;
    assign dado_img_norm = {4'b0000, dado_img[7:0], 4'b0000};

    // Contadores
    reg [9:0]  cnt_pixel;    
    reg [6:0]  cnt_neuronio; 
    reg [16:0] cnt_peso;     
	
	 // Flags de fim de iteração
    wire fim_pixel      = (cnt_pixel    == 10'd783);
    wire fim_neuronio_w = (cnt_neuronio == 7'd127);

    // Pipeline de 1 ciclo para alinhar com a latência de leitura das RAMs síncronas
    reg calcular_d;		// calcular atrasado 1 ciclo → valida dado lido da RAM
    reg fim_pixel_d;		// fim_pixel atrasado 1 ciclo → sinaliza fim de neurônio ao MAC

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calcular_d   <= 1'b0;
            fim_pixel_d  <= 1'b0;
        end else begin
            calcular_d   <= calcular;
            fim_pixel_d  <= fim_pixel & calcular;	// Só fecha neurônio se estiver calculando
        end
    end

	 
    // Lógica de contagem e geração de controle
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_pixel       <= 10'd0;
            cnt_neuronio    <= 7'd0;
            cnt_peso        <= 17'd0;
            ultimo_neuronio <= 1'b0;
        end else if (calcular) begin
            ultimo_neuronio <= 1'b0;
            cnt_peso        <= cnt_peso + 17'd1; // Avança sempre, 1 peso por ciclo

            if (fim_pixel) begin
					 // Fim do neurônio atual: reinicia pixel, avança neurônio
                cnt_pixel <= 10'd0;
                if (fim_neuronio_w) begin
						  // Fim da camada inteira: sinaliza e reinicia tudo
                    cnt_neuronio    <= 7'd0;
                    cnt_peso        <= 17'd0;    // Reseta só quando completa todos os neurônios
                    ultimo_neuronio <= 1'b1;		 // Pulso para FSM avançar de estado
                end else begin
                    cnt_neuronio <= cnt_neuronio + 7'd1;
                end
            end else begin
                cnt_pixel <= cnt_pixel + 10'd1;
            end
        end else begin
				// Quando calcular=0, mantém contadores zerados (idle)
            cnt_pixel       <= 10'd0;
            cnt_neuronio    <= 7'd0;
            cnt_peso        <= 17'd0;
            ultimo_neuronio <= 1'b0;
        end
    end

    // Endereços para as RAMs (combinacional)
    always @(*) begin
        addr_img   = cnt_pixel;    // Endereço do pixel: varia de 0 a 783 por neurônio
        addr_bias  = cnt_neuronio; // Endereço do bias: 1 por neurônio
        addr_peso  = cnt_peso;     // Endereço do peso: incrementa monotonicamente
    end

    

    // Instância do MAC
    mac u_mac (
        .clk         (clk),
        .rst_n       (rst_n),
        .dado_valido (calcular_d),	// Dado da RAM disponível 1 ciclo após o endereço
        .fim_neuronio(fim_pixel_d),	// Fecha neurônio após o último pixel
        .valor       (dado_img_norm),
        .peso        (dado_peso),
        .bias        (dado_bias),
        .saida       (h_saida),
		  .ativacao    (ativacao)		// Pulso de saída válida → vai para sigmoid e FSM
    );

endmodule