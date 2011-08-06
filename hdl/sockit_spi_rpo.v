////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  repackaging output data (command protocol into queue protocol)            //
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

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Handshaking protocol:                                                      //
//                                                                            //
// Both the command and the queue protocol employ the same handshaking mech-  //
// anism. The data source sets the request signal (*_req) and the data drain  //
// confirms the transfer by setting the grant signal (*_grt).                 //
//                                                                            //
//                       ----------   req    ----------                       //
//                       )      S | ------>  | D      (                       //
//                       (      R |          | R      )                       //
//                       )      C | <------  | N      (                       //
//                       ----------   grt    ----------                       //
//                                                                            //
// Command protocol:                                                          //
//                                                                            //
// The command protocol packet transfer contains CDW=32 data bits (same as    //
// the CPU system bus) and CCO=11 control bits. Control word fields:          //
// [10: 6] - len - transfer length (in the range from 1 to CDW bits)          //
// [ 5: 0] -     - this fields have the same meaning as in the queue protocol //
//                                                                            //
// Queue protocol:                                                            //
//                                                                            //
// The queue protocol packet transfer contains QDW=4*SDW=4*8 data bits (num-  //
// ber of SPI data bits times serializer length) and QCO=10 control bits.     //
// Control word fields:                                                       //
// [ 9: 7] - len - transfer length (in the range from 1 to SDW bits)          //
// [    6] - lst - last tran. segment (used to size the input side packet)    //
// [ 5: 4] - iom - SPI data IO mode (0 - 3-wire)                              //
//               -                  (1 - SPI   )                              //
//               -                  (2 - dual  )                              //
//               -                  (3 - quad  )                              //
// [    3] - die - SPI data input enable                                      //
// [    2] - doe - SPI data output enable                                     //
// [    1] - sso - SPI slave select enable                                    //
// [    0] - cke - SPI clock enable                                           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_rpo #(
  // port widths
  parameter SDW     =            8,  // serial data register width
  parameter SDL     =  $clog2(SDW),  // serial data register width logarithm
  parameter CCO     =          5+6,  // command control output width
  parameter CDW     =           32,  // command data width
  parameter QCO     =        SDL+7,  // queue control output width
  parameter QDW     =        4*SDW   // queue data width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // command
  input  wire           cmd_req,  // request
  input  wire [CCO-1:0] cmd_ctl,  // control
  input  wire [CDW-1:0] cmd_dat,  // data
  output wire           cmd_grt,  // grant
  // queue
  output wire           que_req,  // request
  output wire [QCO-1:0] que_ctl,  // control
  output wire [QDW-1:0] que_dat,  // data
  input  wire           que_grt   // grant
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

wire           cmd_trn;  // command transfer

reg            cyc_run;  // counter run state
reg      [4:0] cyc_cnt;  // counter
wire     [4:0] cyc_nxt;  // counter next
wire [SDL-1:0] cyc_len;  // SPI transfer length
reg            cyc_lst;  // last piece
wire     [1:0] cyc_iom;  // SPI IO mode

reg  [CCO-6:0] cyc_ctl;  // control register
reg  [CDW-1:0] cyc_dat;  // data    register

wire           que_trn;  // queue transfer

////////////////////////////////////////////////////////////////////////////////
// repackaging function                                                       //
////////////////////////////////////////////////////////////////////////////////

function [4*SDW-1:0] rpk (
  input  [4*SDW-1:0] dat,
  input        [1:0] mod
);
  integer i;
begin
  for (i=0; i<SDW; i=i+1) begin
    case (mod)
      2'd0 : begin  // 3-wire
        rpk [4*SDW-1-i] = 1'b1;
        rpk [3*SDW-1-i] = 1'b1;
        rpk [2*SDW-1-i] = 1'b1;
        rpk [1*SDW-1-i] = dat [32-1-1*i];
      end
      2'd1 : begin  // SPI
        rpk [4*SDW-1-i] = 1'b1;
        rpk [3*SDW-1-i] = 1'b1;
        rpk [2*SDW-1-i] = 1'b1;
        rpk [1*SDW-1-i] = dat [32-1-1*i];
      end
      2'd2 : begin  // dual
        rpk [4*SDW-1-i] = 1'b1;
        rpk [3*SDW-1-i] = 1'b1;
        rpk [2*SDW-1-i] = dat [32-1-2*i];
        rpk [1*SDW-1-i] = dat [32-2-2*i];
      end
      2'd3 : begin  // quad
        rpk [4*SDW-1-i] = dat [32-1-4*i];
        rpk [3*SDW-1-i] = dat [32-2-4*i];
        rpk [2*SDW-1-i] = dat [32-3-4*i];
        rpk [1*SDW-1-i] = dat [32-4-4*i];
      end
    endcase
  end
end
endfunction

////////////////////////////////////////////////////////////////////////////////
// repackaging state machine                                                  //
////////////////////////////////////////////////////////////////////////////////

// command flow control
assign cmd_grt = ~cyc_run | que_grt & cyc_lst;
assign cmd_trn = cmd_req & cmd_grt;

// counter
always @(posedge clk, posedge rst)
if (rst) begin
  cyc_run <= 1'b0;
  cyc_lst <= 1'b0;
  cyc_cnt <= 5'd0;
end else begin
  if (cmd_trn) begin
    cyc_run <= 1'b1;
    cyc_lst <= cmd_ctl [6+:5] < SDW;
    cyc_cnt <= cmd_ctl [6+:5];
  end else if (que_trn) begin
    cyc_run <= ~cyc_lst;
    cyc_lst <= cyc_nxt < SDW;
    cyc_cnt <= cyc_nxt;
  end
end

// counter next
assign cyc_nxt = cyc_lst ? 5'd0 : cyc_cnt - SDW;

// SPI transfer length
assign cyc_len = cyc_lst ? cyc_cnt [SDL-1:0] : {SDL{1'b1}};

// SPI IO mode
assign cyc_iom = cyc_ctl [5:4];

// control and data registers
always @(posedge clk)
if (cmd_trn) begin
  cyc_ctl <= cmd_ctl [5:0];
  cyc_dat <= cmd_dat;
end else if (que_trn) begin
  case (cyc_iom)
    2'd0 : cyc_dat <= cyc_dat << 1*SDW;
    2'd1 : cyc_dat <= cyc_dat << 1*SDW;
    2'd2 : cyc_dat <= cyc_dat << 2*SDW;
    2'd3 : cyc_dat <= cyc_dat << 4*SDW;
  endcase
end

// queue control and data
assign que_ctl = {cyc_len, cyc_lst, cyc_ctl};
assign que_dat = rpk (cyc_dat, cyc_iom);

// queue flow control
assign que_req = cyc_run;
assign que_trn = que_req & que_grt;

endmodule
