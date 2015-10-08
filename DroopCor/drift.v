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
   input 	 clk, // clock
   input 	 rst_n, // reset
   input 	 pause, // pause histogramm data taking and processor read out
   input 	 rescale, // enable rescaling if histogramm is full
   input [4:0] 	 rdaddr, // readout adress
   input [13:0]  center_val, // input histogram central value
   input [13:0]  adc, // data input from ADC
   output [19:0] q_a, // readout data
   output 	 filled // RAM is full flag
   );
   
   // variables
   reg 		 wren_a; // write enable chanel A
   wire 	 wren_b; // write enable chanel B
   reg [13:0] 	     old_center_val;  // to keep track if central value has changed
   reg [19:0] 	     data_a; // port A data
   reg [19:0] 	     data_b; // port B data
   reg [19:0] 	     count_in; //counter for repeated address hits
   reg [19:0] 	     pipe_count; //pipeline  counter 
   wire [19:0] 	     q_b;   // RAM output B
   reg [4:0] 	     addr_a; // RAM address input port A
   reg [4:0] 	     addr_b; // RAM address input port B
   reg [4:0] 	     addr; // first pipeline stage, address calculated from ADC
   reg [4:0] 	     addr_1; // second pipeline stage
   reg [4:0] 	     addr_2; // third pipeline stage
   reg [4:0] 	     addr_3; // forth pipeline stage
   reg [4:0] 	     addr_mem_1; // variable for remembering the repeated address
   reg [4:0] 	     addr_mem_2;
   reg [4:0] 	     addr_mem_3;
   reg [4:0] 	     addr_mem_4;
   reg [4:0] 	     addr_mem_5;
   reg [4:0] 	     addr_mem_6;
   reg [5:0] 	     counter; // state machine counter
   reg 		     remove_1; // varible is high if repeated address needs to be removed
   reg 		     remove_2;
   reg 		     remove_3;
   reg 		     remove_4;
   reg 		     remove_5;
   reg 		     remove_6;

  // RAM initialization (two port)
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

   // RAM parameters
   localparam L_RAM_DEPTH = 1048576; // Depth of the RAM (max count in a bin)
   localparam L_HALF_RAM_DEPTH = L_RAM_DEPTH/2; // Half depth
   localparam L_RAM_SIZE = 32; // Size of the RAM (number of addresses)
   localparam L_HALF_RAM_SIZE = L_RAM_SIZE/2-1; // Half size
  
   // State machine parametrs 
   reg [3:0] fsm; // state variable
   localparam [3:0] S_INIT_RAM = 4'b0001; // state: initialize RAM
   localparam [3:0] S_RUN = 4'b0010; // state: normal running (pipeline)
   localparam [3:0] S_PAUSE = 4'b0100; // state: pause data taking and read out
   localparam [3:0] S_RESCALE = 4'b1000; // state: rescaling if RAM is full

   // Bin finding function parametrs
   wire signed [14:0] diff14;
   reg signed [5:0]  diff;
   
   // Bin address finding function. 0 and 31 are overflow bins 
   assign diff14 = adc-center_val; 
   always @(diff14)
     begin
	if (diff14 > L_HALF_RAM_SIZE) diff =  L_HALF_RAM_SIZE+1;
	else if (diff14 < - L_HALF_RAM_SIZE) diff = - L_HALF_RAM_SIZE;
	else
	  begin
	     diff = diff14[5:0];
	  end
	addr =  L_HALF_RAM_SIZE + diff;
     end
  
   // FSM
   always @(posedge clk or negedge rst_n)
     begin
	if (!rst_n) // Pulse reset
	  begin
	     fsm <= S_INIT_RAM;
	     counter <= 6'b0;
	  end
       else     
	 case (fsm)
	   S_INIT_RAM: // initialization
	     begin
		if (counter == L_RAM_SIZE) // if the final RAM bin is reached intialize counters
		  begin // and go to RUN state
		     fsm <= S_RUN;
		     counter <= 6'b0;
		     old_center_val <= center_val; // remember the central value
		     pipe_count <= 1'b0;
		     wren_a <= 1'b0;
		  end
		else
		  begin // write zero into every bin 
		     wren_a <= 1'b1;
		     fsm <= S_INIT_RAM;
		     counter <= counter + 1'b1;
		     data_a <= 14'd0;
		     addr_a <= counter[4:0];
		  end
	     end // case: S_INIT_RAM
	   
	   S_RUN: //normal running sate
	     begin
		if ((rescale) && (q_b == L_RAM_DEPTH-1)) // RAM is full - rescale
		  fsm <= S_RESCALE;
		else if (old_center_val != center_val) // New central value - inititialize
		  fsm <= S_INIT_RAM;
		else if (pause) // Pause signal 
		  fsm<= S_PAUSE;
		else
		  fsm <= S_RUN;
		
		//PIPELINE START
		pipe_count <= pipe_count + 1'b1; //pipeline counter
		addr_3 <= addr_2;
		addr_2 <= addr_1;
		addr_1 <= addr;
		addr_b <= addr;
		
		if (pipe_count > 2'd2) // if pipeline is filled 
		  begin	  
		     if ((addr_3 == addr_mem_1) && (remove_1 == 1'b1)) // skip the repeat address
		       begin // addr_mem_n contain address that will be repeated 
			  wren_a <= 1'b0; // remove_n is a flag.
			  remove_1 <= 1'b0; // high if adress has not been removed yet 
		       end
		     else if ((addr_3 == addr_mem_2) && (remove_2 == 1'b1))
		       begin
			  wren_a <= 1'b0;
			  remove_2 <= 1'b0;
		       end
		     else if ((addr_3 == addr_mem_3) && (remove_3 == 1'b1))
		       begin
			  wren_a <= 1'b0;
			  remove_3 <= 1'b0;
		       end
		     else if ((addr_3 == addr_mem_4) && (remove_4 == 1'b1))
		       begin
			  wren_a <= 1'b0;
			  remove_4 <= 1'b0;
			 end
		     else if ((addr_3 == addr_mem_5) && (remove_5 == 1'b1))
		       begin
			  wren_a <= 1'b0;
			  remove_5 <= 1'b0;
		       end
		     else if ((addr_3 == addr_mem_6) && (remove_6 == 1'b1))
		       begin
			  wren_a <= 1'b0;
			  remove_6 <= 1'b0;
		       end
		     else if ((addr_3 == addr_2) &&  (count_in != 20'd524288)) // if two sequential 
		       begin // addresses are the same increase count_in by 1 and write nothing
			  wren_a <= 1'b0; // unless count in is 524288, then write it
			  count_in <= count_in + 1'b1;
		       end
		     else if ((addr_3 == addr_1) && (addr_3 == addr)) // 1011 case of repeats
		       begin
			  wren_a <= 1'b1;
			  data_a <= q_b + 2'd3 + count_in; // write 3 + count_in
			  addr_a <= addr_3;
			  count_in <= 20'b0;
			  remove_6 <= 1'b1; // remove 1st repeat
			  addr_mem_6 <= addr_3;  // remove 1st repeat
			  remove_2 <= 1'b1; // remove 2nd repeat
			  addr_mem_2 <= addr_3; // remove 2nd repeat
		       end
		     else if ((addr_3 == addr_2) && (addr_3 == addr)) // 1101 case of repeats
		       begin
			  wren_a <= 1'b1;
			  data_a <= q_b + 2'd3 + count_in;
			  addr_a <= addr_3;
			  count_in <= 20'b0;
			  remove_5 <= 1'b1;
			  addr_mem_5 <= addr_3;
			  remove_2 <= 1'b1;
			  addr_mem_2 <= addr_3;
		       end
		     else if ((addr_3 == addr_1) && (remove_1 == 1'b1)) // 0101 repeat 
		       begin
			  wren_a <= 1'b1;
			  data_a <= q_b + 2'b10 + count_in;  // write 2 + count_in
			  addr_a <= addr_3;
			  count_in <= 20'b0;
			  remove_2 <= 1'b1; // remove the repeat
			  addr_mem_2 <= addr_3; // remove the repeat 
		       end
		     else if (addr_3 == addr_1) // 1010 repeat
		       begin
			  wren_a <= 1'b1;
			  data_a <= q_b + 2'b10 + count_in;
			  addr_a <= addr_3;
			  count_in <= 20'b0;
			  remove_1 <= 1'b1;
			  addr_mem_1 <= addr_3;
		       end
		     else if ((addr_3 == addr) && (remove_4 == 1'b1)) //001001 repeat
		       begin
			  wren_a <= 1'b1;
			  data_a <= q_b + 2'b10 + count_in;
			  addr_a <= addr_3;
			  count_in <= 20'b0;
			  remove_5 <= 1'b1;
			  addr_mem_5 <= addr_3;
		       end
		     else if ((addr_3 == addr)  && (remove_3 == 1'b1)) // 010010 repeat
		       begin
			  wren_a <= 1'b1;
			  data_a <= q_b + 2'b10 + count_in;
			  addr_a <= addr_3;
			  count_in <= 20'b0;
			  remove_4 <= 1'b1;
			  addr_mem_4 <= addr_3;
		       end
		     else if (addr_3 == addr) //100100 repeat 
		       begin
			  wren_a <= 1'b1;
			  data_a <= q_b + 2'b10 + count_in;
			  addr_a <= addr_3;
			  count_in <= 20'b0;
			  remove_3 <= 1'b1;
			  addr_mem_3 <= addr_3;
		       end	   
		     else 
		       begin // no repeats
			  wren_a <= 1'b1;
			  data_a <= q_b + 1'b1 + count_in; //write 1 +count_in
			  addr_a <= addr_3; // to this address
			  count_in <= 20'b0;
		       end
		    
		     
		  end // if (pipe_count > 2'd2)
		else if (pipe_count == 1'b1) // while pipeline is not full yet initialize vars
		  begin
		     count_in <= 20'b0;
		     remove_1 <= 1'b0;
		     remove_2 <= 1'b0;
		     remove_3 <= 1'b0;
		     remove_4 <= 1'b0;
		     remove_5 <= 1'b0;
		  end
	     end // case: S_RUN PIPELINE END
	 
	   S_RESCALE:
	     begin
		if (counter == L_RAM_SIZE) //if reached the final bin, initialize and run  
		  begin
		     fsm <= S_RUN;
		     counter <= 6'b0;
		     pipe_count <= 20'b0;	     
		  end
		else
		  begin
		     fsm <= S_RESCALE;
		     counter <= counter + 1'b1;
		     if (counter > 1'b1) 
		       begin
			  if (q_b > L_HALF_RAM_DEPTH) //if bin is more than half full
			    data_a <= q_b - L_HALF_RAM_DEPTH; // remove the half of ram max size
			  else 
			    data_a <= 20'b0; // else set it to zero
			  addr_a <= counter-2'b10; // write to address what was 2 counts ago
		       end
		     addr_b <= counter[4:0];
		  end
	     end // case: S_RESCALE
	     
	   S_PAUSE:
	     begin
	        if (pause)
		begin
		   fsm <= S_PAUSE;
		   addr_a <= rdaddr;
		   wren_a <= 1'b0;
		end
		else 
		  fsm <= S_RUN;	
	     end // case: S_PAUSE
	   
	   default: fsm <= 4'b0100;
	   
	 endcase // case (fsm)
     end

   // Combinational outputs
   assign wren_b = 1'b0; // never write to port B
   assign filled = ((!rescale) && (q_b == L_RAM_DEPTH-1)); //RAM is full (no rescale)
   
     
endmodule
