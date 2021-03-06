////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) testbench                                        //
//                                                                            //
//  Copyright (C) 2008-2011  Iztok Jeras                                      //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  This RTL is free hardware: you can redistribute it and/or modify          //
//  it under the terms of the GNU Lesser General Public License               //
//  as published by the Free Software Foundation, either                      //
//  version 3 of the License, or (at your option) any later version.          //
//                                                                            //
//  This RTL is distributed in the hope that it will be useful,               //
//  but WITHOUT ANY WARRANTY; without even the implied warranty of            //
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             //
//  GNU General Public License for more details.                              //
//                                                                            //
//  You should have received a copy of the GNU General Public License         //
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.     //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

`timescale 1us / 1ns

module spi_tb ();

////////////////////////////////////////////////////////////////////////////////
// local parameters and signals                                               //
////////////////////////////////////////////////////////////////////////////////

// SPI parameters
localparam SSW = 8;  // slave select width
localparam SDW = 8;  // serial data register width
// clock domain crossing enable
localparam CDC = 1'b1;

// length of test array/string
localparam ARL = 8*256;
localparam ADW = 32;
localparam XAW = 24;
localparam STL =   256;

localparam DMA_SIZ = 1024;

////////////////////////////////////////////////////////////////////////////////
// master instance signals                                                    //
////////////////////////////////////////////////////////////////////////////////

// system signals
reg clk_cpu, rst_cpu;
reg clk_spi, rst_spi;

// AXI4 interfaces
axi4_lite_if #(.AW ( 4), .DW (32)) axi_reg (.ACLK (clk_cpu), .ARESETn (rst_cpu));
axi4_if      #(.AW (12), .DW (32)) axi_dma (.ACLK (clk_cpu), .ARESETn (rst_cpu));
axi4_if      #(.AW (24), .DW (32)) axi_xip (.ACLK (clk_cpu), .ARESETn (rst_cpu));

// DMA memory
//reg  [DDW-1:0] dma_mem [0:DMA_SIZ-1];

// SPI interface
spi_if spi();

////////////////////////////////////////////////////////////////////////////////
// SPI related signals                                                        //
////////////////////////////////////////////////////////////////////////////////

// SPI signals
wire [SSW-1:0] spi_ss_n;
wire           spi_sclk;
wire           spi_mosi;
wire           spi_miso;
wire           spi_wp_n;
wire           spi_hold_n;

// SPI slave model configuration
reg      [1:0] tst_ckm;  // mode clock {CPOL, CPHA}
reg      [1:0] tst_iom;  // mode data (0-3wire, 1-SPI, 2-duo, 3-quad)
reg            tst_oen;  // data output enable for half duplex modes
reg            tst_dir;  // shift direction (0 - LSB first, 1 - MSB first)

////////////////////////////////////////////////////////////////////////////////
// testbench specific signals                                                 //
////////////////////////////////////////////////////////////////////////////////

// error counter
integer        tst_tmp;
integer        tst_err;

// string (output/input) for testing
reg  [0:ARL-1] tst_txt = {"Hello world!", {ARL-8*12{1'bx}}};
reg  [0:ARL-1] tst_aro;
reg  [0:ARL-1] tst_ari;

// test write/read data
reg  [ADW-1:0] tst_wdt;
reg  [ADW-1:0] tst_rdt;

// test name (status descriptor)
reg [64*8-1:0] tst_nme;

// for loop variables
integer i, j, k, l;

// request for a dump file
initial begin
  $dumpfile("spi.fst");
  $dumpvars(0, spi_tb);
end

////////////////////////////////////////////////////////////////////////////////
// clock sources                                                              //
////////////////////////////////////////////////////////////////////////////////

// TODO enable asynchronous clocking

// CPU clock generation
initial    clk_cpu <= 1'b1;
always  #5 clk_cpu <= ~clk_cpu;

// SPI master clock generation
initial    clk_spi <= 1'b1;
always  #5 clk_spi <= ~clk_spi;

////////////////////////////////////////////////////////////////////////////////
// testbench                                                                  //
////////////////////////////////////////////////////////////////////////////////

// test sequence
initial begin
  // reset generation
  rst_cpu  = 1'b1;
  rst_spi  = 1'b1;
  repeat (2) @ (posedge clk_cpu); #1;
  rst_cpu  = 1'b0;
  rst_spi  = 1'b0;

  IDLE (4);                // few clock periods

//`define SPI_TB_DEBUG
`ifdef SPI_TB_DEBUG

  // TODO
  test_spi_half_duplex (1'b1, 0, 0, 64, 5, 7, tst_tmp);
  tst_err = tst_err + tst_tmp;

`else

  // check bit sized transfers up to SDW limit
  for (i=0; i<4; i=i+1) begin           // loop clock modes
    for (j=0; j<4; j=j+1) begin         // loop IO modes
      l = (j==3) ? 4 : (j==2) ? 2 : 1;  // number of transferred bits per clock period
      for (k=l; k<32; k=k+l) begin      // loop transfer size
        test_spi_half_duplex (1'b1, i[1:0], j[1:0], k, 0, 1, tst_tmp);
        tst_err = tst_err + tst_tmp;
      end
    end
  end

  // check SDW sized transfers up to SDW limit
  for (i=0; i<4; i=i+1) begin        // loop clock_modes
    for (j=0; j<4; j=j+1) begin      // loop IO modes
      for (k=1; k<=12; k=k+1) begin  // loop transfer size
        test_spi_half_duplex (1'b1, i[1:0], j[1:0], k*SDW, 0, 1, tst_tmp);
        tst_err = tst_err + tst_tmp;
      end
    end
  end

  // test Flash access using register interface
  test_flash_reg;
  // test Flash access using DMA
  test_flash_dma;

`endif

  tst_nme = "END";
  IDLE (16);               // few clock periods

  $finish;  // end simulation
end

// end test on timeout
initial begin
  repeat (50000) @ (posedge clk_cpu);
  $finish;  // end simulation
end

////////////////////////////////////////////////////////////////////////////////
// test SPI slave half duplex modes                                           //
////////////////////////////////////////////////////////////////////////////////

task test_spi_half_duplex (
  // configuration
  input          cfg_dir,  // shift direction (0 - LSB first, 1 - MSB first)
  input    [1:0] cfg_ckm,  // clock mode {CPOL, CPHA}
  input    [1:0] cfg_iom,  // data mode (0-3wire, 1-SPI, 2-duo, 3-quad)
  input  integer cfg_num,  // transfer size in number in bits
  input  integer cfg_dly,  // delay time before/betwee/after transfer units
  input  integer cfg_idl,  // idle time between slave selects
  // error status
  output integer tst_err
);
  // local variables
  reg      [4:0] cfg_len;          // transfer unit length (clock periods)
  integer        var_tmp;          // temporal variable
  integer        var_num [0:255];  // transfer unit length table (data bits)
  integer        var_trn;          // transfer unit number (table size)
  integer        var_cnw;          // transfer unit counter (writes)
  integer        var_cnr;          // transfer unit counter (reads)
begin
  // initialize error counter
  tst_err = 0;

  // configure SPI slave
  tst_ckm = cfg_ckm;
  tst_iom = cfg_iom;
  tst_dir = cfg_dir;

  // set test name
  tst_nme = {"half duplex:", " dir=", "0" + cfg_dir
                           , " ckm=", "0" + cfg_ckm
                           , " iom=", "0" + cfg_iom
                           , " idl=", "0" + cfg_idl
                           , " num=", int2str(cfg_num)};

  // create a table of transfer lengths
  for (var_trn=0; var_trn*32<cfg_num; var_trn=var_trn+1) begin
    var_num [var_trn] = (cfg_num - var_trn*32) > 32 ? 32 : (cfg_num - var_trn*32);
  end
  
  // write configuration
  IOWR (0, 32'h020100cc | cfg_ckm);

  // clear slave arrays
  ary_clr (slave_spi.ary_i, ARL);
  ary_clr (slave_spi.ary_o, ARL);

  // set master output array
  ary_clr (tst_aro, ARL);
  ary_cpy (tst_aro, tst_txt, cfg_num);

  // disable slave output
  tst_oen = 1'b0;

  for (var_cnw=0; var_cnw<var_trn; var_cnw=var_cnw+1) begin
    // write data
    tst_wdt = tst_aro[32*var_cnw+:32];
    IOWR (3, tst_wdt);
    if (cfg_dly)
    IOWR (2, iowr_cmd_dly (cfg_dly));
    IOWR (2, iowr_cmd_dto (var_num[var_cnw], cfg_iom));
  end
  if (cfg_dly)
  IOWR (2, iowr_cmd_dly (cfg_dly));
  IOWR (2, iowr_cmd_idl (cfg_idl));

  IDLE (32);  // wait for write transfers to finish

  // check if read data is same as written data
  IDLE (1);
  tst_err = tst_err + ary_cmp (tst_aro, slave_spi.ary_i, ARL);
  IDLE (1);

  // clear master arrays
  ary_clr (tst_ari, ARL);
  ary_clr (tst_aro, ARL);

  // set slave output array
  ary_clr (slave_spi.ary_o, ARL);
  ary_cpy (slave_spi.ary_o, tst_txt, cfg_num);

  // enable slave output
  tst_oen = 1'b1;

  var_cnw = 0;
  for (var_cnr=0; var_cnr<var_trn; var_cnr=var_cnr+1) begin
    if (var_cnw == 0) begin
      IOWR (2, iowr_cmd_dti (var_num[var_cnw], cfg_iom));
      var_cnw=var_cnw+1;
    end
    if (var_cnr < var_trn-1) begin
      IOWR (2, iowr_cmd_dti (var_num[var_cnw], cfg_iom));
      var_cnw=var_cnw+1;
    end else begin
      IOWR (2, iowr_cmd_idl (cfg_idl));
    end
    // read flash data
    IORD (3, tst_rdt);
    // TODO, find some more elegant code to do this
    for (var_tmp=0; var_tmp<var_num[var_cnr]; var_tmp=var_tmp+1)
      tst_ari [32*var_cnr+var_tmp] = tst_rdt [var_num[var_cnr]-1-var_tmp];
  end

  // check if read data is same as written data
  IDLE (1);
  tst_err = tst_err + ary_cmp (tst_ari, slave_spi.ary_o, ARL);
  IDLE (1);
end
endtask

// command
function [31:0] iowr_cmd (
  input   [4:0] len,  // transfer length (in the range from 1 to SDW bits)
  input         pkm,  // packeting mode (0 - remainder last, 1 - remainder first)
  input   [1:0] iom,  // SPI data mode (0-3wire, 1-SPI, 2-duo, 3-quad)
  input         die,  // SPI data input enable
  input         doe,  // SPI data output enable
  input         sso,  // SPI slave select enable
  input         cke   // SPI clock enable
);
  iowr_cmd = {20'hxxxxx, len, 1'b0, pkm, iom, die, doe, sso, cke};
endfunction

// command (idle with slave select inactive)
function [31:0] iowr_cmd_idl (
  input integer num   // clock periods
);  //                         len,           pkm, iom, die, doe, sso, cke
  iowr_cmd_idl = iowr_cmd (num, 'b0, 'd1, 'b0, 'b0, 'b0, 'b0);
endfunction

// command (delay with slave select active)
function [31:0] iowr_cmd_dly (
  input integer num   // clock periods
);  //                         len          , pkm, iom, die, doe, sso, cke
  iowr_cmd_dly = iowr_cmd (num, 'b0, 'd1, 'b0, 'b0, 'b1, 'b0);
endfunction

// command (data transfer output)
function [31:0] iowr_cmd_dto (
  input integer num,  // transfer size in number in bits
  input   [1:0] iom   // SPI data mode (0-3wire, 1-SPI, 2-duo, 3-quad)
);  //                         len          , pkm, iom, die, doe, sso, cke
  iowr_cmd_dto = iowr_cmd (num, 'b0, iom, 'b0, 'b1, 'b1, 'b1);
endfunction

// command (data transfer output)
function [31:0] iowr_cmd_dti (
  input integer num,  // transfer size in number in bits
  input   [1:0] iom   // SPI data mode (0-3wire, 1-SPI, 2-duo, 3-quad)
);  //                         len          , pkm, iom, die, doe, sso, cke
  iowr_cmd_dti = iowr_cmd (num, 'b1, iom, 'b1, 'b0, 'b1, 'b1);
endfunction

// command (data transfer duplex)
function [31:0] iowr_cmd_dtd (
  input integer num,  // transfer size in number in bits
  input         pkm   // packeting mode (0 - remainder last, 1 - remainder first)
);  //                         len          , pkm, iom, die, doe, sso, cke
  iowr_cmd_dtd = iowr_cmd (num, pkm, 'd1, 'b1, 'b1, 'b1, 'b1);
endfunction

////////////////////////////////////////////////////////////////////////////////
// test Flash access using register interface                                 //
////////////////////////////////////////////////////////////////////////////////

task test_flash_reg;
begin
  // TODO, should be tested in clock mode 0 and 3

  IOWR (0, 32'h040100cc);  // write configuration

  // test write to flash
  IDLE (16);  tst_nme = "write 12B";

    // write data
    IOWR (3, 32'h02000000);  // write data    register
    IOWR (2, 32'h00001f17);  // write control register (32bit write)
    for (i=0; i<3; i=i+1) begin
    tst_wdt = tst_aro[i*32+:32];
    IOWR (3, tst_wdt     );  // write flash data
    IOWR (2, 32'h00001f17);  // write control register (32bit write)
    end
    IOWR (2, 32'h00000010);  // write control register (cycle end)

  // test read from flash
  IDLE (16);  tst_nme = "read 12B";

    // read data
    IOWR (3, 32'h0b5a0000);  // write data    register
    IOWR (2, 32'h00001f17);  // write control register (32bit write)
    IOWR (2, 32'h00000713);  // write control register ( 8bit idle)
    IOWR (2, 32'h00001f1b);  // write control register (32bit read)
    for (i=0; i<2; i=i+1) begin
    IOWR (2, 32'h00001f1b);  // write control register (32bit read)
    IORD (3, tst_rdt     );  // read flash data
    tst_ari[i*32+:32] = tst_rdt;
    end
    IOWR (2, 32'h00000010);  // write control register (cycle end)
    IORD (3, tst_rdt     );  // read flash data
    tst_ari[i*32+:32] = tst_rdt;

  // check if read data is same as written data
  IDLE (16);  tst_err = tst_err + (tst_ari != tst_aro);
end
endtask

////////////////////////////////////////////////////////////////////////////////
// test Flash access using register interface                                 //
////////////////////////////////////////////////////////////////////////////////

task test_flash_dma;
begin
  IOWR (0, 32'h040100cc);  // write configuration

  // test write to SPI Flash
  IDLE (16);  tst_nme = "DMA -> SPI";

    IOWR (3, 32'h02000000);  // write data    register
    IOWR (2, 32'h00001f17);  // write control register (32bit write)
    IOWR (5, 32'h80000003);  // request a DMA read, SPI write transfer
    POLL (5, 32'h80000000);  // wait for DMA to finish
    IOWR (2, 32'h00000010);  // write control register (cycle end)

  // test read from SPI Flash
  IDLE (16);  tst_nme = "SPI -> DMA";

    IOWR (3, 32'h0b5a0000);  // write data    register
    IOWR (2, 32'h00001f17);  // write control register (32bit write)
    IOWR (2, 32'h00000713);  // write control register ( 8bit idle)
    IOWR (5, 32'h00000003);  // request a SPI read, DMA write transfer
    POLL (5, 32'h80000000);  // wait for DMA to finish
    IOWR (2, 32'h00000010);  // write control register (cycle end)

  // extra idle time before next test
  IDLE (100);
end
endtask

//  IOWR (3, 32'h3b5a0000);  // write data    register (command fast read dual output)
//  IOWR (2, 32'h00174007);  // write control register (enable a chip and start a 4 byte write)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h00104001);  // write control register (enable a chip and start a 1 byte dummy)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h00388007);  // write control register (enable a chip and start a 4 byte read)
//  POLL (2, 32'h0000000f);
//  IORD (3, tst_rdt);       // read flash data
//
//  IDLE (16);               // few clock periods
//
//  IOWR (3, 32'h6b5a0000);  // write data    register (command fast read quad output)
//  IOWR (2, 32'h00174007);  // write control register (enable a chip and start a 4 byte write)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h00104001);  // write control register (enable a chip and start a 1 byte dummy)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h0038c007);  // write control register (enable a chip and start a 4 byte read)
//  POLL (2, 32'h0000000f);
//  IORD (3, tst_rdt);       // read flash data
//
//  IDLE (16);               // few clock periods
//
//  IOWR (3, 32'hbb000000);  // write data    register (command fast read dual IO)
//  IOWR (2, 32'h00174001);  // write control register (send command)
//  POLL (2, 32'h0000000f);
//  IOWR (3, 32'h5a000000);  // write data    register (address and dummy)
//  IOWR (2, 32'h00138007);  // write control register (send address and dummy)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h00388007);  // write control register (4 byte read)
//  POLL (2, 32'h0000000f);
//  IORD (3, tst_rdt);       // read flash data
//
//  IDLE (16);               // few clock periods
//
//  IOWR (3, 32'heb000000);  // write data    register (command fast read quad IO)
//  IOWR (2, 32'h00174001);  // write control register (send command)
//  POLL (2, 32'h0000000f);
//  IOWR (3, 32'h5a000000);  // write data    register (address and dummy)
//  IOWR (2, 32'h0017c007);  // write control register (send address and dummy)
//  POLL (2, 32'h0000000f);
//  IOWR (2, 32'h0038c007);  // write control register (4 byte read)
//  POLL (2, 32'h0000000f);
//  IORD (3, tst_rdt);       // read flash data
//
//  IDLE (16);               // few clock periods
//
//  IOWR (1, 32'h00000001);  // enable XIP
//
//  xip_cyc (0, 24'h000000, 4'hf, 32'hxxxxxxxx, data);  // read data from XIP port

////////////////////////////////////////////////////////////////////////////////
// array/string manipulation                                                 //
////////////////////////////////////////////////////////////////////////////////

// conversion from integer to string
function automatic [0:3*8-1] int2str (input integer num);
  integer n;
begin
  int2str [0*8+:8] = "0" + num / 100 % 10;
  int2str [1*8+:8] = "0" + num /  10 % 10;
  int2str [2*8+:8] = "0" + num /   1 % 10;
end
endfunction

// array bit by bit comparator (returns number of differing bits)
function automatic integer ary_cmp (
  input [0:ARL-1] ar0,  // array 0
  input [0:ARL-1] ar1,  // array 1
  input integer   num   // number of bits to compare
);
  integer n;
begin
  ary_cmp = 0;
  for (n=0; n<num; n=n+1)  ary_cmp = ary_cmp + (ar0 [n] !== ar1 [n]);
end
endfunction

// array clear (returns number of cleared bits)
task automatic ary_clr (
  inout [0:ARL-1] ary,  // array
  input integer   num   // number of bits to clear
);
  integer n;
begin
  for (n=0; n<num; n=n+1)  ary [n] = 1'bx;
end
endtask

// array copy (returns number of differing bits)
task automatic ary_cpy (
  inout [0:ARL-1] ard,  // array source
  input [0:ARL-1] ars,  // array destination
  input integer   num   // number of bits to copy
);
  integer n;
begin
  for (n=0; n<num; n=n+1)  ard [n] = ars [n];
end
endtask

////////////////////////////////////////////////////////////////////////////////
// register bus tasks                                                         //
////////////////////////////////////////////////////////////////////////////////

//// IO register write
//task IOWR (input [AAW-1:0] adr,  input [ADW-1:0] wdt);
//  reg [ADW-1:0] rdt;
//begin
//  reg_cyc (1'b1, adr, 4'hf, wdt, rdt);
//end
//endtask
//
//// IO register read
//task IORD (input [AAW-1:0] adr, output [ADW-1:0] rdt);
//begin
//  reg_cyc (1'b0, adr, 4'hf, {ADW{1'bx}}, rdt);
//end
//endtask
//
//// polling for end of cycle
//task POLL (input [AAW-1:0] adr,  input [ADW-1:0] msk);
//  reg [ADW-1:0] rdt;
//begin
//  rdt = msk;
//  while (rdt & msk)
//  IORD (adr, rdt);
//end
//endtask
//
//// idle for a specified number of clock periods
//task IDLE (input integer num);
//begin
//  repeat (num) @ (posedge clk_cpu);
//end
//endtask

////////////////////////////////////////////////////////////////////////////////
// XIP bus tasks                                                              //
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// DMA memory model                                                           //
////////////////////////////////////////////////////////////////////////////////

// initializing memory contents
//initial  $readmemh("dma_mem.hex", dma_mem);

////////////////////////////////////////////////////////////////////////////////
// SPI controller master instance                                             //
////////////////////////////////////////////////////////////////////////////////

sockit_spi #(
  .XAW      (XAW),
  .SSW      (SSW),
  .CDC      (CDC)
) sockit_spi (
  // system signals (used by the CPU bus interface)
  .clk_spi  (clk_spi),
  .rst_spi  (rst_spi),
  // AXI4 interfaces
  .axi_reg  (axi_reg),
  .axi_dma  (axi_dma),
  .axi_xip  (axi_xip),
  // SPI signals (should be connected to tristate IO pads)
  .spi_inf  (spi)
);

////////////////////////////////////////////////////////////////////////////////
// SPI master tristate arrays                                                 //
////////////////////////////////////////////////////////////////////////////////

// clock
bufif1 spi_clk_b  (spi_sclk, spi.clk_o, spi.clk_e);
assign spi.clk_i = spi_sclk;

// data
bufif1 spi_sio_b [3:0] ({spi_hold_n, spi_wp_n, spi_miso, spi_mosi}, spi.sio_o, spi.sio_e);
assign spi.sio_i =      {spi_hold_n, spi_wp_n, spi_miso, spi_mosi};

// slave select (active low)
bufif1 spi_ssn_b [SSW-1:0] (spi_ss_n, ~spi.ssn_o, spi.ssn_e);
assign spi.ssn_i =          spi_ss_n;

////////////////////////////////////////////////////////////////////////////////
// SPI slave (serial Flash)                                                   //
////////////////////////////////////////////////////////////////////////////////

// loopback for debug purposes
assign spi_miso = ~spi_ss_n[0] ? spi_mosi : 1'bz;

// SPI slave model
spi_slave_model #(
  .ARL       (ARL)
) slave_spi (
  // configuration 
  .cfg_ckm   (tst_ckm),
  .cfg_iom   (tst_iom),
  .cfg_oen   (tst_oen),
  .cfg_dir   (tst_dir),
  // SPI signals
  .ss_n      (spi_ss_n[1]),
  .sclk      (spi_sclk),
  .mosi      (spi_mosi),
  .miso      (spi_miso),
  .wp_n      (spi_wp_n),
  .hold_n    (spi_hold_n)
);

// SPI Flash model
spi_flash_model #(
  .DIOM      (2'd1),
  .MODE      (2'd0)
) slave_flash (
  .ss_n      (spi_ss_n[2]),
  .sclk      (spi_sclk),
  .mosi      (spi_mosi),
  .miso      (spi_miso),
  .wp_n      (spi_wp_n),
  .hold_n    (spi_hold_n)
);

//// Spansion serial Flash
//s25fl129p00 #(
//  .mem_file_name ("none")
//) Flash_1 (
//  .SCK     (spi_sclk),
//  .SI      (spi_mosi),
//  .CSNeg   (spi_ss_n[1]),
//  .HOLDNeg (spi_hold_n),
//  .WPNeg   (spi_wp_n),
//  .SO      (spi_miso)
//);
//
//// Spansion serial Flash
//s25fl032a #(
//  .mem_file_name ("none")
//) Flash_2 (
//  .SCK     (spi_sclk),
//  .SI      (spi_mosi),
//  .CSNeg   (spi_ss_n[2]),
//  .HOLDNeg (1'b1),
//  .WNeg    (1'b1),
//  .SO      (spi_miso)
//);
//
//// Numonyx serial Flash
//m25p80 
//Flash_3 (
//  .c         (spi_sclk),
//  .data_in   (spi_mosi),
//  .s         (spi_ss_n[3]),
//  .w         (1'b1),
//  .hold      (1'b1),
//  .data_out  (spi_miso)
//);
//defparam Flash.mem_access.initfile = "hdl/bench/numonyx/initM25P80.txt";

endmodule: spi_tb
