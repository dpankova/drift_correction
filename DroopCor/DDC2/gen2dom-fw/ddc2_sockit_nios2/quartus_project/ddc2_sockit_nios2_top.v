//////////////////////////////////////////////////////////////////////////////////////
// Tyler Anderson Thu Oct 30 16:27:31 EDT 2014
// ddc2_sockit_nios2_top.v
//
// Top-level Verilog HDL module for DDC2 readout by SoCKit using NIOS II. 
//
// Major modules:
//
// version_number: "Version Number"
//                 A custom Verilog HDL module which contains a verison number
//                 for the project. It is automatically updated with each compile.
// 
// RCLK_PLL: "Reference Clock Phase-Locked Loop"
//            A PLL IP-core. Locks to R_CLK and generates DDC_ENC_IN and proc_clk.
//
// ADC_PLL: "ADC Phased-Locked Loop" 
//          A PLL IP-core. Locks to DDC_ENC_OUT and generates serial_clk, 
//          serial_clk_en, and logic_clk.
// 
// RST_GEN: "Reset Generator"
//          A custom Verilog HDL module. Generates a "synchronized asynchronous reset"
//          for modules in logic_clk and proc_clk domains. (See Q2HB 12-32). 
//   
// ADC_LVDS: "ADC Low-Voltage Differential Signaling Deserializer"
//           A SERDES (8x7) IP-core. De-serializes DDC2's incoming ADC datastream.
//           Four samples are processed in each logic_clk cycle.
//
// flash_HSMC_TEST: "Flash High-Speed Mezzanine Connector Tester" 
//                  A custom Verilog HDL module. Flashes DDC2 LED1 to show that 
//                  SoCKit FPGA is programmed.
//
// fcr_ctrl: "FPGA Command and Reponse Control"
//           A custom Verilog HDL module. Reads commands from QSYS command FIFO,
//           takes the appropriate action, and writes response words to the QSYS 
//           response FIFO.
//
// ltc: "Local Time Counter" 
//      A custom Verilog HDL module. Generates the 48-bit local time word.
// 
// tap: "Trigger and Pipeline"
//      A custom Verilog HDL module. Generates trigger signals based on a combination of
//      the ADC datastream and various user-selectable trigger conditions from QSYS. Also
//      pipelines the data output to align it with the TOT bits. 
// 
// af_ctrl: "ADC FIFO Control"
//          A custom Verilog HDL module. Generates the event record decision and the 
//          corresponding AFM FIFO control signals based on trigger signals from tap. 
//          Also generates header and footer words for phf_ctrl.
//   
// afm: "ADC FIFO Module"
//      A custom Verilog HDL module with some internal IP-core FIFOs. Stores the ADC
//      event data. Internal dual-clock FIFOs separate "upstream" (logic_clk) and 
//      "downstream" (proc_clk) clock domains.
//
// pef_ctrl: "Processor Event FIFO Control"
//           A custom Verilog HDL module. Receives notification of a new event from 
//           phf_ctrl. Retrieves the AFM index of the first sample in the event from 
//           phf_ctrl. It then proceeds to empty the AFMs into PEF until an end-of-event
//           (EOE) is encountered. Controls the address lines of the PEF_MUX multiplexer
//           to switch between the four AFM FIFO data words.  
//  
// phf_ctrl: "Processor Header FIFO Control"
//           A custom Verilog HDL module. Receives the event header and footer words 
//           from af_ctrl and the event's local time word from ltc. It handshakes the 
//           header word to pef_ctrl, and then writes the header, local time, and footer
//           data words to the QSYS Processor Header FIFO (PHF).
//
// PEF_MUX: "Processor Event FIFO Multiplexer"
//          A 32x4 IP-core. Multiplexers the four AFM FIFOs going into the QSYS PEF.
// 
// ddc2_sockit_qsys_nios2: "DDC2 SoCKit QSYS NIOS II"
//                         The QSYS module. Includes: 
//                         -- Clock and reset manager
//                         -- Systen ID peripheral
//                         -- NIOS II/f processor
//                         -- On-board program and data memory
//                         -- JTAG debugging module (for USB interface)
//                         -- Timer peripheral (for benchmarking code)
//                         -- Processor Event FIFO (PEF)
//                         -- Processor Header FIFO (PHF)
//                         -- Command FIFO (CMDF)
//                         -- Response FIFO (RSPF)
//                         -- DDC2 SPI controller
//                         -- HVS SPI and GPIO controller
//////////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 100ps

module ddc2_sockit_nios2_top
  (
   // SoCKit Peripheral I/Os
   input       KEY0, // Pushbutton, pressing gives a LOW
   input       KEY1, // Pushbutton, pressing gives a LOW
   input       KEY2, // Pushbuton, arms a single trigger
   output      LED0, // Indicates RCLK PLL is locked
   output      LED1, // Indicates ADC PLL is locked
   output      LED2, // Flashes to indicates that the HVS is enabled.
   output      LED3, // Solid-ON indicates that record is armed
   input       R_CLK, // 50MHz reference clock

   //baseline trial
   input       SW0, // switch, for read_fin
   input       KEY3, // Pushbuton, for read_mod
   
   // DDC ADC data interface I/Os
   input [6:0] DDC_ADC_D, // ADC data inputs (these need to be inverted)
   input       DDC_ENC_OUT, // Data clock from ADC
   output      DDC_ENC_IN, // Data clock to ADC
   
   // DDC SPI I/Os
   output      DDC_SCK, // Serial clock for SPI interfaces
   output      DDC_MOSI, // Master-out, slave-in for SPI interfaces
   output      DDC_RESET_ADC, // Resets the DDC ADC
   output      DDC_CS_ADC_SAMPLER, // Chip select for DDC ADC
   input       DDC_MISO_ADC_SAMPLER, // Master-in, slave-out for DDC ADC
   output      DDC_CS_DAC_OFFSET, // Chip select for DDC offset DAC
   input       DDC_MISO_DAC_OFFSET, // Master-in, slave-out for DDC offset DAC
   output      DDC_CS_SENSOR_PT, // Chip select for DDC pressure/temperature sensor
   input       DDC_MISO_SENSOR_PT, // Master-in, slave-out for DDC pressure/temperature sensor

   // DDC Trigger I/Os
   output      DDC_TRIG_OUT, // trigger output from the DDC
   input       DDC_TRIG_IN, // trigger input to the DDC
   
   // HVS SPI I/Os
   input       HVS_MISO, // Master-in, slave-out for HVS
   output      HVS_CS0_N, // Chip select for control DAC on HVS (active low)
   output      HVS_HVEN, // High voltage enable for HVS
   output      HVS_SCK, // Serial clock for HVS
   output      HVS_MOSI, // Master-out, slave-in for HVS
   output      HVS_CS1_N, // Chip select for monitor ADC on HVS (active low)
      
   // Debugging LED
   output      HSMC_TEST_LED // flashing green on DDC says SoCKit is programmed
   );


   //////////////////////////////////////////////////////////////////////////////////////
   // Version number generated automatically at each compile.
   wire [15:0] version_number;
   version_number VNUM0(.version_number(version_number));
      
   //////////////////////////////////////////////////////////////////////////////////////
   // RCLK PLL (RCLK_PLL) and its reset generator
   // ALTPLL megafunction
   wire        rclk_outclk_0; // DDC2 ADC input clock.
   wire        proc_clk; // processor logic clock. Used downstream of AFMs.
   wire        rclk_pll_locked; // RCLK_PLL locked.
   wire        rclk_rst_n; // RCLK_PLL sychronized asynchronous reset
   wire        proc_clk_rst_n; // proc_clk sychronized asynchronous reset.
   
   RCLK_PLL RCLK_PLL_0(
		       .refclk(R_CLK), 
		       .rst(!KEY0), 
		       .outclk_0(rclk_outclk_0),
		       .outclk_1(proc_clk),
		       .locked(rclk_pll_locked)
		       );
   rst_gen RST_GEN0(.clk(R_CLK),.arst_n(rclk_pll_locked),.rst_n(rclk_rst_n));
   rst_gen RST_GEN1(.clk(proc_clk),.arst_n(rclk_pll_locked),.rst_n(proc_clk_rst_n));
   assign LED0 = rclk_pll_locked;
   assign DDC_ENC_IN = rclk_outclk_0;
   
   //////////////////////////////////////////////////////////////////////////////////
   // The PLL which locks to the ADC serial clock
   wire        serial_clk; // the serial clock for the SERDES
   wire        serial_clk_en; // the serial clock enable for the SERDES
   wire        logic_clk; // clock for fabric
   wire        adc_pll_locked; // ADC_PLL locked
   wire        logic_clk_rst_n; // ADC_PLL synchronous reset
   ADC_PLL ADC_PLL0 (
		     .refclk   (DDC_ENC_OUT),
		     .rst      (!KEY0),
		     .outclk_0 (serial_clk),
		     .outclk_1 (serial_clk_en),
		     .outclk_2 (logic_clk),
		     .locked   (adc_pll_locked)
		     );
   rst_gen RST_GEN2(.clk(logic_clk),.arst_n(adc_pll_locked),.rst_n(logic_clk_rst_n));
   assign LED1 = adc_pll_locked;

   //////////////////////////////////////////////////////////////////////////////////
   // ALTLVDS megafunction for SERDES
   wire [13:0] data_stream_0_n; // inverted 1st ADC sample
   wire [13:0] data_stream_1_n; // inverted 2nd ADC sample
   wire [13:0] data_stream_2_n; // inverted 3rd ADC sample
   wire [13:0] data_stream_3_n; // inverted 4th ADC sample
   reg [13:0]  data_stream_0; // polarity corrected 1st ADC sample
   reg [13:0]  data_stream_1; // polarity corrected 2nd ADC sample
   reg [13:0]  data_stream_2; // polarity corrected 3rd ADC sample
   reg [13:0]  data_stream_3; // polarity corrected 4th ADC sample
   
   ADC_LVDS ADC_LVDS0(
		      .rx_enable(serial_clk_en),
		      .rx_in(DDC_ADC_D),
		      .rx_inclock(serial_clk),
		      .rx_out({
			       data_stream_0_n[12],
			       data_stream_0_n[13],
			       data_stream_1_n[12],
			       data_stream_1_n[13],
			       data_stream_2_n[12],
			       data_stream_2_n[13],
			       data_stream_3_n[12],
			       data_stream_3_n[13],
			       data_stream_0_n[10],
			       data_stream_0_n[11],
			       data_stream_1_n[10],
			       data_stream_1_n[11],
			       data_stream_2_n[10],
			       data_stream_2_n[11],
			       data_stream_3_n[10],
			       data_stream_3_n[11],
			       data_stream_0_n[8],
			       data_stream_0_n[9],
			       data_stream_1_n[8],
			       data_stream_1_n[9],
			       data_stream_2_n[8],
			       data_stream_2_n[9],
			       data_stream_3_n[8],
			       data_stream_3_n[9],
			       data_stream_0_n[6],
			       data_stream_0_n[7],
			       data_stream_1_n[6],
			       data_stream_1_n[7],
			       data_stream_2_n[6],
			       data_stream_2_n[7],
			       data_stream_3_n[6],
			       data_stream_3_n[7],
			       data_stream_0_n[4],
			       data_stream_0_n[5],
			       data_stream_1_n[4],
			       data_stream_1_n[5],
			       data_stream_2_n[4],
			       data_stream_2_n[5],
			       data_stream_3_n[4],
			       data_stream_3_n[5],
			       data_stream_0_n[2],
			       data_stream_0_n[3],
			       data_stream_1_n[2],
			       data_stream_1_n[3],
			       data_stream_2_n[2],
			       data_stream_2_n[3],
			       data_stream_3_n[2],
			       data_stream_3_n[3],
			       data_stream_0_n[0],
			       data_stream_0_n[1],
			       data_stream_1_n[0],
			       data_stream_1_n[1],
			       data_stream_2_n[0],
			       data_stream_2_n[1],
			       data_stream_3_n[0],
			       data_stream_3_n[1]
			       })
		      );
   
   // Need to invert the inputs. This adds one cycle of latency.
   always @(posedge logic_clk )
     begin
	data_stream_0 <= ~data_stream_0_n;
	data_stream_1 <= ~data_stream_1_n;
	data_stream_2 <= ~data_stream_2_n;
	data_stream_3 <= ~data_stream_3_n;
     end
   
//////////////////////////////////////////////////////////////////////////////////
   //Baseline drift correction module trial
   wire pause; // paude data taking
   wire rescale; //enable rescaling of histogramm
   wire [4:0] addr_read; // addr for reading aout the hist once it's filled
   wire read_fin_mid; // indicates reading is over
   wire read_fin; // indicates reading is over
      
   wire [19:0] count_in_out_0; // count in the last bin if it was repeating
   wire [4:0]  addr_count_in_0; // address of the last bin if it was repeating
   wire [13:0] center_val_0; // the value of central hist bin
   wire        filled_0; // signal what hist 0 is filled
   wire        read_fin_0; // signal what processor finished reading
   wire [4:0]  rdaddr_0; // hist 0 read out address
   wire [19:0] out_ram_0; // hist 0 read out bin value
   wire [19:0] count_in_out_1;
   wire [4:0]  addr_count_in_1;
   wire [13:0] center_val_1; // the value of central hist bin
   wire        filled_1; // signal what hist 1  is filled
   wire        read_fin_1; // signal what processor finished reading
   wire [4:0]  rdaddr_1; //  hist 1 read out address
   wire [19:0] out_ram_1; //  hist 1 read out bin value
   wire [19:0] count_in_out_2;
   wire [4:0]  addr_count_in_2;
   wire [13:0] center_val_2; // the value of central hist bin
   wire        filled_2; // signal what hist 2 is filled
   wire        read_fin_2; // signal what processor finished reading
   wire [4:0]  rdaddr_2; //  hist 2 read out address
   wire [19:0] out_ram_2; //  hist 2 read out bin value
   wire [19:0] count_in_out_3;
   wire [4:0]  addr_count_in_3;
   wire [13:0] center_val_3; // the value of central hist bin
   wire        filled_3; // signal what hist 3  is filled
   wire        read_fin_3; // signal what processor finished reading
   wire [4:0]  rdaddr_3; //  hist 3 read out address
   wire [19:0] out_ram_3; //  hist 3 read out bin value

   wire [3:0]  fsm_0;
   wire [3:0]  fsm_1;
   wire [3:0]  fsm_2;
   wire [3:0]  fsm_3; 

   reg [3:0]   fsm_0_reg /* synthesis noprune */;
   reg [3:0]   fsm_1_reg /* synthesis noprune */;
   reg [3:0]   fsm_2_reg /* synthesis noprune */; 
   reg [3:0]   fsm_3_reg /* synthesis noprune */;

   reg 	       sw0_reg;

   wire [4:0]  addr_out_0;
   wire [4:0]  addr_out_1;
   wire [4:0]  addr_out_2;
   wire [4:0]  addr_out_3;

   reg [4:0]   addr_out_0_reg /* synthesis noprune */;
   reg [4:0]   addr_out_1_reg /* synthesis noprune */;
   reg [4:0]   addr_out_2_reg /* synthesis noprune */;
   reg [4:0]   addr_out_3_reg /* synthesis noprune */;

   reg [19:0] count_in_out_0_reg /* synthesis noprune */;  
   reg [4:0]  addr_count_in_0_reg /* synthesis noprune */;  
   reg 	      filled_0_reg /* synthesis noprune */;  
   reg [19:0] out_ram_0_reg /* synthesis noprune */; 
   reg [19:0] count_in_out_1_reg /* synthesis noprune */;
   reg [4:0]  addr_count_in_1_reg /* synthesis noprune */;
   reg        filled_1_reg /* synthesis noprune */; 
   reg [19:0] out_ram_1_reg /* synthesis noprune */; 
   reg [19:0] count_in_out_2_reg /* synthesis noprune */;
   reg [4:0]  addr_count_in_2_reg /* synthesis noprune */;
   reg        filled_2_reg /* synthesis noprune */; 
   reg [19:0] out_ram_2_reg /* synthesis noprune */;
   reg [19:0] count_in_out_3_reg /* synthesis noprune */;
   reg [4:0]  addr_count_in_3_reg /* synthesis noprune */;
   reg        filled_3_reg /* synthesis noprune */;
   reg [19:0] out_ram_3_reg /* synthesis noprune */;
   reg        read_fin_reg /* synthesis noprune */;
   reg [4:0]  addr_read_reg /* synthesis noprune */;

   always @(posedge logic_clk)
     begin
	count_in_out_0_reg <= count_in_out_0;
 	addr_count_in_0_reg <=  addr_count_in_0;
	filled_0_reg <= filled_0;
	out_ram_0_reg <=  out_ram_0;
	count_in_out_1_reg <=  count_in_out_1; 
	addr_count_in_1_reg <=  addr_count_in_1;
 	filled_1_reg  <= filled_1;
	out_ram_1_reg <= out_ram_1; 
	count_in_out_2_reg <= count_in_out_2;
	addr_count_in_2_reg <= addr_count_in_2;
	filled_2_reg <= filled_2;
	out_ram_2_reg <=  out_ram_2;
	count_in_out_3_reg <= count_in_out_3;
	addr_count_in_3_reg <= addr_count_in_3;
	filled_3_reg <= filled_3;
	out_ram_3_reg  <= out_ram_3;
	read_fin_reg <= read_fin;
	addr_read_reg <= addr_read;
	fsm_0_reg <= fsm_0;
	fsm_1_reg <= fsm_1;
	fsm_2_reg <= fsm_2;
	fsm_3_reg <= fsm_3;
	sw0_reg <= SW0;
	addr_out_0_reg <= addr_out_0;
	addr_out_1_reg <= addr_out_1;
	addr_out_2_reg <= addr_out_2;
	addr_out_3_reg <= addr_out_3;
		
     end
   
   assign center_val_0 = 14'd8188;
   assign center_val_1 = 14'd8188;
   assign center_val_2 = 14'd8188;
   assign center_val_3 = 14'd8188;
   assign rescale = 1'b0;
   assign pause = 1'b0;

   read_mod read_mod (
		      .clk(logic_clk), // clock
		      .rst_n(logic_clk_rst_n), // active low reset
		      .KEY(KEY3), // input on which positive 
		      .addr(addr_read)
		      );

   debounce read_fin0 (
		       .clk(logic_clk), // clock
		       .rst_n(logic_clk_rst_n), // active low reset
		       .a(SW0), // input on which positive 
		       .y(read_fin_mid)
		       );
   
   posedge_detector pos1 (
			  .clk(logic_clk), // clock
			  .rst_n(logic_clk_rst_n), // active low reset
			  .a(read_fin_mid), // input on which positive 
			  .y(read_fin)
			  );
   
   
   drift drift0 (
		 .adc(data_stream_0),
		 .center_val(center_val_0),
		 .rst_n(logic_clk_rst_n),
		 .pause(pause),
		 .rescale(rescale),
		 .read_fin(read_fin),
		 .q_a(out_ram_0),
		 .rdaddr(addr_read),
		 .clk(logic_clk),
		 .filled(filled_0),
		 .count_in_out(count_in_out_0),
		 .addr_count_in(addr_count_in_0),
		 .fsm_out(fsm_0),
		 .addr_out(addr_out_0)
		 );
   
   drift drift1 (
		 .adc(data_stream_1),
		 .center_val(center_val_1),
		 .rst_n(logic_clk_rst_n),
		 .pause(pause),
		 .rescale(rescale),
		 .read_fin(read_fin),
		 .q_a(out_ram_1),
		 .rdaddr(addr_read),
		 .clk(logic_clk),
		 .filled(filled_1),
		 .count_in_out(count_in_out_1),
		 .addr_count_in(addr_count_in_1),
		 .fsm_out(fsm_1),
		 .addr_out(addr_out_1)
		 );
   
   drift drift2 (
		 .adc(data_stream_2),
		 .center_val(center_val_2),
		 .rst_n(logic_clk_rst_n),
		 .pause(pause),
		 .rescale(rescale),
		 .read_fin(read_fin),
		 .q_a(out_ram_2),
		 .rdaddr(addr_read),
		 .clk(logic_clk),
		 .filled(filled_2),
		 .count_in_out(count_in_out_2),
		 .addr_count_in(addr_count_in_2),
		 .fsm_out(fsm_2),
		 .addr_out(addr_out_2)
		 );
   
   drift drift3 (
		 .adc(data_stream_3),
		 .center_val(center_val_3),
		 .rst_n(logic_clk_rst_n),
		 .pause(pause),
		 .rescale(rescale),
		 .read_fin(read_fin),
		 .q_a(out_ram_3),
		 .rdaddr(addr_read),
		 .clk(logic_clk),
		 .filled(filled_3),
		 .count_in_out(count_in_out_3),
		 .addr_count_in(addr_count_in_3),
		 .fsm_out(fsm_3),
		 .addr_out(addr_out_3)
		 );
   //////////////////////////////////////////////////////////////////////////////////////
   // LED flasher indicating the FPGA is programmed.
   flash_HSMC_TEST flash_HSMC_TEST0(.clk(R_CLK),.rst_n(rclk_rst_n),.cout(HSMC_TEST_LED));
   
   //////////////////////////////////////////////////////////////////////////////////////
   // The FPGA Command and Response Control (fcr_ctrl) module
   // Comments below are relative to fcr_ctrl
   wire [31:0] cmd_data; // FCR command data to QSYS
   wire [31:0] rsp_data; // RSP response data to QSYS
   wire        cmd_rdreq; // QSYS command FIFO read request
   wire        rsp_wrreq; // QSYS command FIFO write request
   wire        ltc_req; // Handshaking request to ltc
   wire        ltc_busy; // Handshaking busy from ltc
   wire [47:0] ltc_to_fcr; // local time word from ltc 
   wire        tap_req; // Handshaking request to tap
   wire        tap_busy; // Handshaking busy from tap
   wire        tap_run; // SW run to tap
   wire        tap_gt; // Greater than trigger signal to tap
   wire        tap_et; // Equal to trigger signal to tap
   wire        tap_lt; // Less than trigger to tap
   wire [13:0] tap_thr; // Trigger threshold to TAP
   wire        tap_trig_en; // Trigger enable to TAP
   wire        pef_clear_req; // Handshaking clear request to pef_ctrl
   wire        pef_clear_busy; // Handshaking clear busy from pef_ctrl
   wire        phf_req; // Handshaking request to phf_ctrl
   wire        phf_busy; // Handshaking busy from phf_ctrl
   wire        af_req; // Handshaking request to af_ctrl 
   wire        af_busy; // Handshaking busy from af_ctrl 
   wire [2:0]  af_pre_config; // pre-trigger configuration word to af_ctrl and AFM
   wire [2:0]  af_post_config; // post-trigger configuration word to af_ctrl 
   wire [15:0] af_status; // Status word from af_ctrl
   wire [15:0] pef_status; // Status word from pef_ctrl
   wire [15:0] phf_status; // Status word from phf_ctrl
   wire        pef_status_req; // Handshaking status request to pef_ctrl
   wire        pef_status_busy; // Handshaking status busy from pef_ctrl
   wire        phf_status_req; // Handshaking status request to phf_ctrl
   wire        phf_status_busy; // Handshaking status busy from phf_ctrl
   wire        phf_clear_req; // Handshaking clear request to phf_ctrl
   wire        phf_clear_busy; // Handshaking clear busy from phf_ctrl
   wire [10:0] af_test_config; // test configuration word to af_ctrl
   wire [10:0] af_cnst_config; // constant configuration word to af_ctrl
   wire        af_cnst_run; // constant run mode signal to af_ctrl
   wire        dt_trig_mode; // trigger mode signal to top level
   fcr_ctrl FCR_CTRL0(
		      .clk(proc_clk),
		      .rst_n(proc_clk_rst_n),
		      .cmd_data(cmd_data),
		      .rsp_data(rsp_data),
		      .cmd_rdreq(cmd_rdreq),
		      .rsp_wrreq(rsp_wrreq),
		      .cmd_waitreq(cmd_waitreq),
		      .rsp_waitreq(rsp_waitreq),
		      .ltc_req(ltc_req),
		      .ltc_busy(ltc_busy),
		      .ltc(ltc_to_fcr),
		      .tap_req(tap_req),
		      .tap_busy(tap_busy),
		      .tap_run(tap_run),
		      .tap_gt(tap_gt),
		      .tap_et(tap_et),
		      .tap_lt(tap_lt),
		      .tap_thr(tap_thr),
		      .tap_trig_en(tap_trig_en),
		      .pef_clear_req(pef_clear_req),
		      .pef_clear_busy(pef_clear_busy),
		      .phf_clear_req(phf_clear_req),
		      .phf_clear_busy(phf_clear_busy),
		      .af_req(af_req),
		      .af_busy(af_busy),
		      .af_pre_config(af_pre_config),
		      .af_post_config(af_post_config),
		      .af_status(af_status),
		      .pef_status(pef_status),
		      .phf_status(phf_status),
		      .pef_status_req(pef_status_req),
		      .pef_status_busy(pef_status_busy),
		      .phf_status_req(phf_status_req),
		      .phf_status_busy(phf_status_busy),
		      .af_test_config(af_test_config),
		      .af_cnst_run(af_cnst_run),
		      .af_cnst_config(af_cnst_config),
		      .dt_trig_mode(dt_trig_mode),
		      .version_number(version_number)
		      );
   
   //////////////////////////////////////////////////////////////////////////////////////
   // The local time counter
   wire [47:0] local_time;   
   ltc LTC0
     (
      .clk(logic_clk),
      .rst_n(logic_clk_rst_n),
      .local_time(local_time),
      .ltc_to_fcr(ltc_to_fcr),
      .ltc_req(ltc_req),
      .ltc_busy(ltc_busy)
      );
   
   //////////////////////////////////////////////////////////////////////////////////////
   // Trigger and Pipeline (TAP) module.
   wire [13:0] data_stream_0_pl; // 1st sample of pipelined adc data stream to AFM
   wire [13:0] data_stream_1_pl; // 2nd sample of pipelined adc data stream to AFM
   wire [13:0] data_stream_2_pl; // 3rd sample of pipelined adc data stream to AFM
   wire [13:0] data_stream_3_pl; // 4th sample of pipelined adc data stream to AFM
   wire [3:0]  trig; // trigger signals to af_ctrl (used to make record decision)
   wire        trig_test; // tells af_ctrl to trigger a test record 
   wire        tot_0; // 1st sample time-over-threshold (TOT) bit to AFM
   wire        tot_1; // 2nd sample time-over-threshold (TOT) bit to AFM
   wire        tot_2; // 3rd sample time-over-threshold (TOT) bit to AFM
   wire        tot_3; // 4th sample time-over-threshold (TOT) bit to AFM
   wire        trig_in; // Negative edge detector for the DDC_TRIG_IN input 
   negedge_detector NEDGE2(.clk(logic_clk),.rst_n(logic_clk_rst_n),.a(DDC_TRIG_IN),.y(trig_in));
   
   tap TAP0(
	    .clk(logic_clk),
	    .rst_n(logic_clk_rst_n),
	    .data_stream_0_in(data_stream_0),
	    .data_stream_1_in(data_stream_1),
	    .data_stream_2_in(data_stream_2),
	    .data_stream_3_in(data_stream_3),
	    .data_stream_0_out(data_stream_0_pl),
	    .data_stream_1_out(data_stream_1_pl),
	    .data_stream_2_out(data_stream_2_pl),
	    .data_stream_3_out(data_stream_3_pl),
	    .gt(tap_gt),
	    .et(tap_et),
	    .lt(tap_lt),
	    .trig_en(tap_trig_en),
	    .run(tap_run),
	    .thr(tap_thr),
	    .cmd_req(tap_req),
	    .cmd_busy(tap_busy),
	    .trig(trig),
	    .tot_0(tot_0),
	    .tot_1(tot_1),
	    .tot_2(tot_2),
	    .tot_3(tot_3),
	    .trig_test(trig_test),
	    .ext_run(!KEY1 || trig_in)
	    );
        
   //////////////////////////////////////////////////////////////////////////////////////
   // ADC FIFO Control (af_ctrl).
   wire [3:0]  ptf_full; // pre-trigger FIFO is full
   wire [3:0]  wff_wrfull; // waveform FIFO is full 
   wire [3:0]  wff_wrempty; // waveform FIFO is empty (synchronized to write flag)
   wire [10:0] wff_wrusedw_0; // AFS waveform FIFO 0 number of used words
   wire [10:0] wff_wrusedw_1; // AFS waveform FIFO 1 number of used words
   wire [10:0] wff_wrusedw_2; // AFS waveform FIFO 2 number of used words
   wire [10:0] wff_wrusedw_3; // AFS waveform FIFO 3 number of used words
   wire [3:0]  eoe; // end of event flag
   wire [3:0]  ptf_wrreq; // pre-trigger FIFO write request 
   wire [3:0]  ptf_rdreq; // pre-trigger FIFO read request
   wire [3:0]  wff_wrreq; // waveform FIFO write request
   wire [31:0] header; // header word for phf_ctrl
   wire        header_wrreq; // header write request for phf_ctrl
   wire [31:0] footer; // footer word for phf_ctrl
   wire        footer_wrreq; // footer write request for phf_ctrl
   wire        armed; // status of af_ctrl run enable      
   wire        key2_s; // Synchronized SoCKit KEY2
   wire        arm; // Use negative edge of KEY2 to arm in singly-triggered mode
   sync SYNC0(.clk(logic_clk),.rst_n(logic_clk_rst_n),.a(KEY2),.y(key2_s));
   negedge_detector NEDGE1(.clk(logic_clk),.rst_n(logic_clk_rst_n),.a(key2_s),.y(arm));
   
   af_ctrl AF_CTRL0
     (
      .clk(logic_clk),
      .rst_n(logic_clk_rst_n),
      .trig(trig),
      .trig_test(trig_test),
      .ptf_full(ptf_full),
      .wff_full(wff_wrfull),
      .wff_wrusedw_0(wff_wrusedw_0),
      .wff_wrusedw_1(wff_wrusedw_1),
      .wff_wrusedw_2(wff_wrusedw_2),
      .wff_wrusedw_3(wff_wrusedw_3),
      .wff_empty(wff_wrempty),
      .pre_config(af_pre_config),
      .post_config(af_post_config),
      .eoe(eoe),
      .ptf_wrreq(ptf_wrreq),
      .ptf_rdreq(ptf_rdreq),
      .wff_wrreq(wff_wrreq),
      .header(header),
      .header_wrreq(header_wrreq),
      .footer(footer),
      .footer_wrreq(footer_wrreq),
      .cmd_req(af_req),
      .cmd_busy(af_busy),
      .status(af_status),
      .test_config(af_test_config),
      .cnst_config(af_cnst_config),
      .cnst_run(af_cnst_run),
      .arm(arm),
      .trig_mode(dt_trig_mode),
      .armed(armed)
      );
      
   //////////////////////////////////////////////////////////////////////////////////////
   // ADC FIFO Module (afm).
   wire [31:0] afm_data_word_0_out; // AFM data word from 1st sample to processor
   wire [31:0] afm_data_word_1_out; // AFM data word from 2nd sample to processor
   wire [31:0] afm_data_word_2_out; // AFM data word from 3rd sample to processor
   wire [31:0] afm_data_word_3_out; // AFM data word from 4th sample to processor
   wire [3:0]  wff_rdreq; // waveform FIFO read request from pef_ctrl
   wire [3:0]  wff_rdempty; // waveform FIFO empty (synchronized to read clock)
   wire [3:0]  ptf_empty; // pre-trigger FIFO is empty
   afm AFM(
	   .wrclk(logic_clk),
	   .wrclk_rst_n(logic_clk_rst_n),
	   .tot({tot_3,tot_2,tot_1,tot_0}),
	   .eoe(eoe),
	   .data_stream_0_in(data_stream_0_pl),
	   .data_stream_1_in(data_stream_1_pl),
	   .data_stream_2_in(data_stream_2_pl),
	   .data_stream_3_in(data_stream_3_pl),
	   .ptf_wrreq(ptf_wrreq),
	   .ptf_rdreq(ptf_rdreq),
	   .ptf_empty(ptf_empty),
	   .ptf_full(ptf_full),
	   .wff_wrreq(wff_wrreq),
	   .wff_wrempty(wff_wrempty),
	   .wff_wrfull(wff_wrfull),
	   .wff_wrusedw_0(wff_wrusedw_0),
	   .wff_wrusedw_1(wff_wrusedw_1),
	   .wff_wrusedw_2(wff_wrusedw_2),
	   .wff_wrusedw_3(wff_wrusedw_3),
	   .ltc(local_time),
	   .cmd_req(af_req),
	   .cmd_busy(),
	   .pre_config(af_pre_config),
	   .post_config(af_post_config),
	   .rdclk(proc_clk),
	   .rdclk_rst_n(proc_clk_rst_n),
	   .data_word_0_out(afm_data_word_0_out),
	   .data_word_1_out(afm_data_word_1_out),
	   .data_word_2_out(afm_data_word_2_out),
	   .data_word_3_out(afm_data_word_3_out),
	   .wff_rdreq(wff_rdreq),
	   .wff_rdempty(wff_rdempty)
	   );
   
   //////////////////////////////////////////////////////////////////////////////////////
   // Processor Event FIFO Control (pef_ctrl) 
   // Processor event FIFO Multiplexer (PEF_MUX) 
   // Processor Header FIFO Control (phf_ctrl) 
   wire        pef_run_n; // phf_ctrl tells pef_ctrl that there's new data, so get it 
   wire [31:0] phf_data; // phf_ctrl header to QSYS PHF 
   wire        pef_ok; // read the event header word from phf_ctrl
   wire        pef_wrreq; // write to the QSYS PEF
   wire        pef_waitreq; // PEF requests wait to write (backpressure) 
   wire [1:0]  pemux_adr; // address for the PEF multiplexer
   wire [31:0] pef_header; // header word to pef_ctrl
   wire [31:0] proc_adc_datastream; // data stream out of PEF_MUX  
   wire        phf_wrreq; // write to the QSYS PHF
   wire        phf_waitreq; // PHF requests wait to write (backpressure)
   
   pef_ctrl PEF_CTRL0
     (
      .clk(proc_clk),
      .rst_n(proc_clk_rst_n),
      .phf_empty(!pef_run_n),
      .phf_data(pef_header),
      .phf_rdreq(pef_ok),
      .af_empty_0(wff_rdempty[0]),
      .af_empty_1(wff_rdempty[1]),
      .af_empty_2(wff_rdempty[2]),
      .af_empty_3(wff_rdempty[3]),
      .af_rdreq_0(wff_rdreq[0]),
      .af_rdreq_1(wff_rdreq[1]),
      .af_rdreq_2(wff_rdreq[2]),
      .af_rdreq_3(wff_rdreq[3]),
      .af_data_0(afm_data_word_0_out),
      .af_data_1(afm_data_word_1_out),
      .af_data_2(afm_data_word_2_out),
      .af_data_3(afm_data_word_3_out),
      .pef_wrreq(pef_wrreq),
      .pef_waitreq(pef_waitreq),
      .pemux_adr(pemux_adr),
      .clear_req(pef_clear_req),
      .clear_busy(pef_clear_busy),
      .status_req(pef_status_req),
      .status_busy(pef_status_busy),
      .status(pef_status)
      );
   
   PEF_MUX PEF_MUX0(
		    .data0x(afm_data_word_0_out),
		    .data1x(afm_data_word_1_out),
		    .data2x(afm_data_word_2_out),
		    .data3x(afm_data_word_3_out),
		    .sel(pemux_adr),
		    .result(proc_adc_datastream)
		    );
   
   phf_ctrl PHF_CTRL0(
		      .lclk(logic_clk),
		      .lclk_rst_n(logic_clk_rst_n),
		      .pclk(proc_clk),
		      .pclk_rst_n(proc_clk_rst_n),
		      .header_wrreq(header_wrreq),
		      .header(header),
		      .footer_wrreq(footer_wrreq),
		      .footer(footer),
		      .local_time_wrreq(header_wrreq),
		      .local_time(local_time), 
		      .phf_wrreq(phf_wrreq),
		      .phf_data(phf_data),
		      .phf_waitreq(phf_waitreq),
		      .pef_ok(pef_ok),
		      .pef_run(pef_run_n),
		      .pef_header(pef_header),
		      .clear_req(phf_clear_req),
		      .clear_busy(phf_clear_busy),
		      .status_req(phf_status_req),
		      .status_busy(phf_status_busy),
		      .status(phf_status)
		      );
   
   //////////////////////////////////////////////////////////////////////////////////////
   // The QSYS NIOS II module
   wire        cmd_waitreq; // QSYS command FIFO requests wait to write (backpressure)
   wire        rsp_waitreq; // QSYS respnose FIFO requests wait to write (backpressure)
   wire        qsys_ddc_dac_miso; // DDC DAC master in, slave out
   wire        qsys_ddc_dac_mosi; // DDC DAC master out, slave in
   wire        qsys_ddc_dac_sclk; // DDC DAC serial clock
   wire        qsys_ddc_dac_ssn; // DDC DAC slave select (active low)
   wire        qsys_ddc_adc_miso; // DDC ADC master in, slave out
   wire        qsys_ddc_adc_mosi; // DDC ADC master out, slave in
   wire        qsys_ddc_adc_sclk; // DDC ADC serial clock
   wire        qsys_ddc_adc_ssn; // DDC ADC slave select (active low)
   wire        qsys_ddc_pt_miso; // DDC pressure sensor master in, slave out
   wire        qsys_ddc_pt_mosi; // DDC pressure sensor master out, slave in
   wire        qsys_ddc_pt_sclk; // DDC pressure sensor serial clock
   wire        qsys_ddc_pt_ssn; // DDC pressure sensor slave select (active low)

   // For DDC2
   assign DDC_CS_DAC_OFFSET = qsys_ddc_dac_ssn;
   assign DDC_CS_ADC_SAMPLER = qsys_ddc_adc_ssn;
   assign DDC_CS_SENSOR_PT = qsys_ddc_pt_ssn;
   assign DDC_SCK = (!qsys_ddc_dac_ssn && qsys_ddc_dac_sclk) ||
		    (!qsys_ddc_adc_ssn && qsys_ddc_adc_sclk) ||
		    (!qsys_ddc_pt_ssn && qsys_ddc_pt_sclk)   ||
		    (qsys_ddc_dac_ssn && qsys_ddc_adc_ssn && qsys_ddc_pt_ssn);
   assign DDC_MOSI = (
		      (!qsys_ddc_dac_ssn && qsys_ddc_dac_mosi) ||
		      (!qsys_ddc_adc_ssn && qsys_ddc_adc_mosi) ||
		      (!qsys_ddc_pt_ssn && qsys_ddc_pt_mosi)
		      ) &&
		     !(qsys_ddc_dac_ssn && qsys_ddc_adc_ssn && qsys_ddc_pt_ssn);
   assign qsys_ddc_dac_miso = DDC_MISO_DAC_OFFSET;
   assign qsys_ddc_adc_miso = DDC_MISO_ADC_SAMPLER;
   assign qsys_ddc_pt_miso = DDC_MISO_SENSOR_PT;
   
   // For HVS
   wire        hvs_mosi_dac; // HVS DAC master out, slave in 
   wire        hvs_mosi_adc; // HVS ADC master out, slave in
   wire        hvs_sck_dac; // HVS DAC serial clock
   wire        hvs_sck_adc; // HVS ADC serial clock
   wire        hvs_adc_test; // HVS ADC conversion test
   wire        hvs_adc_cs1_n; // HVS ADC chip select 1 (active low)
   
   assign HVS_MOSI = ((!HVS_CS0_N && hvs_mosi_dac) || (!HVS_CS1_N && hvs_mosi_adc)) && !(HVS_CS0_N && HVS_CS1_N);
   assign HVS_SCK =  ((!HVS_CS0_N && hvs_sck_dac) || (!HVS_CS1_N && hvs_sck_adc)) || (HVS_CS0_N && HVS_CS1_N) || hvs_adc_test;
   assign HVS_CS1_N = hvs_adc_cs1_n && !hvs_adc_test;
   
   ddc2_sockit_qsys_nios2 ddc2_sockit_qsys_nios2_u0(
						    .pclk_clk(proc_clk),
						    .pclk_reset_reset_n(proc_clk_rst_n),
						    .pef_in_writedata(proc_adc_datastream),
						    .pef_in_write(pef_wrreq),
						    .pef_in_waitrequest(pef_waitreq),
						    .cmdf_out_readdata(cmd_data),
						    .cmdf_out_read(cmd_rdreq),
						    .cmdf_out_waitrequest(cmd_waitreq),
						    .rspf_in_writedata(rsp_data),
						    .rspf_in_write(rsp_wrreq),
						    .rspf_in_waitrequest(rsp_waitreq),
						    .lclk_clk(proc_clk),
						    .lclk_reset_reset_n(proc_clk_rst_n),
						    .phf_in_writedata(phf_data),
						    .phf_in_write(phf_wrreq && !phf_waitreq),
						    .phf_in_waitrequest(phf_waitreq),
						    .spi_ddc_dac_MISO(qsys_ddc_dac_miso),
						    .spi_ddc_dac_MOSI(qsys_ddc_dac_mosi),
						    .spi_ddc_dac_SCLK(qsys_ddc_dac_sclk),
						    .spi_ddc_dac_SS_n(qsys_ddc_dac_ssn),
						    .spi_ddc_adc_MISO(qsys_ddc_adc_miso),
						    .spi_ddc_adc_MOSI(qsys_ddc_adc_mosi),
						    .spi_ddc_adc_SCLK(qsys_ddc_adc_sclk),
						    .spi_ddc_adc_SS_n(qsys_ddc_adc_ssn),
						    .spi_ddc_pt_MISO(qsys_ddc_pt_miso),
						    .spi_ddc_pt_MOSI(qsys_ddc_pt_mosi),
						    .spi_ddc_pt_SCLK(qsys_ddc_pt_sclk),
						    .spi_ddc_pt_SS_n(qsys_ddc_pt_ssn),
						    .hvs_hv_dac_ext_MISO(HVS_MISO),
						    .hvs_hv_dac_ext_MOSI(hvs_mosi_dac),
						    .hvs_hv_dac_ext_SCLK(hvs_sck_dac),
						    .hvs_hv_dac_ext_SS_n(HVS_CS0_N),
						    .hvs_hv_adc_ext_MISO(HVS_MISO),
						    .hvs_hv_adc_ext_MOSI(hvs_mosi_adc),
						    .hvs_hv_adc_ext_SCLK(hvs_sck_adc),
						    .hvs_hv_adc_ext_SS_n(hvs_adc_cs1_n),
						    .hvs_hv_enable_ext_export(HVS_HVEN),
						    .hvs_hv_adc_rdy_export(HVS_MISO),
						    .hvs_hv_adc_test_export(hvs_adc_test)   
						    );      
   
   //////////////////////////////////////////////////////////////////////////////////////
   // Some combinational outputs
   assign DDC_TRIG_OUT = |wff_wrreq; 
   assign DDC_RESET_ADC = 1'b0;
   assign LED2 = HVS_HVEN && HSMC_TEST_LED;
   assign LED3 = dt_trig_mode ? armed && tap_trig_en && !(|trig) && !(trig_test) : tap_trig_en && !(|trig) && !(trig_test);
   
   
endmodule
