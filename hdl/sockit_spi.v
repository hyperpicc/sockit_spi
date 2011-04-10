////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
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
// this file contains:                                                        //
// - the system bus interface                                                 //
// - static configuration registers                                           //
// - SPI state machine and serialization logic                                //
////////////////////////////////////////////////////////////////////////////////

module sockit_spi #(
  parameter CTL_RST = 32'h00000000,  // control/status register reset value
  parameter CTL_MSK = 32'hffffffff,  // control/status register implementation mask
  parameter CFG_RST = 32'h00000000,  // configuration register reset value
  parameter CFG_MSK = 32'hffffffff,  // configuration register implementation mask
  parameter XIP_RST = 32'h00000000,  // XIP configuration register reset value
  parameter XIP_MSK = 32'h00000001,  // XIP configuration register implentation mask
  parameter NOP     = 32'h00000000,  // no operation instuction for the given CPU
  parameter XAW     =           24,  // XIP address width
  parameter SSW     =            8,  // slave select width
  parameter SDW     =            8,  // serial data register width
  parameter CDC     =         1'b0   // implement clock domain crossing
)(
  // system signals (used by the CPU interface)
  input  wire           clk_cpu,     // clock for CPU interface
  input  wire           rst_cpu,     // reset for CPU interface
  input  wire           clk_spi,     // clock for SPI IO
  input  wire           rst_spi,     // reset for SPI IO
  // XIP interface bus
  input  wire           xip_ren,     // read enable
  input  wire [XAW-1:0] xip_adr,     // address
  output wire    [31:0] xip_rdt,     // read data
  output wire           xip_wrq,     // wait request
  output wire           xip_err,     // error interrupt
  // registers interface bus
  input  wire           reg_wen,     // write enable
  input  wire           reg_ren,     // read enable
  input  wire     [1:0] reg_adr,     // address
  input  wire    [31:0] reg_wdt,     // write data
  output wire    [31:0] reg_rdt,     // read data
  output wire           reg_wrq,     // wait request
  output wire           reg_irq,     // interrupt request

  // SPI signals (at a higher level should be connected to tristate IO pads)
  // serial clock
  input  wire           spi_sclk_i,  // input (clock loopback)
  output wire           spi_sclk_o,  // output
  output wire           spi_sclk_e,  // output enable
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  input  wire     [3:0] spi_sio_i,   // input
  output wire     [3:0] spi_sio_o,   // output
  output wire     [3:0] spi_sio_e,   // output enable
  // active low slave select signal
  input  wire [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

localparam BOW = 4*SDW + SSW + 11;
localparam BIW = 4*SDW + 1;

// command output
wire           reg_cmo_req, xip_cmo_req, dma_cmo_req;
wire    [31:0] reg_cmo_dat, xip_cmo_dat, dma_cmo_dat;
wire    [16:0] reg_cmo_ctl, xip_cmo_ctl, dma_cmo_ctl;
wire           reg_cmo_grt, xip_cmo_grt, dma_cmo_grt;
// command input
wire           reg_cmi_req, xip_cmi_req, dma_cmi_req;
wire    [31:0] reg_cmi_dat, xip_cmi_dat, dma_cmi_dat;
wire     [0:0] reg_cmi_ctl, xip_cmi_ctl, dma_cmi_ctl;
wire           reg_cmi_grt, xip_cmi_grt, dma_cmi_grt;

////////////////////////////////////////////////////////////////////////////////
// REG instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_reg #(
  .CFG_RST  (CFG_RST),
  .CFG_MSK  (CFG_MSK),
  .XIP_RST  (XIP_RST),
  .XIP_MSK  (XIP_MSK),
  .XAW      (XAW    )
) rgs (
  // system signals
  .clk      (clk_cpu),  // clock
  .rst      (rst_cpu),  // reset
  // register interface
  .reg_wen  (reg_wen),
  .reg_ren  (reg_ren),
  .reg_adr  (reg_adr),
  .reg_wdt  (reg_wdt),
  .reg_rdt  (reg_rdt),
  .reg_wrq  (reg_wrq),
  .reg_irq  (reg_irq),
  // configuration
  // command output
  .cmo_req  (reg_cmo_req),
  .cmo_dat  (reg_cmo_dat),
  .cmo_ctl  (reg_cmo_ctl),
  .cmo_grt  (reg_cmo_grt),
  // command input
  .cmi_req  (reg_cmi_req),
  .cmi_dat  (reg_cmi_dat),
  .cmi_ctl  (reg_cmi_ctl),
  .cmi_grt  (reg_cmi_grt)
);

////////////////////////////////////////////////////////////////////////////////
// XIP instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_xip #(
  .XAW      (XAW),      // bus address width
  .NOP      (NOP)       // no operation instruction (returned on error)
) xip (
  // system signals
  .clk      (clk_cpu),  // clock
  .rst      (rst_cpu),  // reset
  // input bus (XIP requests)
  .xip_wen  (xip_wen),  // write enable
  .xip_ren  (xip_ren),  // read enable
  .xip_adr  (xip_adr),  // address
  .xip_wdt  (xip_wdt),  // write data
  .xip_rdt  (xip_rdt),  // read data
  .xip_wrq  (xip_wrq),  // wait request
  .xip_err  (xip_err),  // error interrupt
  // configuration
  // command output
  .cmo_req  (xip_cmo_req),
  .cmo_dat  (xip_cmo_dat),
  .cmo_ctl  (xip_cmo_ctl),
  .cmo_grt  (xip_cmo_grt),
  // command input
  .cmi_req  (xip_cmi_req),
  .cmi_dat  (xip_cmi_dat),
  .cmi_ctl  (xip_cmi_ctl),
  .cmi_grt  (xip_cmi_grt)
);

////////////////////////////////////////////////////////////////////////////////
// DMA instance                                                               //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_dma #(
  .DAW      (XAW)    // TODO
) dma (
  // system signals
  .clk      (clk_cpu),
  .rst      (rst_cpu),
  // input bus (XIP requests)
  .dma_wen  (dma_wen),
  .dma_ren  (dma_ren),
  .dma_adr  (dma_adr),
  .dma_wdt  (dma_wdt),
  .dma_rdt  (dma_rdt),
  .dma_wrq  (dma_wrq),
  .dma_err  (dma_err),
  // configuration
  // command output
  .cmo_req  (dma_cmo_req),
  .cmo_dat  (dma_cmo_dat),
  .cmo_ctl  (dma_cmo_ctl),
  .cmo_grt  (dma_cmo_grt),
  // command input
  .cmi_req  (dma_cmi_req),
  .cmi_dat  (dma_cmi_dat),
  .cmi_ctl  (dma_cmi_ctl),
  .cmi_grt  (dma_cmi_grt)
);

////////////////////////////////////////////////////////////////////////////////
// arbiter                                                                    //
////////////////////////////////////////////////////////////////////////////////

//reg [1:0] master;


// command output arbiter
assign     cmo_req = reg_cmo_req;
assign     cmo_dat = reg_cmo_dat;
assign reg_cmo_grt =     cmo_grt & 1'b1;

// command input arbiter
assign     cmi_req = reg_cmo_req;
assign     cmi_dat = reg_cmo_dat;
assign reg_cmi_grt =     cmo_grt & 1'b1;

////////////////////////////////////////////////////////////////////////////////
// repack                                                                     //
////////////////////////////////////////////////////////////////////////////////

wire           bfo_wer;
wire           bfo_weg;
wire [BOW-1:0] bfo_wdt;
wire [BOW-1:0] bfo_rdt;
wire           bfo_rer;
wire           bfo_reg;

wire           bfi_rer;
wire           bfi_reg;
wire [BIW-1:0] bfi_rdt;
wire [BIW-1:0] bfi_wdt;
wire           bfi_wer;
wire           bfi_weg;

sockit_spi_rpo #(
  .SDW  (SDW)
) rpo (
  // system signals
  .clk      (clk_cpu),
  .rst      (rst_cpu),
  // configuration
  // command output
  .cmd_req  (cmo_req),
  .cmd_dat  (cmo_dat),
  .cmd_ctl  (cmo_ctl),
  .cmd_grt  (cmo_grt),
  // buffer output
  .buf_req  (bfo_wer),
  .buf_dat  (bfo_wdt[      4*SDW-1:0]),
  .buf_ctl  (bfo_wdt[BOW-1:4*SDW    ]),
  .buf_grt  (bfo_grt)
);

sockit_spi_rpi #(
  .SDW  (SDW)
) rpi (
  // system signals
  .clk      (clk_cpu),
  .rst      (rst_cpu),
  // command input
  .cmi_req  (dma_cmi_req),
  .cmi_dat  (dma_cmi_dat),
  .cmi_ctl  (dma_cmi_ctl),
  .cmi_grt  (dma_cmi_grt),
  // buffer output
  .bfo_req  (bfo_wer),
  .bfo_dat  (bfo_wdt[      4*SDW-1:0]),
  .bfo_ctl  (bfo_wdt[BOW-1:4*SDW    ]),
  .bfo_grt  (bfo_grt)
);

////////////////////////////////////////////////////////////////////////////////
// clock domain crossing pipeline (optional) for data register                //
////////////////////////////////////////////////////////////////////////////////

generate if (CDC) begin : cdc

  // data output
  sockit_spi_cdc #(
    .CW       ( 1),
    .DW       (BOW)
  ) cdc_bfo (
    // input port
    .cdi_clk  (clk_cpu),
    .cdi_rst  (rst_cpu),
    .cdi_dat  (bus_wdt),
    .cdi_pli  (bus_wed),
    .cdi_plo  (pod_sts),
    // output port
    .cdo_clk  (clk_spi),
    .cdo_rst  (rst_spi),
    .cdo_pli  (bfo_reg),
    .cdo_plo  (bfo_rer),
    .cdo_dat  (bfo_rdt)
  );

  // data input
  sockit_spi_cdc #(
    .CW       ( 1),
    .DW       (BIW)
  ) cdc_bfi (
    // input port
    .cdi_clk  (clk_spi),
    .cdi_rst  (rst_spi),
    .cdi_dat  (bfi_wdt),
    .cdi_pli  (bfi_wer),
    .cdi_plo  (bfi_weg),
    // output port
    .cdo_clk  (clk_cpu),
    .cdo_rst  (rst_cpu),
    .cdo_pli  (bus_red),
    .cdo_plo  (pid_sts),
    .cdo_dat  (bus_rdt)
  );

end else begin : syn

  reg [31:0] buf_dat;

  // write data
  assign pod_sts = cyc_run;
  assign buf_wdt = bus_wdt;

  // read data
  assign pid_sts = 1'bx;     // TODO
  assign bus_rdt = buf_dat;

end endgenerate

////////////////////////////////////////////////////////////////////////////////
// serializer/deserializer instance                                           //
////////////////////////////////////////////////////////////////////////////////

sockit_spi_ser #(
  .SSW      (SSW),
  .SDW      (SDW)
) ser (
  // system signals
  .clk      (clk_spi),
  .rst      (rst_spi),
  // output buffer
  .bfo_req  (bfo_req),
  .bfo_dat  (bfo_dat),
  .bfo_ctl  (bfo_ctl),
  .bfo_grt  (bfo_grt),
  // input buffer
  .bfi_wdt  (bfi_wdt),
  .bfi_ctl  (bfi_ctl),
  .bfi_req  (bfi_req),
  .bfi_grt  (bfi_grt),

  // serial clock
  .spi_sclk_i  (spi_sclk_i),
  .spi_sclk_o  (spi_sclk_o),
  .spi_sclk_e  (spi_sclk_e),
  // serial input output SIO[3:0] or {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  .spi_sio_i   (spi_sio_i),
  .spi_sio_o   (spi_sio_o),
  .spi_sio_e   (spi_sio_e),
  // active low slave select signal
  .spi_ss_i    (spi_ss_i),
  .spi_ss_o    (spi_ss_o),
  .spi_ss_e    (spi_ss_e)
);

endmodule
