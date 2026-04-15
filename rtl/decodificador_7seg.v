module decodificador_7seg(
	input [3:0] in, 
	input sinal,
	output reg [6:0] seg_out);

	always@(*)begin
		if(sinal) begin
			case(in)
			4'h0: seg_out = 7'b1000000; 
         4'h1: seg_out = 7'b1111001; 
         4'h2: seg_out = 7'b0100100; 
         4'h3: seg_out = 7'b0110000; 
         4'h4: seg_out = 7'b0011001; 
         4'h5: seg_out = 7'b0010010; 
         4'h6: seg_out = 7'b0000010; 
         4'h7: seg_out = 7'b1111000; 
         4'h8: seg_out = 7'b0000000; 
         4'h9: seg_out = 7'b0010000;
			default: seg_out = 7'b1111111;
			endcase
		end else begin
			case(in)
			// in = {0, error, done, busy}
			4'b0000: seg_out = 7'b0110000; //I - Espera
			4'b0001: seg_out = 7'b0000011; //b - Busy
			4'b0010: seg_out = 7'b0100001; //d - Done
			4'b0100: seg_out = 7'b0000110; //E - Error
			4'b0110: seg_out = 7'b0000110; //E - Error
			default: seg_out = 7'b1111111;
			endcase
		end
	end
endmodule
