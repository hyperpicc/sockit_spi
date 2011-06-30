////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  data serializer/de-serializer, clave selects, clocks                      //
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

module sockit_spi_ser #(
  // port widths
  parameter SSW     =            8,  // slave select width
  parameter SDW     =            8,  // serial data register width
  parameter SDL     =            3,  // serial data register width logarithm
  parameter QCO     =        SDL+7,  // queue control output width
  parameter QCI     =            4,  // queue control  input width
  parameter QDW     =        4*SDW   // queue data width
)(
  // system signals
  input  wire           clk,      // clock
  input  wire           rst,      // reset
  // SPI clocks
  output wire           spi_cko,  // output registers
  output wire           spi_cki,  // input  registers
  // SPI configuration
  input  wire           cfg_pol,  // clock polarity
  input  wire           cfg_pha,  // clock phase
  input  wire           cfg_coe,  // clock output enable
  input  wire           cfg_sse,  // slave select output enable
  input  wire           cfg_m_s,  // mode (0 - slave, 1 - master)
  // output queue
  input  wire           quo_req,  // request
  input  wire [QCO-1:0] quo_ctl,  // control
  input  wire [QDW-1:0] quo_dat,  // data
  output wire           quo_grt,  // grant
  // input queue
  output wire           qui_req,  // request
  output wire [QCI-1:0] qui_ctl,  // control
  output wire [QDW-1:0] qui_dat,  // data
  input  wire           qui_grt,  // grant

  // SCLK (serial clock)
  input  wire           spi_sclk_i,  // input (clock loopback)
  output wire           spi_sclk_o,  // output
  output wire           spi_sclk_e,  // output enable
  // SIO  (serial input output) {HOLD_n, WP_n, MISO, MOSI/3wire-bidir}
  input  wire     [3:0] spi_sio_i,   // input
  output wire     [3:0] spi_sio_o,   // output
  output wire     [3:0] spi_sio_e,   // output enable
  // SS_N (slave select - active low signal)
  input  wire [SSW-1:0] spi_ss_i,    // input  (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_o,    // output (requires inverter at the pad)
  output wire [SSW-1:0] spi_ss_e     // output enable
);

////////////////////////////////////////////////////////////////////////////////
// local signals                                                              //
////////////////////////////////////////////////////////////////////////////////

// internal clocks, resets
wire           spi_clk;
wire           spi_rsi;

// queue transfers
wire           qui_trn;
wire           quo_trn;

// cycle timing
reg  [SDL-1:0] cyc_cnt;  // clock counter
reg            cyc_cke;  // clock enable
wire           cyc_end;  // cycle end

// output control signals
reg            cyc_lst;  // input last (signal for synchronization purposes)
reg      [3:0] cyc_doe;  // data output enable
reg            cyc_die;  // data input enable
reg      [1:0] cyc_iom;  // data IO mode
reg  [SSW-1:0] cyc_sse;  // slave select output enable
reg  [SSW-1:0] cyc_sso;  // slave select outputs

// input control signals
reg            cyc_new;  // new (first) data on input (used in slave mode)

// output data signals
reg  [SDW-1:0] spi_sdo_3;
reg  [SDW-1:0] spi_sdo_2;
reg  [SDW-1:0] spi_sdo_1;
reg  [SDW-1:0] spi_sdo_0;

// input data signals
reg  [SDW-1:0] spi_sdi_3;
reg  [SDW-1:0] spi_sdi_2;
reg  [SDW-1:0] spi_sdi_1;
reg  [SDW-1:0] spi_sdi_0;
wire [SDW-1:0] spi_dti_3;
wire [SDW-1:0] spi_dti_2;
wire [SDW-1:0] spi_dti_1;
wire [SDW-1:0] spi_dti_0;

////////////////////////////////////////////////////////////////////////////////
// master/slave mode                                                          //
////////////////////////////////////////////////////////////////////////////////

// clock source
assign spi_clk = cfg_m_s ? clk : spi_sclk_i;

// register clocks
assign spi_cko = (cfg_pol ^ cfg_pha) ^  spi_clk;  // output registers
assign spi_cki = (cfg_pol ^ cfg_pha) ^ ~spi_clk;  // input  registers

////////////////////////////////////////////////////////////////////////////////
// SPI cycle timing                                                           //
////////////////////////////////////////////////////////////////////////////////

// flow control for queue output
assign quo_grt = cyc_end;
assign quo_trn = quo_req & quo_grt;

// flow control for queue input
assign qui_req = cyc_die & cyc_cke & cyc_end;
assign qui_trn = qui_req & qui_grt;

// transfer length counter
always @(posedge spi_cko, posedge rst)
if (rst) begin
  cyc_cke <=      1'b0  ;
  cyc_cnt <= {SDL{1'b0}};
end else begin
  if (quo_trn) begin
    cyc_cke <= quo_ctl [0     ];
    cyc_cnt <= quo_ctl [7+:SDL];
  end else begin
    if (~cyc_end)  cyc_cnt <= cyc_cnt - 'd1;
    if ( quo_grt)  cyc_cke <= 1'b0;
  end
end

assign cyc_end = ~|cyc_cnt;

// IO control registers
always @(posedge spi_cko, posedge rst)
if (rst) begin
  cyc_sso <= {SSW{1'b0}};
  cyc_doe <=      4'h0  ;
  cyc_die <=      1'b0  ;
  cyc_iom <=      2'd1  ;
  cyc_lst <=      1'b0  ;
end else if (quo_trn) begin
  cyc_sso <= {SSW{quo_ctl [1]}} & 'd1;  // TODO
  case (quo_ctl [5:4])
    2'd0 : cyc_doe <= {4{quo_ctl [2]}} & 4'b0001;
    2'd1 : cyc_doe <= {4{quo_ctl [2]}} & 4'b0001;
    2'd2 : cyc_doe <= {4{quo_ctl [2]}} & 4'b0011;
    2'd3 : cyc_doe <= {4{quo_ctl [2]}} & 4'b1111;
  endcase
  cyc_die <= quo_ctl [  3];
  cyc_iom <= quo_ctl [5:4];
  cyc_lst <= quo_ctl [  6];
end

// new data cycle indicator
always @(posedge spi_cko, posedge spi_rsi)
if (spi_rsi)      cyc_new <= 1'b1;
else if (qui_trn) cyc_new <= 1'b0;

assign qui_ctl = {cyc_new, cyc_lst, cyc_iom};
assign qui_dat = {spi_dti_3, spi_dti_2, spi_dti_1, spi_dti_0};

////////////////////////////////////////////////////////////////////////////////
// slave select, clock, data (input, output, enable)                          //
////////////////////////////////////////////////////////////////////////////////

// serial clock output
assign spi_sclk_o = cfg_pol ^ (cyc_cke & ~clk);
assign spi_sclk_e = cfg_coe;


// slave select input
assign spi_rsi = spi_ss_i [0];  // reset for output registers

// slave select output, output enable
assign spi_ss_o =      cyc_sso  ;
assign spi_ss_e = {SSW{cfg_sse}};


// data output
always @ (posedge spi_cko)
if (quo_trn) begin
  spi_sdo_3 <=  quo_dat [3*SDW+:SDW];
  spi_sdo_2 <=  quo_dat [2*SDW+:SDW];
  spi_sdo_1 <=  quo_dat [1*SDW+:SDW];
  spi_sdo_0 <=  quo_dat [0*SDW+:SDW];
end else begin
  if (cyc_doe [3])  spi_sdo_3 <= {spi_sdo_3 [SDW-2:0], 1'bx};
  if (cyc_doe [2])  spi_sdo_2 <= {spi_sdo_2 [SDW-2:0], 1'bx};
  if (cyc_doe [1])  spi_sdo_1 <= {spi_sdo_1 [SDW-2:0], 1'bx};
  if (cyc_doe [0])  spi_sdo_0 <= {spi_sdo_0 [SDW-2:0], 1'bx};
end

assign spi_sio_o [3] = spi_sdo_3 [SDW-1];
assign spi_sio_o [2] = spi_sdo_2 [SDW-1];
assign spi_sio_o [1] = spi_sdo_1 [SDW-1];
assign spi_sio_o [0] = spi_sdo_0 [SDW-1];

// data output enable
assign spi_sio_e = cyc_doe;


// data input
always @ (posedge spi_cki)
if (cyc_die) begin
  spi_sdi_3 <= spi_dti_3;
  spi_sdi_2 <= spi_dti_2;
  spi_sdi_1 <= spi_dti_1;
  spi_sdi_0 <= spi_dti_0;
end

assign spi_dti_3 = {spi_sdi_3 [SDW-2:0], spi_sio_i [3]};
assign spi_dti_2 = {spi_sdi_2 [SDW-2:0], spi_sio_i [2]};
assign spi_dti_1 = {spi_sdi_1 [SDW-2:0], spi_sio_i [1]};
assign spi_dti_0 = {spi_sdi_0 [SDW-2:0], spi_sio_i [0]};

endmodule