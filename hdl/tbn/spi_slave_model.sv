////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) slave model                                      //
//                                                                            //
//  Copyright (C) 2011  Iztok Jeras                                           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  This HDL is free hardware: you can redistribute it and/or modify          //
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

module spi_slave_model #(
  parameter ARL = 1024   // array length
)(
  // configuration
  input wire [1:0] cfg_ckm,  // clock mode {CPOL, CPHA}
  input wire [1:0] cfg_iom,  // data mode (0-3wire, 1-SPI, 2-duo, 3-quad)
  input wire       cfg_oen,  // data output enable for half duplex modes
  input wire       cfg_dir,  // shift direction (0 - LSB first, 1 - MSB first)
  // SPI signals
  input wire       ss_n,     // slave select  (active low)
  input wire       sclk,     // serial clock
  inout wire       mosi,     // master output slave  input / SIO[0]
  inout wire       miso,     // maste   input slave output / SIO[1]
  inout wire       wp_n,     // write protect (active low) / SIO[2]
  inout wire       hold_n    // clock hold    (active low) / SIO[3]
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// system signals
wire          clk;    // local clock
wire          rst;    // local reset

// IO signal vectors
wire    [3:0] sig_i;  // inputs
reg     [3:0] sig_o;  // outputs
reg     [3:0] sig_e;  // enables

// clock period counters
integer       cnt_i;  // bit counter input
integer       cnt_o;  // bit counter output

// arrays
reg [0:ARL-1] ary_i;  // data array input
reg [0:ARL-1] ary_o;  // data array output

////////////////////////////////////////////////////////////////////////////////
// clock and reset                                                            //
////////////////////////////////////////////////////////////////////////////////

// local clock and reset
assign clk = sclk ^ cfg_ckm[1] ^ cfg_ckm[0];
assign rst = ss_n;

////////////////////////////////////////////////////////////////////////////////
// input write into array                                                     //
////////////////////////////////////////////////////////////////////////////////

// input clock period counter
always @ (posedge clk, posedge rst)
if (rst)  cnt_i <= 0;
else      cnt_i <= cnt_i + 1;

// input signal vector
assign sig_i = {hold_n, wp_n, miso, mosi};

// input array
always @ (posedge clk)
if (~rst) case (cfg_iom)
  2'd0 :  if (~cfg_oen)  ary_i [  cnt_i   ] <= sig_i[  0];
  2'd1 :                 ary_i [  cnt_i   ] <= sig_i[  0];
  2'd2 :  if (~cfg_oen)  ary_i [2*cnt_i+:2] <= sig_i[1:0];
  2'd3 :  if (~cfg_oen)  ary_i [4*cnt_i+:4] <= sig_i[3:0];
endcase

////////////////////////////////////////////////////////////////////////////////
// output read from array                                                     //
////////////////////////////////////////////////////////////////////////////////

// clock period counter
always @ (negedge clk, posedge rst)
if (rst)  cnt_o <= 0;
else      cnt_o <= cnt_o + |cnt_i;

// output signal vector
always @ (*)
if (rst)  sig_o = 4'bxxxx;
else case (cfg_iom)
  2'd0 :  sig_o = {2'bxx, 1'bx, ary_o [  cnt_o   ]      };
  2'd1 :  sig_o = {2'bxx,       ary_o [  cnt_o   ], 1'bx};
  2'd2 :  sig_o = {2'bxx,       ary_o [2*cnt_o+:2]      };
  2'd3 :  sig_o = {             ary_o [4*cnt_o+:4]      };
endcase

// output enable signal vector
always @ (*)
if (rst)  sig_e = 4'b0000;
else case (cfg_iom)
  2'd0 :  sig_e = {2'b0, 1'b0, cfg_oen      };
  2'd1 :  sig_e = {2'b0,       cfg_oen, 1'b0};
  2'd2 :  sig_e = {2'b0,    {2{cfg_oen}}    };
  2'd3 :  sig_e = {         {4{cfg_oen}}    };
endcase

// output drivers
assign mosi   = sig_e [0] ? sig_o [0] : 1'bz;
assign miso   = sig_e [1] ? sig_o [1] : 1'bz;
assign wp_n   = sig_e [2] ? sig_o [2] : 1'bz;
assign hold_n = sig_e [3] ? sig_o [3] : 1'bz;

endmodule
