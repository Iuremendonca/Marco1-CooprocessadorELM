module argmax (
    input clk,
    input rst_n,
    input clear,            // Sinal para resetar antes de começar as 10 classes
    input signed [15:0] y_in, // O score da classe atual vindo do MAC
    input [3:0] current_idx, // O índice da classe atual (0 a 9)
    input update_en,        // Pulso que avisa que um novo score está pronto
    output reg [3:0] final_digit // O dígito vencedor (vai para a sua ISA)
);

    reg signed [15:0] max_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_val <= 16'h8000; // Menor valor possível (signed)
            final_digit <= 4'd0;
        end else if (clear) begin
            max_val <= 16'h8000;
            final_digit <= 4'd0;
        end else if (update_en) begin
            // Comparação Assinalada (Signed)
            if (y_in > max_val) begin
                max_val <= y_in;
                final_digit <= current_idx;
            end
        end
    end
endmodule