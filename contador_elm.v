module contador_elm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        calcular,
    input  wire        calculo_saida,
    output reg  [9:0]  x_addr,
    output reg  [16:0] w_addr,
    output reg         dado_valido,
    output wire        fim_neuronio,   // ← wire agora
    output wire        fim_camada,     // ← wire agora
    output reg  [6:0]  neuronio
);
    reg [9:0]  cont_pi;
    reg [6:0]  cont_neu;
    reg [16:0] endereco;

    wire ativo     = calcular || calculo_saida;
    wire [9:0] max_pi  = calcular ? 10'd783 : 10'd127;
    wire [6:0] max_neu = calcular ? 7'd127  : 7'd9;

    wire ultimo_pi  = (cont_pi  == max_pi);
    wire ultimo_neu = (cont_neu == max_neu);

    // combinacional — chegam no mesmo ciclo do último dado
    assign fim_neuronio = ativo && ultimo_pi;
    assign fim_camada   = ativo && ultimo_pi && ultimo_neu;

    wire [9:0]  prox_pi  = ultimo_pi  ? 10'd0 : cont_pi  + 10'd1;
    wire [6:0]  prox_neu = ultimo_neu ? 7'd0  : cont_neu + 7'd1;
    wire [16:0] prox_end = endereco + 17'd1;

    always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cont_pi     <= 10'd0;
        cont_neu    <= 7'd0;
        endereco    <= 17'd0;
        dado_valido <= 1'b0;
        x_addr      <= 10'd0;
        w_addr      <= 17'd0;
        neuronio    <= 7'd0;
    end
    else if (ativo) begin
        x_addr      <= cont_pi;
        w_addr      <= endereco;
        neuronio    <= cont_neu;
        dado_valido <= 1'b1;

        if (ultimo_pi) begin
            cont_pi  <= 10'd0;
            cont_neu <= ultimo_neu ? 7'd0 : prox_neu;

            if (ultimo_neu && calcular)
                endereco <= 17'd0;
            else
                endereco <= prox_end;
        end
        else begin
            cont_pi  <= prox_pi;
            endereco <= prox_end;  // só aqui
        end
    end
    else begin
        dado_valido <= 1'b0;
        endereco    <= 17'd0;
    end
end
endmodule