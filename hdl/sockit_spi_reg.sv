////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  memory mapped configuration, control and status registers                 //
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
//  Address space                                                             //
//                                                                            //
//  adr | reg name, short description                                         //
// -----+-------------------------------------------------------------------- //
//  0x0 | spi_cfg - SPI configuration                                         //
//  0x1 | spi_par - SPI parameterization (synthesis parameters, read only)    //
//  0x2 | spi_ctl - SPI control/status                                        //
//  0x3 | spi_dat - SPI data                                                  //
//  0x4 | spi_irq - SPI interrupts                                            //
//  0x5 | dma_ctl - DMA control/status                                        //
//  0x6 | adr_rof - address read  offset                                      //
//  0x7 | adr_wof - address write offset                                      //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Configuration register                                                     //
//                                                                            //
// Reset values of each bit in the configuration register are defined by the  //
// CFG_RST[31:0] parameter, another parameter CFG_MSK[31:0] defines which     //
// configuration field is read/ write (mask=0) and which are read only, fixed //
// at the reset value (mask=0).                                               //
//                                                                            //
// Configuration register fields:                                             //
// [31:24] - sss - slave select selector                                      //
// [23:17] - sss - reserved (for configuring XIP for specific SPI devices)    //
// [   16] - end - bus endianness (0 - little, 1 - big) for XIP, DMA          //
// [15:11] - dly - SPI IO output to input switch delay (1 to 32 clk periods)  //
// [   10] - prf - read prefetch (0 - single, 1 - double) for DMA slave mode  //
// [ 9: 8] - bts - bus transfer size (0 - 1 byte  ) for DMA slave mode        //
//               -                   (1 - 2 bytes )                           //
//               -                   (2 - reserved)                           //
//               -                   (3 - 4 bytes )                           //
// [    7] - m_s - SPI bus mode (0 - slave, 1 - master)                       //
// [    6] - dir - shift direction (0 - LSB first, 1 - MSB first)             //
// [ 5: 4] - iom - SPI data IO mode (0 - 3-wire) for XIP, DMA, slave mode     //
//               -                  (1 - SPI   )                              //
//               -                  (2 - dual  )                              //
//               -                  (3 - quad  )                              //
// [    3] - soe - slave select output enable                                 //
// [    2] - coe - clock output enable                                        //
// [    1] - pol - clock polarity                                             //
// [    0] - pha - clock phase                                                //
//                                                                            //
// Slave select selector fields enable the use of each of up to 8 slave       //
// select signals, so that it is possible to enable more than one lave at the //
// same time (broadcast mode).                                                //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Parameterization register:                                                 //
//                                                                            //
// The parameterization register holds parameters, which specify what         //
// functionality is enabled in the module at compile time.                    //
//                                                                            //
// Parameterization register fields:                                          //
// [ 7: 6] - ffo - clock domain crossing FIFO input  size                     //
// [ 5: 4] - ffo - clock domain crossing FIFO output size                     //
// [    3] - ??? - TODO                                                       //
// [ 2: 0] - ssn - number of slave select ports (from 1 to 8 signals)         //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi_reg #(
  // configuration (register reset values and masks)
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter ADR_ROF = 32'h00000000,  // address write offset
  parameter ADR_WOF = 32'h00000000,  // address read  offset
  // port widths
  parameter XAW     =           24,  // XIP address width
  parameter CCO     =          5+7,  // command control output width
  parameter CCI     =            4,  // command control  input width
  parameter CDW     =           32   // command data width
)(
  // system signals (used by the CPU interface)
  input  logic           clk,      // clock for CPU interface
  input  logic           rst,      // reset for CPU interface
  // bus interface
  input  logic           reg_wen,  // write enable
  input  logic           reg_ren,  // read enable
  input  logic     [2:0] reg_adr,  // address
  input  logic    [31:0] reg_wdt,  // write data
  output logic    [31:0] reg_rdt,  // read data
  output logic           reg_wrq,  // wait request
  output logic           reg_err,  // error response
  output logic           reg_irq,  // interrupt request
  // SPI/XIP/DMA configuration
  output logic    [31:0] spi_cfg,  // configuration register
  // address offsets
  output logic    [31:0] adr_rof,  // address read  offset
  output logic    [31:0] adr_wof,  // address write offset
  // command output
  output logic           cmo_vld,  // valid
  output logic [CCO-1:0] cmo_ctl,  // control
  output logic [CDW-1:0] cmo_dat,  // data
  input  logic           cmo_rdy,  // ready
  // command input
  input  logic           cmi_vld,  // valid
  input  logic [CCI-1:0] cmi_ctl,  // control
  input  logic [CDW-1:0] cmi_dat,  // data
  output logic           cmi_rdy,  // ready
  // DMA task interface
  output logic           tsk_vld,  // DMA valid
  output logic    [31:0] tsk_ctl,  // DMA control
  input  logic    [31:0] tsk_sts,  // DMA status
  input  logic           tsk_rdy   // DMA ready
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// decoded register access signals
logic  wen_spi, ren_spi;  // SPI control/status
logic  wen_dat, ren_dat;  // SPI data
logic  wen_dma, ren_dma;  // DMA control/status

//
logic    [31:0] spi_par;  // SPI parameterization
logic    [31:0] spi_sts;  // SPI status
logic    [31:0] spi_dat;  // SPI data

// SPI command interface
logic           cmo_trn;
logic           cmi_trn;

// data
logic           dat_wld;  // write load
logic           dat_rld;  // read  load

// DMA command interface

////////////////////////////////////////////////////////////////////////////////
// register decoder                                                           //
////////////////////////////////////////////////////////////////////////////////

// register write/read access signals
assign {wen_spi, ren_spi} = {reg_wen, reg_ren} & {2{(reg_adr == 3'd2) & ~reg_wrq}};  // SPI control/status
assign {wen_dat, ren_dat} = {reg_wen, reg_ren} & {2{(reg_adr == 3'd3) & ~reg_wrq}};  // SPI data
assign {wen_dma, ren_dma} = {reg_wen, reg_ren} & {2{(reg_adr == 3'd5) & ~reg_wrq}};  // DMA control/status

// read data
always_comb
case (reg_adr)
  3'd0 : reg_rdt =      spi_cfg;  // SPI configuration
  3'd1 : reg_rdt =      spi_par;  // SPI parameterization
  3'd2 : reg_rdt =      spi_sts;  // SPI status
  3'd3 : reg_rdt =      spi_dat;  // SPI data
  3'd4 : reg_rdt = 32'hxxxxxxxx;  // SPI interrupts
  3'd5 : reg_rdt =      tsk_sts;  // DMA status
  3'd6 : reg_rdt =      adr_rof;  // address read  offset
  3'd7 : reg_rdt =      adr_wof;  // address write offset
endcase

// wait request
always_comb
case (reg_adr)
  3'd0 : reg_wrq = 1'b0;                                 // SPI configuration
  3'd1 : reg_wrq = 1'b0;                                 // SPI parameterization
  3'd2 : reg_wrq = reg_wen & ~cmo_rdy;                   // SPI control
  3'd3 : reg_wrq = reg_wen & 1'b0 | reg_ren & ~dat_rld;  // SPI data
  3'd4 : reg_wrq = 1'b0;                                 // SPI interrupts
  3'd5 : reg_wrq = ~tsk_rdy;                             // DMA control/status
  3'd6 : reg_wrq = 1'b0;                                 // address read  offset
  3'd7 : reg_wrq = 1'b0;                                 // address write offset
endcase

// error response
assign reg_err = 1'b0;

////////////////////////////////////////////////////////////////////////////////
// interrupts                                                                 //
////////////////////////////////////////////////////////////////////////////////

// interrupt
assign reg_irq = 1'b0; // TODO

////////////////////////////////////////////////////////////////////////////////
// configuration registers                                                    //
////////////////////////////////////////////////////////////////////////////////

// SPI configuration (write access)
always_ff @(posedge clk, posedge rst)
if (rst) begin
  spi_cfg <= CFG_RST;
end else if (reg_wen & (reg_adr == 3'd0)) begin
  spi_cfg <= CFG_RST & ~CFG_MSK | reg_wdt & CFG_MSK;
end

// SPI parameterization (read access)
assign spi_par =  32'h0;

// SPI status
assign spi_sts =  32'h0; // TODO

// XIP/DMA address offsets
always_ff @(posedge clk, posedge rst)
if (rst) begin
                        adr_rof <= ADR_ROF [31:0];
                        adr_wof <= ADR_WOF [31:0];
end else if (reg_wen) begin
  if (reg_adr == 3'd6)  adr_rof <= reg_wdt [31:0];
  if (reg_adr == 3'd7)  adr_wof <= reg_wdt [31:0];
end

////////////////////////////////////////////////////////////////////////////////
// command output                                                             //
////////////////////////////////////////////////////////////////////////////////

// command output transfer
assign cmo_trn = cmo_vld & cmo_rdy;

// data output
always_ff @(posedge clk)
if (wen_dat)  cmo_dat <= reg_wdt;

// data output load status
always_ff @(posedge clk, posedge rst)
if (rst)             dat_wld <= 1'b0;
else begin
  if      (wen_dat)  dat_wld <= 1'b1;
  else if (cmo_trn)  dat_wld <= 1'b0;
end

// command output
assign cmo_vld = wen_spi;
assign cmo_ctl = {reg_wdt[12:8], reg_wdt[6:0]};

////////////////////////////////////////////////////////////////////////////////
// command input register                                                     //
////////////////////////////////////////////////////////////////////////////////

// command input transfer
assign cmi_trn = cmi_vld & cmi_rdy;

// data input
always_ff @(posedge clk)
if (cmi_trn)  spi_dat <= cmi_dat;

// data input load status
always_ff @(posedge clk, posedge rst)
if (rst)             dat_rld <= 1'b0;
else begin
  if      (cmi_trn)  dat_rld <= 1'b1;
  else if (ren_dat)  dat_rld <= 1'b0;
end

// command input transfer ready
assign cmi_rdy = ~dat_rld;

////////////////////////////////////////////////////////////////////////////////
// DMA control/status interface                                               //
////////////////////////////////////////////////////////////////////////////////

assign tsk_vld = wen_dma;
assign tsk_ctl = reg_wdt;

endmodule: sockit_spi_reg