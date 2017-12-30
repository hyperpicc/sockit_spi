////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  DMA (direct memory access) interface                                      //
//                                                                            //
//  Copyright (C) 2011  Iztok Jeras                                           //
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
// The DMA task protocol employ a handshaking mechanism. The data source sets //
// the valid signal (tsk_vld) and the data drain confirms the transfer by     //
// setting the ready signal (tsk_rdy).                                        //
//                                                                            //
//                       ----------   vld    ----------                       //
//                       )      S | ------>  | D      (                       //
//                       (      R |          | R      )                       //
//                       )      C | <------  | N      (                       //
//                       ----------   rdy    ----------                       //
//                                                                            //
// DMA task protocol:                                                         //
//                                                                            //
// The protocol uses a control (tsk_ctl) and a status (tsk_sts) signal. The   //
// control signal uses handshaking while the status signal does not. The      //
// control signal is a command from REG to DMA to start a DMA sequence.       //
//                                                                            //
// Control signal fields:                                                     //
// [31   ] - iod - command input/output direction (0 - input, 1 - output)     //
// [30: 0] - len - DMA sequence length in Bytes                               //
//                                                                            //
// The status signal is primarily used to control the command arbiter. While  //
// a DMA sequence is processing the DMA should have exclusive access to the   //
// command bus. The status signal is also connected to REG, so that the CPU   //
// can poll DMA status and interrupts can be generated.                       //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_dma #(
  // bus properties
  parameter ENDIAN = "BIG",  // endian options include "BIG", "LITTLE"
  // port widths
  parameter DW     =    32   // command data width
)(
  // AMBA AXI4
  axi4_if.m              axi,
  // configuration
  input  logic  [32-1:0] spi_cfg,
  // data streams
  sockit_spi_if.s        sdw,  // stream data write
  sockit_spi_if.d        sdr   // stream data read
);

////////////////////////////////////////////////////////////////////////////////
// data write channel                                                         //
////////////////////////////////////////////////////////////////////////////////

// read address options affect read data
always_ff @ (posedge axi.ACLK)
if (axi.AWVALID & axi.AWREADY) begin
  // store transfer ID
  axi.WID <= axi.AWID;
  // AXI4 write response depends on whether a supported request was made
  axi.WRESP <= (axi.WRSIZE <= axi4_pkg::int2SIZE(DW)) ? axi4_pkg::OKEY
                                                      : axi4_pkg::SLVERR;
end

// stream data write
assign sdw.vld = axi.WVALID;
assign sdw.dat = axi.WDATA ;
assign axi.WREADY = sdw.rdy;

////////////////////////////////////////////////////////////////////////////////
// data read channel                                                          //
////////////////////////////////////////////////////////////////////////////////

// read address options affect read data
always_ff @ (posedge axi.ACLK)
if (axi.ARVALID & axi.ARREADY) begin
  // store transfer ID
  axi.RID <= axi.ARID;
  // AXI4 read response depends on whether a supported request was made
  axi.RRESP <= (axi.ARSIZE <= axi4_pkg::int2SIZE(DW)) ? axi4_pkg::OKEY
                                                      : axi4_pkg::SLVERR;
end

// store transfer size 
always_ff @ (posedge axi.ACLK, negedge axi.ARESETn)
if (~axi.ARESETn) begin
  cnt <= 0;
end else begin
  if (axi.ARVALID & axi.ARREADY) begin
    cnt <= axi4_pkg::SIZE2int(axi.ARSIZE) - 1;
  end else if (axi.RVALID & axi.RREADY) begin
    cnt <= cnt - 1;
  end
end

// return active LAST at the end of the burst
always_ff @ (posedge axi.ACLK)
if (axi.ARVALID & axi.ARREADY) begin
  axi.RLAST <= ~|cnt;
end

// stream data read
assign axi.RVALID = sdr.vld;
assign axi.RDATA  = sdr.dat;
assign sdr.rdy = axi.RREADY;

endmodule: sockit_spi_dma
