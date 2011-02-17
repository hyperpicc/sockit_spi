////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  XIP (execute in place) engine                                             //
//                                                                            //
//  Copyright (C) 2008  Iztok Jeras                                           //
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

module sockit_spi_xip #(
  parameter XAW = 24,                // bus address width
  parameter NOP = 32'h00000000       // no operation instruction (returned on error)
)(
  // system signals
  input  wire           clk,         // clock
  input  wire           rst,         // reset
  // input bus (XIP requests)
  input  wire           bsi_wen,     // write enable
  input  wire           bsi_ren,     // read enable
  input  wire [XAW-1:0] bsi_adr,     // address
  input  wire    [31:0] bsi_wdt,     // write data
  output wire    [31:0] bsi_rdt,     // read data
  output reg            bsi_wrq,     // wait request
  // output bus (interface to SPI master registers)
  output reg            bso_wen,     // write enable
  output reg            bso_ren,     // read enable
  output reg            bso_adr,     // address
  output reg     [31:0] bso_wdt,     // write data
  input  wire    [31:0] bso_rdt,     // read data
  input  wire           bso_wrq,     // wait request
  // configuration
  input  wire [XAW-1:8] xip_adr,     // address offset
  // status
  output wire [XAW-1:8] xip_err      // error interrupt
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// state names
localparam IDL_RST = 4'h0;  // idle, reset
localparam CMD_WDT = 4'h1;  // command write (load buffer)
localparam CMD_CTL = 4'h2;  // command control (start cycle)
localparam CMD_STS = 4'h3;  // command status (wait for cycle end)
localparam DAT_CTL = 4'h4;  // data control (start cycle)
localparam DAT_RDT = 4'h5;  // data read (read buffer)

// XIP state machine status
reg            xip_cyc;  // cycle
reg      [2:0] xip_fsm;  // current state

// address adder
reg  [XAW-1:0] adr_reg;  // input address register
wire [XAW-1:0] adr_sum;  // input address + offset address

////////////////////////////////////////////////////////////////////////////////
// state machine                                                              //
////////////////////////////////////////////////////////////////////////////////

always @ (posedge clk, posedge rst)
if (rst) begin
  bsi_wrq <= 1'b1;  // there is no data available initially
  bso_wen <= 1'b0;
  bso_ren <= 1'b0;
  bso_adr <= 1'h0;
  bso_wdt <= 32'h000000;
  xip_fsm <= IDL_RST;
end else begin
  case (xip_fsm)
    IDL_RST : begin
      if (bsi_ren) begin
        bsi_wrq <= 1'b1;
        bso_wen <= 1'b1;
        bso_ren <= 1'b0;
        bso_adr <= 1'b0;
        bso_wdt <= {8'h0b, bsi_adr};
        xip_fsm <= CMD_WDT;
      end
    end
    CMD_WDT : begin
      if (bsi_ren) begin
        bsi_wrq <= 1'b1;
        bso_wen <= 1'b1;
        bso_ren <= 1'b0;
        bso_adr <= 1'b1;
        bso_wdt <= 32'h001f_100a;
        xip_fsm <= CMD_CTL;
      end
    end
    CMD_CTL : begin
      if (bsi_ren) begin
        bsi_wrq <= 1'b0;
        bso_wen <= 1'b0;
        bso_ren <= 1'b0;
        bso_adr <= 1'b1;
        bso_wdt <= 32'hxxxx_xxxx;
        xip_fsm <= |(bso_rdt & 32'h0000_c0000) ? CMD_CTL : CMD_STS;
      end
    end
    CMD_STS : begin
      if (bsi_ren) begin
        bsi_wrq <= 1'b1;
        bso_wen <= 1'b1;
        bso_ren <= 1'b0;
        bso_adr <= 1'b1;
        bso_wdt <= 32'h0038_1008;
        xip_fsm <= CMD_CTL;
      end
    end
    DAT_CTL : begin
      if (bsi_ren) begin
        bsi_wrq <= 1'b0;
        bso_wen <= 1'b0;
        bso_ren <= 1'b0;
        bso_adr <= 1'b1;
        bso_wdt <= 32'hxxxx_xxxx;
        xip_fsm <= |(bso_rdt & 32'h0000_c0000) ? CMD_CTL : CMD_STS;
      end
    end
    DAT_RDT : begin
        bsi_wrq <= 1'b0;
        bso_wen <= 1'b0;
        bso_ren <= 1'b0;
        bso_adr <= 1'b0;
        bso_wdt <= 32'hxxxx_xxxx;
        xip_fsm <= IDL_RST;
    end
  endcase
end


endmodule
