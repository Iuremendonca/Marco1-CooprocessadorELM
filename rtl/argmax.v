module argmax (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pronto,      // Indica fim de inferência → captura resultado
    input  wire        clear,       // Reinicia busca (início de nova inferência)
    input  wire signed [15:0] y_in, // Valor de saída de uma classe (Q4.12)
    input  wire        update_en,   // Pulso: y_in é válido e deve ser comparado
    output reg  [3:0]  saida        // Índice da classe com maior valor (0..9)
);

    reg signed [15:0] max_val;    // Maior valor encontrado até o momento
    reg [3:0]         final_digit; // Índice correspondente ao maior valor
    reg [3:0]         current_idx; // Contador interno: classe sendo avaliada (0..9)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
				// Inicializa max_val com o menor valor possível (16'h8000 = -32768)
            max_val     <= 16'h8000;
            final_digit <= 4'd0;
            saida       <= 4'd0;
            current_idx <= 4'd0;
        end
        else if (clear) begin
				// Reinicia estado para nova inferência sem apagar 'saida' anterior
            max_val     <= 16'h8000;
            final_digit <= 4'd0;
            current_idx <= 4'd0;
        end
        else begin
            if (update_en) begin
					 // Compara saída atual com o máximo registrado
                if (y_in > max_val) begin
                    max_val     <= y_in;			// Atualiza máximo
                    final_digit <= current_idx;	// Guarda índice do novo máximo
                end
                current_idx <= current_idx + 4'd1;	// Avança para próxima classe
            end
            else if (pronto) begin
					 // Fim da inferência: publica o índice vencedor
                saida <= final_digit;
            end
        end
    end

endmodule