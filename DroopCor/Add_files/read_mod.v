//////////////////////////////////////////////////////////////////////////////////////
// Daria Pankova Wed Nov 18 16:28:00 EST 2015
// Read out Module for baseline drift correction simulation
// (Pulse one clock cycle when a positive edge is detected and
// after signal go to move throu all the adresses)
//////////////////////////////////////////////////////////////////////////////////////
module read_mod
  (
   input 	clk, // clock
   input 	rst_n, // active low reset
   input 	KEY, // input on which positive edges should be detected
   output [4:0] addr	
   );
   
   localparam L_RAM_SIZE = 32; // Size of the RAM (number of addresses)
   reg 		ff;
   reg [4:0] 	counter;
   reg 		flag;
   reg 		addr_reg;
   wire 	y;
   
   always @(posedge clk or negedge rst_n)
     begin
	if ( !rst_n ) 
	  begin
	     ff <= 1'b0;
	     flag <= 1'b0;
	     counter <= 5'b0;
	  end
	else 
	  begin
	     ff <= ~KEY;
	     counter <= counter + 1'b1;
	     
	     if (y)
	       begin
		  counter <= 5'b0;
		  flag <= 1'b1;
	       end
	     
	     if (flag && (counter == L_RAM_SIZE-1'b1)) 
	       begin
		  flag <= 1'b0;
	       end	
	  end // else: !if( !rst_n )
	
	
    end	
   assign y = !ff & !KEY;
   assign addr[0] = flag && counter[0];
   assign addr[1] = flag && counter[1];
   assign addr[2] = flag && counter[2];
   assign addr[3] = flag && counter[3];
   assign addr[4] = flag && counter[4];
   
endmodule
