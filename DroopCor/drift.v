////////////////////////////////////////////////////////////////
// Daria Pankova Tue Jul  7 13:54:54 EDT 2015
// drift.v
//
// "Drift correction of baseline"
// A custom Verilog HDL module.
// Keeps track of the Baseline
// 
////////////////////////////////////////////////////////////////

module drift
  (
   input 	 clk,
   input 	 rst_n,
   input 	 pause,
   input 	 rescale, 
   input [8:0] 	 rdaddr,
   input [13:0]  center_val,
   input [13:0]  adc,
   output [13:0] q_b   
   );
   
   wire 	 wren_a;
   wire 	 wren_b;
   
   reg signed [8:0]  dif;
   reg [13:0] 	     old_center_val;  
   reg [13:0] 	     data_a;
   reg [13:0] 	     data_b;
   reg [13:0] 	     data_out;
   wire [13:0] 	     q_a;
  // reg [13:0] 	     q_b;
   reg [13:0] 	     mem_a;
   reg [13:0] 	     mem_b; 	     
   reg [8:0] 	     addr_a;
   reg [8:0] 	     addr_b;
   reg [9:0] 	     counter;
   reg 		     first_a;
   reg 		     first_b;
   
   
  ram	ram_inst (
	.address_a ( addr_a ),
	.address_b ( addr_b ),
	.clock ( clk ),
	.data_a ( data_a ),
	.data_b ( data_b ),
	.wren_a ( wren_a ),
	.wren_b ( wren_b ),
	.q_a ( q_a ),
	.q_b ( q_b )
	);

   reg [2:0] fsm;
   localparam [2:0] S_INIT_RAM = 3'b0;
   localparam [2:0] S_RUN_1 = 3'b01;
   localparam [2:0] S_RUN_2 = 3'b10;
   localparam [2:0] S_PAUSE = 3'b100;
   localparam [2:0] S_RESCALE = 3'b101;
   localparam [13:0] scale_diff = 14'd8192;
   localparam [9:0] ramdep = 10'd512;
   localparam [13:0] maximum_ram = 14'b11111111111111;
   localparam dramdep = 512;
   localparam hramdep = 255;
   
   task difference_task;
      input [13:0] adc;
      input [13:0] center_val;
      output signed [8:0] difference;
      
      parameter hr = 255;
      reg signed [13:0]   diff14;
      
      begin
	 diff14 = adc-center_val; 
	 if (diff14 > hr) difference = hr+1;
	 else if (diff14 < -hr) difference = -hr;
	 else difference = diff14[8:0];
      end
   endtask
   
   // FSM
   always @(posedge clk or negedge rst_n)
     begin
	if (!rst_n) 
	  begin
	     fsm <= S_INIT_RAM;
	     counter <= 10'b0;
	  end
       else     
	 case (fsm)
	   S_INIT_RAM: 
	     begin
		if (counter == ramdep)
		  begin
		     fsm <= S_RUN_1;
		     counter <= 10'b0;
		     old_center_val <= center_val;
		     first_a <= 1'b0;
		     first_b <= 1'b0;		     
		  end
		else
		  begin
		     fsm <= S_INIT_RAM;
		     counter <= counter + 1'b1;
		     data_a <= 14'd0;
		     addr_a <= counter[8:0];
		  end
	     end // case: S_INIT_RAM
	   
	   S_RUN_1: 
	     begin
		if ((rescale) && (data_out == maximum_ram-1'b1))
		  begin
		     fsm <= S_RESCALE;
		     first_a <= 1'b0;
		  end
		else if (old_center_val != center_val)
		  begin
		     fsm <= S_INIT_RAM;
		     first_a <= 1'b0;
		  end
		else if (pause)
		  begin
		     fsm<= S_PAUSE;
		     first_a <= 1'b0;
		  end
		else
		     fsm <= S_RUN_2;
		
		if (first_a)
		  begin
		     data_b <= q_a + 1'b1;
		     addr_b <= mem_a;
		  end
		
		difference_task(adc, center_val,dif);
		addr_a <= hramdep + dif;
   		mem_a <= hramdep + dif;
		first_a <= 1'b1;
		
	     end // case: S_RUN
	 
	   S_RUN_2: 
	     begin
		if ((rescale) && (data_out == maximum_ram-1'b1))
		  begin
		     fsm <= S_RESCALE;
		     first_a <= 1'b0;
		  end
		else if (old_center_val != center_val)
		  begin
		     fsm <= S_INIT_RAM;
		     first_a <= 1'b0;
		  end
		else if (pause)
		  begin
		     fsm <= S_PAUSE;
		     first_a <= 1'b0;
		  end
		else
		     fsm <= S_RUN_1;
		
		if (first_b)
		  begin
		     data_b <= q_a + 1'b1;
		     addr_b <= mem_b;
		  end
		
		difference_task(adc, center_val, dif);
		addr_a <= hramdep + dif;
   		mem_b <= hramdep + dif;
		first_b <= 1'b1;
	
	     end // case: S_RUN_2
	   

	   S_RESCALE:
	     begin
		if (counter == ramdep)
		  begin
		     fsm <= S_RUN_1;
		     counter <= 10'b0;
		  end
		else
		  begin
		     fsm <= S_RESCALE;
		     counter <= counter + 1'b1;
		     if (counter > 1'b1)
		       begin
			  data_out <= q_a;
			  if (data_out > scale_diff) 
			    data_b <= data_out - scale_diff;
			  else data_b <= 14'b0;
			  addr_b <= counter-2'b10;
		       end
		     addr_a <= counter[8:0];
		  end
	     end // case: S_RESCALE
	     
	   S_PAUSE:
	     begin
	        if (pause)
		begin
		   fsm <= S_PAUSE;
		   addr_b <= rdaddr;
		end
		else
		  fsm <= S_RUN_1;	
	     end // case: S_PAUSE
	   
	   default: fsm <= 2'bxx;
	   
	 endcase // case (fsm)
     end

   // Combinational outputs
   assign wren_a = (fsm == S_INIT_RAM);
   assign wren_b = (fsm == S_RUN_1) || (fsm == S_RUN_2) || (fsm == S_RESCALE);
   
   
endmodule
