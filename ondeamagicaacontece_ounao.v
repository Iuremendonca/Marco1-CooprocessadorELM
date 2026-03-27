module ondeamagicaacontece_ounao (
    input  wire        clk, rst_n,
    // --- INTERFACE COM O HPS (ARM) ---
    input  wire [31:0] instrucao,
    input  wire        hps_write,
    output wire [31:0] hps_readdata,
    // ---------------------------------
    input  [2:0]       estado, // Mantido conforme original
    output [3:0]       saida 
);

    // --- FIOS PARA CONEXÃO INTERNA DA ISA ---
    wire        w_start_pulse;
    wire [16:0] w_load_w_addr;
    wire [9:0]  w_load_img_addr;
    wire [6:0]  w_load_bias_addr;
    wire [10:0] w_load_beta_addr;
    wire [15:0] w_load_data;
    wire        w_wren_w, w_wren_img, w_wren_bias, w_wren_beta;
    wire        w_busy = (westado != 3'd0); // Status de ocupado

    // ============================================================
    // INSTÂNCIA DA ISA
    // ============================================================
    isa_coprocessador isa_inst (
        .clk          (clk),
        .rst          (~rst_n),
        .instrucao    (instrucao),
        .hps_write    (hps_write),
        .hps_readdata (hps_readdata),
        .fsm_busy     (w_busy),
        .fsm_done     (wpronto),
        .fsm_error    (1'b0),
        .elm_result   (saida),
        .start_pulse  (w_start_pulse),
        .w_addr       (w_load_w_addr),
        .img_addr     (w_load_img_addr),
        .bias_addr    (w_load_bias_addr),
        .beta_addr    (w_load_beta_addr),
        .data_to_mem  (w_load_data),
        .wren_w       (w_wren_w),
        .wren_img     (w_wren_img),
        .wren_bias    (w_wren_bias),
        .wren_beta    (w_wren_beta)
    );

    // --- DECLARAÇÕES DE FIOS ---
    wire wfim_camada;
    wire wfim_pixel;
    wire wativacao_valida;
    wire wativacao_concluida;
    wire wcalcula;
    wire wcalcula_saida;
    wire [2:0]  westado;
    wire [9:0]  wpixel;
    wire [16:0] wpeso;
    wire        wdado_val;
    wire [15:0] wsomabruta;
    wire [15:0] wsaida_mac;
    wire [15:0] wscore;
    wire [6:0]  windice_classe;
    wire        wpronto;
    
    // endereços vindos do contador
    wire [9:0]  wx_addr;   // endereço da imagem  
    wire [16:0] ww_addr;   // endereço dos pesos 

    // dados lidos das memórias
    wire [15:0] wpixel_data;   // imagem - mac
    wire [15:0] wpeso_data;    // rom_pesos - mac
    wire [15:0] wbias_data;    // bias - mac
    wire [15:0] wativacao_data;// neurônios ativos - mac (camada de saída)

    // Nova fiação para os pesos
    wire [15:0] wbeta_data;
    wire [15:0] wpeso_final;

    // RAM Neurônios Ativos  (escrita pela ativação, leitura pelo mac)
    wire wativacao_wren;                     // escrita quando ativação conclui
    wire [6:0] wativacao_waddr;              // endereço de escrita = neurônio que acabou
    wire [15:0] wativacao_dout;              // dado saindo do bloco de ativação

    // --- ATRIBUIÇÕES (LOGICA COMBINACIONAL) ---
    // endereço de bias: índice do neurônio atual
    wire [6:0]  wbias_addr    = windice_classe;          
    wire [6:0]  wneuronio_addr = windice_classe;
     
    // dado que entra no mac:
    wire [15:0] wentrada_mac = (westado == 3'd1) ? wpixel_data : wativacao_data;
     
    // mux saída do mac
    assign wsomabruta = (westado == 3'd1) ? wsaida_mac : 16'b0;
    assign wscore     = (westado == 3'd3) ? wsaida_mac : 16'b0;

    // update_en e clear do argmax
    wire w_argmax_update_en = wativacao_valida && (westado == 3'd3);
    wire w_clear_argmax     = (wfim_camada    && (westado == 3'd1));

    // MUX para decidir qual peso o MAC vai usar
    assign wpeso_final = (westado == 3'd3) ? wbeta_data : wpeso_data;

    assign wativacao_wren  = wativacao_concluida && (westado == 3'd1);
    assign wativacao_waddr = windice_classe;

    // --- INSTANCIAÇÕES ---

    // Instância da nova ROM (RAM 2-Port corrigida)
    ram_beta beta_inst (
        .clock     (clk),
        .data      (w_load_data),      // Lado Escrita (ISA)
        .wraddress (w_load_beta_addr), // Lado Escrita (ISA)
        .wren      (w_wren_beta),      // Lado Escrita (ISA)
        .rdaddress (ww_addr[10:0]),    // Lado Leitura (FSM)
        .rden      (westado == 3'd3),  // Lado Leitura (FSM)
        .q         (wbeta_data)        // Lado Leitura (FSM)
    );

    // FSM
    fsm_elm fsm_inst (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (w_start_pulse), 
        .ultimo_neuronio    (wfim_camada),
        .ativacao           (wativacao_valida),
        .ativacao_concluida (wativacao_concluida),
        .pronto             (wpronto),
        .calcular           (wcalcula),
        .calcula_saida      (wcalcula_saida),
        .estado             (westado)
    );

    // Contador
    contador_elm cont_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .calcular      (wcalcula),
        .calculo_saida (wcalcula_saida),
        .x_addr        (wx_addr),       //  ram imagem
        .w_addr        (ww_addr),       //  rom pesos
        .dado_valido   (wdado_val),
        .fim_neuronio  (wfim_pixel),
        .fim_camada    (wfim_camada),
        .neuronio      (windice_classe)
    );

    // ROM Pesos (RAM 2-Port corrigida)
    ram_pesos weights_inst (
        .clock     (clk),
        .data      (w_load_data),      // Lado Escrita (ISA)
        .wraddress (w_load_w_addr),    // Lado Escrita (ISA)
        .wren      (w_wren_w),         // Lado Escrita (ISA)
        .rdaddress (ww_addr),          // Lado Leitura (FSM)
        .rden      (1'b1),             // Lado Leitura (Sempre lendo)
        .q         (wpeso_data)       // Lado Leitura (FSM)
    );

    // ROM Bias (RAM 2-Port corrigida)
    ram_bias bias_inst (
        .clock     (clk),
        .data      (w_load_data),      // Lado Escrita (ISA)
        .wraddress (w_load_bias_addr), // Lado Escrita (ISA)
        .wren      (w_wren_bias),      // Lado Escrita (ISA)
        .rdaddress (wbias_addr),       // Lado Leitura (FSM)
        .rden      (westado == 3'd1),  // Lado Leitura (FSM)
        .q         (wbias_data)        // Lado Leitura (FSM)
    );

    // RAM Imagem (RAM 2-Port corrigida)
    ram_imagem imagem_inst (
        .clock     (clk),
        .data      (w_load_data),      // Lado Escrita (ISA)
        .wraddress (w_load_img_addr),  // Lado Escrita (ISA)
        .wren      (w_wren_img),       // Lado Escrita (ISA)
        .rdaddress (wx_addr),          // Lado Leitura (FSM)
        .rden      (1'b1),             // Lado Leitura (Sempre lendo)
        .q         (wpixel_data)       // Lado Leitura (FSM)
    );

    // RAM de Neurônios Ativos (Mantida conforme sua lógica de Single-Port/Pseudo Dual)
    // Se esta memória também for Dual-Port do IP Catalog, use o padrão acima.
    ram_neuronios_ativos neuronio_ram_inst (
        .clock   (clk),
        .data    (wativacao_dout),  
		  .wraddress (wativacao_waddr), // escrita: índice do neurônio oculto
        .wren    (wativacao_wren),  
		  .rdaddress (wneuronio_addr), // leitura: índice do neurônio de saída
		  .rden    (westado == 3'd3),
        .q       (wativacao_data)   
    );

    // Ativação Sigmoid
    ativacao_sigmoid sigmoid_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .d_in               (wsomabruta),
        .ativacao           (wativacao_valida),
        .d_out              (wativacao_dout),       
        .ativacao_concluida (wativacao_concluida)
    );

    // MAC atualizado
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

    // Argmax
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
