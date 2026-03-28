module ondeamagicaacontece_ounao (
    input  wire        clk, rst_n, start,
    output [3:0]       saida
);
    wire wfim_camada;
    wire wfim_pixel;
    wire wativacao_valida;
    wire wcalcula;
    wire wcalcula_saida;
    wire [2:0]  westado;
    wire [9:0]  wx_addr;
    wire [16:0] ww_addr;
    wire        wdado_val;
    wire [15:0] wsomabruta;
    wire [15:0] wsaida_mac;
    wire [15:0] wscore;
    wire [6:0]  windice_classe;
    wire        wpronto;
    wire [15:0] wpixel_data;
    wire [15:0] wpeso_data;
    wire [15:0] wbias_data;
    wire [15:0] wativacao_data;
    wire [15:0] wbeta_data;
    wire [15:0] wpeso_final;
    wire        wativacao_wren;
    wire [6:0]  wativacao_waddr;
    wire [15:0] wativacao_dout;

    wire [6:0]  wbias_addr     = windice_classe;
    wire [6:0]  wneuronio_addr = windice_classe;

    wire [15:0] wentrada_mac = (westado == 3'd1) ? wpixel_data : wativacao_data;

    assign wsomabruta = (westado == 3'd1) ? wsaida_mac : 16'b0;
    assign wscore     = (westado == 3'd2) ? wsaida_mac : 16'b0;

    wire w_argmax_update_en = wativacao_valida && (westado == 3'd2);
    wire w_clear_argmax     = wfim_camada && (westado == 3'd1);

    assign wpeso_final    = (westado == 3'd2) ? wbeta_data : wpeso_data;
    assign wativacao_wren  = wativacao_valida && (westado == 3'd1);
    assign wativacao_waddr = windice_classe;

    fsm_elm fsm_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .ultimo_neuronio (wfim_camada),
        .ativacao        (wativacao_valida),
        .pronto          (wpronto),
        .calcular        (wcalcula),
        .calcula_saida   (wcalcula_saida),
        .estado          (westado)
    );

    contador_elm cont_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .calcular      (wcalcula),
        .calculo_saida (wcalcula_saida),
        .x_addr        (wx_addr),
        .w_addr        (ww_addr),
        .dado_valido   (wdado_val),
        .fim_neuronio  (wfim_pixel),
        .fim_camada    (wfim_camada),
        .neuronio      (windice_classe)
    );

    rom_beta beta_inst (
        .address (ww_addr[10:0]),
        .clock   (clk),
        .rden    (westado == 3'd2),
        .q       (wbeta_data)
    );

    rom_pesos rom_pesos_inst (
        .address (ww_addr),
        .clock   (clk),
        .rden    (1'b1),
        .q       (wpeso_data)
    );

    rom_bias bias_inst (
        .address (wbias_addr),
        .clock   (clk),
        .rden    (westado == 3'd1 ? 1'b1 : 1'b0),
        .q       (wbias_data)
    );

    ram_imagem imagem_inst (
        .address (wx_addr),
        .clock   (clk),
        .data    (16'b0),
        .rden    (1'b1),
        .wren    (1'b0),
        .q       (wpixel_data)
    );

    ram_neuronios_ativos neuronio_ram_inst (
        .address (westado == 3'd1 ? wativacao_waddr : wneuronio_addr),
        .clock   (clk),
        .data    (wativacao_dout),
        .rden    (westado == 3'd2),
        .wren    (wativacao_wren),
        .q       (wativacao_data)
    );

    ativacao_sigmoid sigmoid_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .d_in     (wsomabruta),
        .ativacao (wativacao_valida),
        .d_out    (wativacao_dout)
    );

    mac mac_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .dado_valido  (wdado_val),
        .fim_neuronio (wfim_pixel),
        .pixel        (wentrada_mac),
        .peso         (wpeso_final),
        .bias         (westado == 3'd1 ? wbias_data : 16'b0),
        .saida        (wsaida_mac),
        .saida_valida (wativacao_valida)
    );

    argmax argmax_inst (
        .clk         (clk),
        .rst_n       (rst_n),
        .pronto      (wpronto),
        .clear       (w_clear_argmax),
        .y_in        (wscore),
        .current_idx (windice_classe[3:0]),
        .update_en   (w_argmax_update_en),
        .saida       (saida)
    );

endmodule