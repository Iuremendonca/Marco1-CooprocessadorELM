module ativacao_sigmoid (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] d_in,
    input  wire        ativacao,
    output wire signed [15:0] d_out
);
    localparam V_0_5     = 16'h0800;
    localparam V_0_625   = 16'h0a00;
    localparam V_0859375 = 16'h0DC0;
    localparam V_1_0     = 16'h1000;
    localparam LIMIT_1_0 = 16'h1000;
    localparam LIMIT_2_5 = 16'h2800;
    localparam LIMIT_4_5 = 16'h4800;

    reg signed [15:0] d_out_comb;
    reg e_negativo;
    reg [15:0] valor_absoluto;

    always @(*) begin
        e_negativo     = d_in[15];
        valor_absoluto = e_negativo ? (~d_in + 1'b1) : d_in;

        d_out_comb = V_1_0;
        if      (valor_absoluto < LIMIT_1_0) d_out_comb = (valor_absoluto >> 2) + V_0_5;
        else if (valor_absoluto < LIMIT_2_5) d_out_comb = (valor_absoluto >> 3) + V_0_625;
        else if (valor_absoluto < LIMIT_4_5) d_out_comb = (valor_absoluto >> 5) + V_0859375;
        else                                 d_out_comb = V_1_0;

        if (e_negativo) d_out_comb = V_1_0 - d_out_comb;
    end

    assign d_out = ativacao ? d_out_comb : 16'b0;

endmodule