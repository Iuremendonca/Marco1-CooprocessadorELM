module fsm_elm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        ultimo_neuronio,
    input  wire        ativacao,
    output reg         pronto,
    output reg         calcular,
    output reg         calcula_saida,
    output reg  [2:0]  estado
);
    localparam REPOUSO     = 3'd0,
               CALC_OCULTO = 3'd1,
               CALC_SAIDA  = 3'd2,
               ESPERA      = 3'd3, // <-- Estado de espera adicionado
               FIM         = 3'd4;

    reg [2:0] proximo_estado;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) estado <= REPOUSO;
        else        estado <= proximo_estado;
    end

    reg foi_ultimo;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            foi_ultimo <= 1'b0;
        else if (ultimo_neuronio && (estado == CALC_OCULTO))
            foi_ultimo <= 1'b1;
        else if (estado == CALC_SAIDA)
            foi_ultimo <= 1'b0;
    end

    always @(*) begin
        proximo_estado = estado;
        case (estado)
            REPOUSO: begin
                if (start) proximo_estado = CALC_OCULTO;
            end
            CALC_OCULTO: begin
                if (ativacao) begin
                    if (foi_ultimo) proximo_estado = CALC_SAIDA;
                    else            proximo_estado = CALC_OCULTO;
                end
            end
            CALC_SAIDA: begin
                if (ultimo_neuronio) proximo_estado = ESPERA; // Vai para espera
            end
            ESPERA: begin
                proximo_estado = FIM; // Espera 1 clock e vai para FIM
            end
            FIM: begin
                proximo_estado = REPOUSO;
            end
            default: proximo_estado = REPOUSO;
        endcase
    end

    always @(*) begin
        calcular      = 1'b0;
        calcula_saida = 1'b0;
        pronto        = 1'b0;
        case (estado)
            CALC_OCULTO: calcular      = 1'b1;
            CALC_SAIDA:  calcula_saida = 1'b1;
            FIM:         pronto        = 1'b1; // Pronto sobe após a espera
            default: ;
        endcase
    end
endmodule