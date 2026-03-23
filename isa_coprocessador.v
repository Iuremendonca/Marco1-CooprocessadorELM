module isa_coprocessador (
    input clk,
    input rst,
    
    // Interface com o HPS (ARM)
    input  [31:0] instrucao,
    input         hps_write,
    output [31:0] hps_readdata,
    
    // Interface com a FSM
    input         fsm_busy,
    input         fsm_done,
    input         fsm_error,
    input  [3:0]  elm_result,
    output reg    start_pulse,
    
    // Interface com Memórias
    output reg [16:0] w_addr,
    output reg [9:0]  img_addr,
    output reg [6:0]  bias_addr,
    output reg [10:0] beta_addr,
    output reg signed [15:0] data_to_mem,
    output reg wren_w, wren_img, wren_bias, wren_beta
);

    // =========================
    // Parâmetros do sistema
    // =========================
    parameter MAX_W    = 17'd100352;

    // =========================
    // Decodificação da instrução
    // =========================
    wire [3:0]  opcode  = instrucao[31:28];
    wire [11:0] addr_in = instrucao[27:16];
    wire [15:0] data_in = instrucao[15:0];

    // =========================
    // Contadores internos
    // =========================
    reg [16:0] count_w;

    // =========================
    // Lógica principal
    // =========================
    always @(posedge clk) begin
        if (rst) begin
            // Reset geral
            count_w        <= 0;
            
            w_addr     <= 0;
            img_addr   <= 0;
            bias_addr  <= 0;
            beta_addr  <= 0;
            
            data_to_mem    <= 0;
            
            {wren_w, wren_img, wren_bias, wren_beta, start_pulse} <= 5'b0;
        end else begin
            // Pulsos duram apenas 1 ciclo
            {wren_w, wren_img, wren_bias, wren_beta, start_pulse} <= 5'b0;

            if (hps_write) begin
                case (opcode)

                    // =========================
                    // STORE IMG (endereço direto)
                    // =========================
                    4'h1: begin
                        img_addr <= addr_in[9:0];
                        data_to_mem  <= data_in;
                        wren_img     <= 1'b1;
                    end

                    // =========================
                    // STORE W (auto-incremento)
                    // =========================
                    4'h2: begin
                        if (count_w < MAX_W) begin
                            w_addr  <= count_w;
                            data_to_mem <= data_in;
                            wren_w      <= 1'b1;
                            count_w     <= count_w + 1;
                        end
                    end

                    // =========================
                    // STORE B (endereço direto)
                    // =========================
                    4'h3: begin
                        bias_addr <= addr_in[6:0];
                        data_to_mem   <= data_in;
                        wren_bias     <= 1'b1;
                    end

                    // =========================
                    // STORE BETA (endereço direto)
                    // =========================
                    4'h4: begin
								 beta_addr <= addr_in[10:0];
								 data_to_mem   <= data_in;
								 wren_beta     <= 1'b1;
                    end

                    // =========================
                    // START (somente se não estiver ocupado)
                    // =========================
                    4'h5: begin
                        if (!fsm_busy)
                            start_pulse <= 1'b1;
                    end

                    // =========================
                    // RESET DOS CONTADORES
                    // =========================
                    4'h7: begin
                        count_w    <= 0;
                    end

                    // =========================
                    // DEFAULT
                    // =========================
                    default: begin
                        // nenhuma ação
                    end

                endcase
            end
        end
    end

    // =========================
    // STATUS (leitura pelo HPS)
    // =========================
    // [0] busy
    // [1] done
    // [2] error
    // [7:4] resultado (dígito)
    assign hps_readdata = {
        24'b0,
        elm_result,
        1'b0,
        fsm_error,
        fsm_done,
        fsm_busy
    };

endmodule