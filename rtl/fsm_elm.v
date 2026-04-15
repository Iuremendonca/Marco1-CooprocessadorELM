module fsm_elm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,                  // Pulso de início de inferência
    input  wire        ultimo_neuronio,         // Pulso: camada oculta concluída
    input  wire        ultimo_neuronio_saida,   // Pulso: camada de saída concluída
    input  wire        ativacao,               // Pulso do MAC: último neurônio calculado
    output reg         pronto,                 // Sinal de conclusão da inferência
    output reg         calcular,              // Habilita camada oculta
    output reg         calcula_saida,         // Habilita camada de saída
    output reg  [2:0]  estado                 // Estado atual (para debug e mux de RAM)
);
		
	 // Codificação dos estados
    localparam REPOUSO     = 3'd0, // Aguardando 'start'
               CALC_OCULTO = 3'd1, // Calculando camada oculta (128 neurônios)
               CALC_SAIDA  = 3'd2, // Calculando camada de saída (10 classes)
               FIM         = 3'd3; // Inferência concluída

    reg [2:0] proximo_estado;

	 // Registro de estado: atualiza na borda de subida
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) estado <= REPOUSO;
        else        estado <= proximo_estado;
    end

	 
    // foi_ultimo_oculto: captura ultimo_neuronio em CALC_OCULTO
    reg foi_ultimo_oculto;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            foi_ultimo_oculto <= 1'b0;
        else if (ultimo_neuronio && (estado == CALC_OCULTO))
            foi_ultimo_oculto <= 1'b1;	// Seta quando último neurônio é detectado
        else if (estado == CALC_SAIDA)
            foi_ultimo_oculto <= 1'b0;	// Limpa ao entrar no estado seguinte
    end

    // foi_ultimo_saida: captura ultimo_neuronio em CALC_SAIDA
    reg foi_ultimo_saida;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            foi_ultimo_saida <= 1'b0;
        else if (ultimo_neuronio_saida && (estado == CALC_SAIDA))
            foi_ultimo_saida <= 1'b1;	// Seta quando última classe é concluída
        else if (estado == FIM)
            foi_ultimo_saida <= 1'b0;	// Limpa ao entrar em FIM
    end

	 // Lógica de próximo estado (combinacional)
    always @(*) begin
        proximo_estado = estado;	// Mantém estado por padrão
        case (estado)
            REPOUSO: begin
                if (start) proximo_estado = CALC_OCULTO;
            end
            CALC_OCULTO: begin
					 // Só avança quando o MAC confirma conclusão do último neurônio
                if (ativacao) begin
                    if (foi_ultimo_oculto) proximo_estado = CALC_SAIDA;
                    else                   proximo_estado = CALC_OCULTO;	// continua
                end
            end
            CALC_SAIDA: begin
                if (foi_ultimo_saida) proximo_estado = FIM;
            end
            FIM: begin
					// Estado transitório de 1 ciclo: pulsa 'pronto' e volta ao repouso
					proximo_estado = REPOUSO;
            end
            default: proximo_estado = REPOUSO;
        endcase
    end

	 // Lógica de saída (combinacional, baseada no estado atual)
    always @(*) begin
        calcular      = 1'b0;
        calcula_saida = 1'b0;
		  if (!rst_n) pronto        = 1'b0;
        case (estado)
            CALC_OCULTO: calcular      = 1'b1; // Habilita camada oculta
            CALC_SAIDA:  calcula_saida = 1'b1; // Habilita camada de saída
            FIM:         pronto        = 1'b1; // Sinaliza fim ao HPS e ao argmax
            default: ;
        endcase
    end

endmodule