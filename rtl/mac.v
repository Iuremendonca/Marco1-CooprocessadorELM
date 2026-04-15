module mac(
	 input wire clk,
    input wire rst_n,
    input wire dado_valido,   // Habilita leitura e acumulação no ciclo atual
    input wire fim_neuronio,  // Indica último pixel do neurônio: fecha o MAC
    input wire signed [15:0] valor, // Pixel normalizado em Q4.12
    input wire signed [15:0] peso,  // Peso do neurônio em Q4.12
    input wire signed [15:0] bias,  // Bias do neurônio em Q4.12
    output reg signed [15:0] saida, // Resultado final em Q4.12 (com clamp)
    output reg ativacao             // Pulso: saída válida por 1 ciclo
);

    // Acumulador com maior largura para evitar overflow durante somas
    reg signed [39:0] acumulador;
	 
	 // Variáveis intermediárias
    reg signed [39:0] v_soma_final; // Soma final antes do shift (acum + mult + bias)
    reg signed [39:0] resultado;    // Resultado após ajuste de ponto fixo (shift >>12)
    
    // Alinhamento do bias para o mesmo formato do acumulador (Q4.12 → extendido 40 bits)
    wire signed [39:0] bias_alinhado = {{12{bias[15]}}, bias, 12'd0};
    
    // Multiplicação atual: valor * peso → resultado em 32 bits (Q8.24)
    wire signed [31:0] mult_atual = valor * peso;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
				// Reset de todos os registradores
            acumulador           <= 40'd0;
            saida                <= 16'd0;
            ativacao             <= 1'b0;
            v_soma_final          = 40'd0;
            resultado  = 40'd0;
        end
        else begin
            if(dado_valido) begin
                if(fim_neuronio) begin
						  // --- Último pixel do neurônio: fecha o cálculo ---
                    // Soma acumulador + produto atual + bias alinhado
                    v_soma_final         = acumulador + mult_atual + bias_alinhado;
						  
						  // Shift aritmético de 12 bits para voltar ao formato Q4.12
                    resultado = v_soma_final >>> 12;

						  // Satura no range representável por 16 bits com sinal
                    // Evita overflow silencioso na truncagem para 16 bits
                    if (resultado > 40'sd32767) 		// Máximo positivo Q4.12
                        saida <= 16'h7FFF;
                    else if (resultado < -40'sd32768) // Mínimo negativo Q4.12
                        saida <= 16'h8000;
                    else
                        saida <= resultado[15:0];		// Valor dentro do range

                    ativacao     <= 1'b1;		// Sinaliza saída válida (pulso de 1 ciclo)
                    acumulador   <= 40'd0; 	// Reseta acumulador para próximo neurônio
                end
                else begin
						  // --- Pixels intermediários: apenas acumula o produto ---
                    acumulador <= acumulador + mult_atual;
                    ativacao   <= 1'b0;
                end
            end
        end
    end
endmodule