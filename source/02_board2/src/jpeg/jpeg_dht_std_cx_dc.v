//-----------------------------------------------------------------
//                      Baseline JPEG Decoder
//                             V0.1
//                       Ultra-Embedded.com
//                        Copyright 2020
//
//                   admin@ultra-embedded.com
//-----------------------------------------------------------------
//                      License: Apache 2.0
// This IP can be freely used in commercial projects, however you may
// want access to unreleased materials such as verification environments,
// or test vectors, as well as changes to the IP for integration purposes.
// If this is the case, contact the above address.
// I am interested to hear how and where this IP is used, so please get
// in touch!
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------
module jpeg_dht_std_cx_dc
(
     input  [ 15:0]  lookup_input_i
    ,output [  4:0]  lookup_width_o
    ,output [  7:0]  lookup_value_o
);

//-----------------------------------------------------------------
// Cx DC Table (standard)
//-----------------------------------------------------------------
reg [7:0] cx_dc_value_r;
reg [4:0] cx_dc_width_r;

// Prefix-free fixed codes permit a parallel case, avoiding a priority mux chain.
always @*begin
 cx_dc_value_r=0;cx_dc_width_r=0;
 casez(lookup_input_i)
    16'b00??????????????:begin cx_dc_value_r=8'h00;cx_dc_width_r=5'd2;end
    16'b01??????????????:begin cx_dc_value_r=8'h01;cx_dc_width_r=5'd2;end
    16'b10??????????????:begin cx_dc_value_r=8'h02;cx_dc_width_r=5'd2;end
    16'b110?????????????:begin cx_dc_value_r=8'h03;cx_dc_width_r=5'd3;end
    16'b1110????????????:begin cx_dc_value_r=8'h04;cx_dc_width_r=5'd4;end
    16'b11110???????????:begin cx_dc_value_r=8'h05;cx_dc_width_r=5'd5;end
    16'b111110??????????:begin cx_dc_value_r=8'h06;cx_dc_width_r=5'd6;end
    16'b1111110?????????:begin cx_dc_value_r=8'h07;cx_dc_width_r=5'd7;end
    16'b11111110????????:begin cx_dc_value_r=8'h08;cx_dc_width_r=5'd8;end
    16'b111111110???????:begin cx_dc_value_r=8'h09;cx_dc_width_r=5'd9;end
    16'b1111111110??????:begin cx_dc_value_r=8'h0a;cx_dc_width_r=5'd10;end
    16'b11111111110?????:begin cx_dc_value_r=8'h0b;cx_dc_width_r=5'd11;end
    default:begin cx_dc_value_r=0;cx_dc_width_r=0;end
 endcase
end

assign lookup_width_o = cx_dc_width_r;
assign lookup_value_o = cx_dc_value_r;

endmodule

