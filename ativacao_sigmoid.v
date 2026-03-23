module ativacao_sigmoid (input wire [15:0] d_in, output reg signed [15:0] d_out);

//0,25x+0,5, 0<=x<1
//0,125x+0,625 1<=x<2,5
//0,03125x+0,859375, 2,5<=x<4,5
//1, x>= 4,5

localparam V_0_5 = 16'h0800;
localparam V_0_625 =16'h0a00;
localparam V_0859375 = 16'h0DC0;
localparam V_1_0 = 16'h1000;

localparam LIMIT_1_0   = 16'h1000; 
localparam LIMIT_2_5   = 16'h2800; 
localparam LIMIT_4_5   = 16'h4800;

reg e_negativo; 
reg [15:0] valor_absoluto;

always@(*)begin

	e_negativo = d_in[15];
	valor_absoluto = e_negativo ? (~d_in + 1'b1) : d_in;
	
	if (valor_absoluto<LIMIT_1_0) begin
		//0,25 = 1/2^2
		d_out = (valor_absoluto>>2) + V_0_5;
	end
	
	else if(valor_absoluto< LIMIT_2_5) begin
		//0,125 = 1/2^3
		d_out = (valor_absoluto >> 3) + V_0_625;
	end

	else if(valor_absoluto<LIMIT_4_5)	begin
		//0,03125 = 1/2^5
		d_out = (valor_absoluto >> 5) + V_0859375;
	end
	
	else begin
		//x>=4,5
		d_out = V_1_0;
	end
	
	if(e_negativo)begin
		d_out = V_1_0 - d_out;
		
	end

end

endmodule
