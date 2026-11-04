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
module jpeg_dht_std_cx_ac
(
     input  [ 15:0]  lookup_input_i
    ,output [  4:0]  lookup_width_o
    ,output [  7:0]  lookup_value_o
);

//-----------------------------------------------------------------
// Cx AC Table (standard)
//-----------------------------------------------------------------
reg [7:0] cx_ac_value_r;
reg [4:0] cx_ac_width_r;

// Prefix-free fixed codes permit a parallel case, avoiding a priority mux chain.
always @*begin
 cx_ac_value_r=0;cx_ac_width_r=0;
 casez(lookup_input_i)
    16'b00??????????????:begin cx_ac_value_r=8'h00;cx_ac_width_r=5'd2;end
    16'b01??????????????:begin cx_ac_value_r=8'h01;cx_ac_width_r=5'd2;end
    16'b100?????????????:begin cx_ac_value_r=8'h02;cx_ac_width_r=5'd3;end
    16'b1010????????????:begin cx_ac_value_r=8'h03;cx_ac_width_r=5'd4;end
    16'b1011????????????:begin cx_ac_value_r=8'h11;cx_ac_width_r=5'd4;end
    16'b11000???????????:begin cx_ac_value_r=8'h04;cx_ac_width_r=5'd5;end
    16'b11001???????????:begin cx_ac_value_r=8'h05;cx_ac_width_r=5'd5;end
    16'b11010???????????:begin cx_ac_value_r=8'h21;cx_ac_width_r=5'd5;end
    16'b11011???????????:begin cx_ac_value_r=8'h31;cx_ac_width_r=5'd5;end
    16'b111000??????????:begin cx_ac_value_r=8'h06;cx_ac_width_r=5'd6;end
    16'b111001??????????:begin cx_ac_value_r=8'h12;cx_ac_width_r=5'd6;end
    16'b111010??????????:begin cx_ac_value_r=8'h41;cx_ac_width_r=5'd6;end
    16'b111011??????????:begin cx_ac_value_r=8'h51;cx_ac_width_r=5'd6;end
    16'b1111000?????????:begin cx_ac_value_r=8'h07;cx_ac_width_r=5'd7;end
    16'b1111001?????????:begin cx_ac_value_r=8'h61;cx_ac_width_r=5'd7;end
    16'b1111010?????????:begin cx_ac_value_r=8'h71;cx_ac_width_r=5'd7;end
    16'b11110110????????:begin cx_ac_value_r=8'h13;cx_ac_width_r=5'd8;end
    16'b11110111????????:begin cx_ac_value_r=8'h22;cx_ac_width_r=5'd8;end
    16'b11111000????????:begin cx_ac_value_r=8'h32;cx_ac_width_r=5'd8;end
    16'b11111001????????:begin cx_ac_value_r=8'h81;cx_ac_width_r=5'd8;end
    16'b111110100???????:begin cx_ac_value_r=8'h08;cx_ac_width_r=5'd9;end
    16'b111110101???????:begin cx_ac_value_r=8'h14;cx_ac_width_r=5'd9;end
    16'b111110110???????:begin cx_ac_value_r=8'h42;cx_ac_width_r=5'd9;end
    16'b111110111???????:begin cx_ac_value_r=8'h91;cx_ac_width_r=5'd9;end
    16'b111111000???????:begin cx_ac_value_r=8'ha1;cx_ac_width_r=5'd9;end
    16'b111111001???????:begin cx_ac_value_r=8'hb1;cx_ac_width_r=5'd9;end
    16'b111111010???????:begin cx_ac_value_r=8'hc1;cx_ac_width_r=5'd9;end
    16'b1111110110??????:begin cx_ac_value_r=8'h09;cx_ac_width_r=5'd10;end
    16'b1111110111??????:begin cx_ac_value_r=8'h23;cx_ac_width_r=5'd10;end
    16'b1111111000??????:begin cx_ac_value_r=8'h33;cx_ac_width_r=5'd10;end
    16'b1111111001??????:begin cx_ac_value_r=8'h52;cx_ac_width_r=5'd10;end
    16'b1111111010??????:begin cx_ac_value_r=8'hf0;cx_ac_width_r=5'd10;end
    16'b11111110110?????:begin cx_ac_value_r=8'h15;cx_ac_width_r=5'd11;end
    16'b11111110111?????:begin cx_ac_value_r=8'h62;cx_ac_width_r=5'd11;end
    16'b11111111000?????:begin cx_ac_value_r=8'h72;cx_ac_width_r=5'd11;end
    16'b11111111001?????:begin cx_ac_value_r=8'hd1;cx_ac_width_r=5'd11;end
    16'b111111110100????:begin cx_ac_value_r=8'h0a;cx_ac_width_r=5'd12;end
    16'b111111110101????:begin cx_ac_value_r=8'h16;cx_ac_width_r=5'd12;end
    16'b111111110110????:begin cx_ac_value_r=8'h24;cx_ac_width_r=5'd12;end
    16'b111111110111????:begin cx_ac_value_r=8'h34;cx_ac_width_r=5'd12;end
    16'b11111111100000??:begin cx_ac_value_r=8'he1;cx_ac_width_r=5'd14;end
    16'b111111111000010?:begin cx_ac_value_r=8'h25;cx_ac_width_r=5'd15;end
    16'b111111111000011?:begin cx_ac_value_r=8'hf1;cx_ac_width_r=5'd15;end
    16'b1111111110001000:begin cx_ac_value_r=8'h17;cx_ac_width_r=5'd16;end
    16'b1111111110001001:begin cx_ac_value_r=8'h18;cx_ac_width_r=5'd16;end
    16'b1111111110001010:begin cx_ac_value_r=8'h19;cx_ac_width_r=5'd16;end
    16'b1111111110001011:begin cx_ac_value_r=8'h1a;cx_ac_width_r=5'd16;end
    16'b1111111110001100:begin cx_ac_value_r=8'h26;cx_ac_width_r=5'd16;end
    16'b1111111110001101:begin cx_ac_value_r=8'h27;cx_ac_width_r=5'd16;end
    16'b1111111110001110:begin cx_ac_value_r=8'h28;cx_ac_width_r=5'd16;end
    16'b1111111110001111:begin cx_ac_value_r=8'h29;cx_ac_width_r=5'd16;end
    16'b1111111110010000:begin cx_ac_value_r=8'h2a;cx_ac_width_r=5'd16;end
    16'b1111111110010001:begin cx_ac_value_r=8'h35;cx_ac_width_r=5'd16;end
    16'b1111111110010010:begin cx_ac_value_r=8'h36;cx_ac_width_r=5'd16;end
    16'b1111111110010011:begin cx_ac_value_r=8'h37;cx_ac_width_r=5'd16;end
    16'b1111111110010100:begin cx_ac_value_r=8'h38;cx_ac_width_r=5'd16;end
    16'b1111111110010101:begin cx_ac_value_r=8'h39;cx_ac_width_r=5'd16;end
    16'b1111111110010110:begin cx_ac_value_r=8'h3a;cx_ac_width_r=5'd16;end
    16'b1111111110010111:begin cx_ac_value_r=8'h43;cx_ac_width_r=5'd16;end
    16'b1111111110011000:begin cx_ac_value_r=8'h44;cx_ac_width_r=5'd16;end
    16'b1111111110011001:begin cx_ac_value_r=8'h45;cx_ac_width_r=5'd16;end
    16'b1111111110011010:begin cx_ac_value_r=8'h46;cx_ac_width_r=5'd16;end
    16'b1111111110011011:begin cx_ac_value_r=8'h47;cx_ac_width_r=5'd16;end
    16'b1111111110011100:begin cx_ac_value_r=8'h48;cx_ac_width_r=5'd16;end
    16'b1111111110011101:begin cx_ac_value_r=8'h49;cx_ac_width_r=5'd16;end
    16'b1111111110011110:begin cx_ac_value_r=8'h4a;cx_ac_width_r=5'd16;end
    16'b1111111110011111:begin cx_ac_value_r=8'h53;cx_ac_width_r=5'd16;end
    16'b1111111110100000:begin cx_ac_value_r=8'h54;cx_ac_width_r=5'd16;end
    16'b1111111110100001:begin cx_ac_value_r=8'h55;cx_ac_width_r=5'd16;end
    16'b1111111110100010:begin cx_ac_value_r=8'h56;cx_ac_width_r=5'd16;end
    16'b1111111110100011:begin cx_ac_value_r=8'h57;cx_ac_width_r=5'd16;end
    16'b1111111110100100:begin cx_ac_value_r=8'h58;cx_ac_width_r=5'd16;end
    16'b1111111110100101:begin cx_ac_value_r=8'h59;cx_ac_width_r=5'd16;end
    16'b1111111110100110:begin cx_ac_value_r=8'h5a;cx_ac_width_r=5'd16;end
    16'b1111111110100111:begin cx_ac_value_r=8'h63;cx_ac_width_r=5'd16;end
    16'b1111111110101000:begin cx_ac_value_r=8'h64;cx_ac_width_r=5'd16;end
    16'b1111111110101001:begin cx_ac_value_r=8'h65;cx_ac_width_r=5'd16;end
    16'b1111111110101010:begin cx_ac_value_r=8'h66;cx_ac_width_r=5'd16;end
    16'b1111111110101011:begin cx_ac_value_r=8'h67;cx_ac_width_r=5'd16;end
    16'b1111111110101100:begin cx_ac_value_r=8'h68;cx_ac_width_r=5'd16;end
    16'b1111111110101101:begin cx_ac_value_r=8'h69;cx_ac_width_r=5'd16;end
    16'b1111111110101110:begin cx_ac_value_r=8'h6a;cx_ac_width_r=5'd16;end
    16'b1111111110101111:begin cx_ac_value_r=8'h73;cx_ac_width_r=5'd16;end
    16'b1111111110110000:begin cx_ac_value_r=8'h74;cx_ac_width_r=5'd16;end
    16'b1111111110110001:begin cx_ac_value_r=8'h75;cx_ac_width_r=5'd16;end
    16'b1111111110110010:begin cx_ac_value_r=8'h76;cx_ac_width_r=5'd16;end
    16'b1111111110110011:begin cx_ac_value_r=8'h77;cx_ac_width_r=5'd16;end
    16'b1111111110110100:begin cx_ac_value_r=8'h78;cx_ac_width_r=5'd16;end
    16'b1111111110110101:begin cx_ac_value_r=8'h79;cx_ac_width_r=5'd16;end
    16'b1111111110110110:begin cx_ac_value_r=8'h7a;cx_ac_width_r=5'd16;end
    16'b1111111110110111:begin cx_ac_value_r=8'h82;cx_ac_width_r=5'd16;end
    16'b1111111110111000:begin cx_ac_value_r=8'h83;cx_ac_width_r=5'd16;end
    16'b1111111110111001:begin cx_ac_value_r=8'h84;cx_ac_width_r=5'd16;end
    16'b1111111110111010:begin cx_ac_value_r=8'h85;cx_ac_width_r=5'd16;end
    16'b1111111110111011:begin cx_ac_value_r=8'h86;cx_ac_width_r=5'd16;end
    16'b1111111110111100:begin cx_ac_value_r=8'h87;cx_ac_width_r=5'd16;end
    16'b1111111110111101:begin cx_ac_value_r=8'h88;cx_ac_width_r=5'd16;end
    16'b1111111110111110:begin cx_ac_value_r=8'h89;cx_ac_width_r=5'd16;end
    16'b1111111110111111:begin cx_ac_value_r=8'h8a;cx_ac_width_r=5'd16;end
    16'b1111111111000000:begin cx_ac_value_r=8'h92;cx_ac_width_r=5'd16;end
    16'b1111111111000001:begin cx_ac_value_r=8'h93;cx_ac_width_r=5'd16;end
    16'b1111111111000010:begin cx_ac_value_r=8'h94;cx_ac_width_r=5'd16;end
    16'b1111111111000011:begin cx_ac_value_r=8'h95;cx_ac_width_r=5'd16;end
    16'b1111111111000100:begin cx_ac_value_r=8'h96;cx_ac_width_r=5'd16;end
    16'b1111111111000101:begin cx_ac_value_r=8'h97;cx_ac_width_r=5'd16;end
    16'b1111111111000110:begin cx_ac_value_r=8'h98;cx_ac_width_r=5'd16;end
    16'b1111111111000111:begin cx_ac_value_r=8'h99;cx_ac_width_r=5'd16;end
    16'b1111111111001000:begin cx_ac_value_r=8'h9a;cx_ac_width_r=5'd16;end
    16'b1111111111001001:begin cx_ac_value_r=8'ha2;cx_ac_width_r=5'd16;end
    16'b1111111111001010:begin cx_ac_value_r=8'ha3;cx_ac_width_r=5'd16;end
    16'b1111111111001011:begin cx_ac_value_r=8'ha4;cx_ac_width_r=5'd16;end
    16'b1111111111001100:begin cx_ac_value_r=8'ha5;cx_ac_width_r=5'd16;end
    16'b1111111111001101:begin cx_ac_value_r=8'ha6;cx_ac_width_r=5'd16;end
    16'b1111111111001110:begin cx_ac_value_r=8'ha7;cx_ac_width_r=5'd16;end
    16'b1111111111001111:begin cx_ac_value_r=8'ha8;cx_ac_width_r=5'd16;end
    16'b1111111111010000:begin cx_ac_value_r=8'ha9;cx_ac_width_r=5'd16;end
    16'b1111111111010001:begin cx_ac_value_r=8'haa;cx_ac_width_r=5'd16;end
    16'b1111111111010010:begin cx_ac_value_r=8'hb2;cx_ac_width_r=5'd16;end
    16'b1111111111010011:begin cx_ac_value_r=8'hb3;cx_ac_width_r=5'd16;end
    16'b1111111111010100:begin cx_ac_value_r=8'hb4;cx_ac_width_r=5'd16;end
    16'b1111111111010101:begin cx_ac_value_r=8'hb5;cx_ac_width_r=5'd16;end
    16'b1111111111010110:begin cx_ac_value_r=8'hb6;cx_ac_width_r=5'd16;end
    16'b1111111111010111:begin cx_ac_value_r=8'hb7;cx_ac_width_r=5'd16;end
    16'b1111111111011000:begin cx_ac_value_r=8'hb8;cx_ac_width_r=5'd16;end
    16'b1111111111011001:begin cx_ac_value_r=8'hb9;cx_ac_width_r=5'd16;end
    16'b1111111111011010:begin cx_ac_value_r=8'hba;cx_ac_width_r=5'd16;end
    16'b1111111111011011:begin cx_ac_value_r=8'hc2;cx_ac_width_r=5'd16;end
    16'b1111111111011100:begin cx_ac_value_r=8'hc3;cx_ac_width_r=5'd16;end
    16'b1111111111011101:begin cx_ac_value_r=8'hc4;cx_ac_width_r=5'd16;end
    16'b1111111111011110:begin cx_ac_value_r=8'hc5;cx_ac_width_r=5'd16;end
    16'b1111111111011111:begin cx_ac_value_r=8'hc6;cx_ac_width_r=5'd16;end
    16'b1111111111100000:begin cx_ac_value_r=8'hc7;cx_ac_width_r=5'd16;end
    16'b1111111111100001:begin cx_ac_value_r=8'hc8;cx_ac_width_r=5'd16;end
    16'b1111111111100010:begin cx_ac_value_r=8'hc9;cx_ac_width_r=5'd16;end
    16'b1111111111100011:begin cx_ac_value_r=8'hca;cx_ac_width_r=5'd16;end
    16'b1111111111100100:begin cx_ac_value_r=8'hd2;cx_ac_width_r=5'd16;end
    16'b1111111111100101:begin cx_ac_value_r=8'hd3;cx_ac_width_r=5'd16;end
    16'b1111111111100110:begin cx_ac_value_r=8'hd4;cx_ac_width_r=5'd16;end
    16'b1111111111100111:begin cx_ac_value_r=8'hd5;cx_ac_width_r=5'd16;end
    16'b1111111111101000:begin cx_ac_value_r=8'hd6;cx_ac_width_r=5'd16;end
    16'b1111111111101001:begin cx_ac_value_r=8'hd7;cx_ac_width_r=5'd16;end
    16'b1111111111101010:begin cx_ac_value_r=8'hd8;cx_ac_width_r=5'd16;end
    16'b1111111111101011:begin cx_ac_value_r=8'hd9;cx_ac_width_r=5'd16;end
    16'b1111111111101100:begin cx_ac_value_r=8'hda;cx_ac_width_r=5'd16;end
    16'b1111111111101101:begin cx_ac_value_r=8'he2;cx_ac_width_r=5'd16;end
    16'b1111111111101110:begin cx_ac_value_r=8'he3;cx_ac_width_r=5'd16;end
    16'b1111111111101111:begin cx_ac_value_r=8'he4;cx_ac_width_r=5'd16;end
    16'b1111111111110000:begin cx_ac_value_r=8'he5;cx_ac_width_r=5'd16;end
    16'b1111111111110001:begin cx_ac_value_r=8'he6;cx_ac_width_r=5'd16;end
    16'b1111111111110010:begin cx_ac_value_r=8'he7;cx_ac_width_r=5'd16;end
    16'b1111111111110011:begin cx_ac_value_r=8'he8;cx_ac_width_r=5'd16;end
    16'b1111111111110100:begin cx_ac_value_r=8'he9;cx_ac_width_r=5'd16;end
    16'b1111111111110101:begin cx_ac_value_r=8'hea;cx_ac_width_r=5'd16;end
    16'b1111111111110110:begin cx_ac_value_r=8'hf2;cx_ac_width_r=5'd16;end
    16'b1111111111110111:begin cx_ac_value_r=8'hf3;cx_ac_width_r=5'd16;end
    16'b1111111111111000:begin cx_ac_value_r=8'hf4;cx_ac_width_r=5'd16;end
    16'b1111111111111001:begin cx_ac_value_r=8'hf5;cx_ac_width_r=5'd16;end
    16'b1111111111111010:begin cx_ac_value_r=8'hf6;cx_ac_width_r=5'd16;end
    16'b1111111111111011:begin cx_ac_value_r=8'hf7;cx_ac_width_r=5'd16;end
    16'b1111111111111100:begin cx_ac_value_r=8'hf8;cx_ac_width_r=5'd16;end
    16'b1111111111111101:begin cx_ac_value_r=8'hf9;cx_ac_width_r=5'd16;end
    16'b1111111111111110:begin cx_ac_value_r=8'hfa;cx_ac_width_r=5'd16;end
    default:begin cx_ac_value_r=0;cx_ac_width_r=0;end
 endcase
end

assign lookup_width_o = cx_ac_width_r;
assign lookup_value_o = cx_ac_value_r;

endmodule
