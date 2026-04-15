module ativacao_sigmoid (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] d_in,              // Entrada pré-ativação em Q4.12
    input  wire        ativacao,          // Pulso: d_in é válido para processar
    output wire signed [15:0] d_out,      // Saída pós-sigmoid em Q4.12
    output reg  [6:0]  addr_out           // Endereço sequencial para RAM de neurônios
);

	 // Constantes em Q4.12 (valor decimal * 4096)
    localparam V_0_5     = 16'h0800;  // 0.5       = 2048
    localparam V_0_625   = 16'h0a00;  // 0.625     = 2560
    localparam V_0859375 = 16'h0DC0;  // 0.859375  = 3520
    localparam V_1_0     = 16'h1000;  // 1.0       = 4096
	 
    // Limites de faixa em Q4.12
    localparam LIMIT_1_0 = 16'h1000;  // 1.0 em Q4.12
    localparam LIMIT_2_5 = 16'h2800;  // 2.5 em Q4.12
    localparam LIMIT_4_5 = 16'h4800;  // 4.5 em Q4.12

    reg signed [15:0] d_out_comb; // Resultado combinacional da sigmoid
    reg e_negativo;               // Flag: entrada é negativa
    reg [15:0] valor_absoluto;    // Valor absoluto da entrada (para lookup simétrico)

	 // Cálculo combinacional da sigmoid por partes
    always @(*) begin
        e_negativo     = d_in[15];	// Bit de sinal
        valor_absoluto = e_negativo ? (~d_in + 1'b1) : d_in; // |d_in|
		  
		  // Segmento padrão: saturação em 1.0
        d_out_comb = V_1_0;
		  
		  // Seleção do segmento linear baseado em |x|
        if      (valor_absoluto < LIMIT_1_0) d_out_comb = (valor_absoluto >> 2) + V_0_5;		// inclinação 0.25
        else if (valor_absoluto < LIMIT_2_5) d_out_comb = (valor_absoluto >> 3) + V_0_625;	// inclinação 0.125
        else if (valor_absoluto < LIMIT_4_5) d_out_comb = (valor_absoluto >> 5) + V_0859375; // inclinação 0.03125
        else                                 d_out_comb = V_1_0;
		  // Aplica simetria para entradas negativas: σ(-x) = 1 - σ(x)
        if (e_negativo) d_out_comb = V_1_0 - d_out_comb;
    end
	 
	 // d_out só é válido quando 'ativacao' está alto; caso contrário, zera a saída
    assign d_out = ativacao ? d_out_comb : 16'b0;

    // Contador de endereço para escrita sequencial na RAM de neurônios
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            addr_out <= 7'd0;
        else if (ativacao)
            addr_out <= addr_out + 7'd1;
    end

endmodule