////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  CDC (clock domain crossing) general purpose gray counter                  //
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

module sockit_spi_cdc #(
  parameter CDW = 1
)(
  // port A
  input  wire  cda_clk,  // clock
  input  wire  cda_rst,  // reset
  input  wire  cda_pli,  // pulse input
  output reg   cda_plo,  // pulse output
  // port B
  input  wire  cdb_clk,  // clock
  input  wire  cdb_rst,  // reset
  input  wire  cdb_pli,  // pulse input
  output reg   cdb_plo   // pulse output
);

// gray function
function automatic [CDW-1:0] gry_inc (input [CDW-1:0] gry_cnt); 
begin
  gry_inc = gry_cnt + 'd1;
end
endfunction

// gray table
reg  [CDW-1:0] gry_tab [0:2**CDW-1];

// port A
reg  [CDW-1:0] cda_syn;  // synchronization
reg  [CDW-1:0] cda_cnt;  // gray counter
wire [CDW-1:0] cda_inc;  // gray increment

// port B
reg  [CDW-1:0] cdb_syn;  // synchronization
reg  [CDW-1:0] cdb_cnt;  // gray counter
wire [CDW-1:0] cdb_inc;  // gray increment

////////////////////////////////////////////////////////////////////////////////
// port A
////////////////////////////////////////////////////////////////////////////////

assign cda_inc = gry_inc (cda_cnt);

always @ (posedge cda_clk, posedge cda_rst)
if (cda_rst) begin
                          cda_syn <= {CDW{1'b0}};
                          cda_cnt <= {CDW{1'b0}};
                          cda_plo <=      1'b0  ;
end else begin
                          cda_syn <= cdb_cnt;
  if (cda_pli & cda_plo)  cda_cnt <= cda_inc;
                          cda_plo <= cda_syn != cda_inc;
end

////////////////////////////////////////////////////////////////////////////////
// port A
////////////////////////////////////////////////////////////////////////////////

assign cdb_inc = gry_inc (cdb_cnt);

always @ (posedge cdb_clk, posedge cdb_rst)
if (cdb_rst) begin
                          cdb_syn <= {CDW{1'b0}};
                          cdb_cnt <= {CDW{1'b0}};
                          cdb_plo <=      1'b0  ;
end else begin
                          cdb_syn <= cda_cnt;
  if (cdb_pli & cdb_plo)  cdb_cnt <= cdb_inc;
                          cdb_plo <= cdb_syn != cdb_inc;
end


endmodule