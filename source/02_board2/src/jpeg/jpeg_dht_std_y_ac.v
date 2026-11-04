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
module jpeg_dht_std_y_ac
(
     input  [ 15:0]  lookup_input_i
    ,output [  4:0]  lookup_width_o
    ,output [  7:0]  lookup_value_o
);

//-----------------------------------------------------------------
// Y AC Table (standard)
//-----------------------------------------------------------------
reg [7:0] y_ac_value_r;
reg [4:0] y_ac_width_r;

// Prefix-free fixed codes permit a parallel case, avoiding a priority mux chain.
always @*begin
 y_ac_value_r=0;y_ac_width_r=0;
 casez(lookup_input_i)
    16'b00??????????????:begin y_ac_value_r=8'h01;y_ac_width_r=5'd2;end
    16'b01??????????????:begin y_ac_value_r=8'h02;y_ac_width_r=5'd2;end
    16'b100?????????????:begin y_ac_value_r=8'h03;y_ac_width_r=5'd3;end
    16'b1010????????????:begin y_ac_value_r=8'h00;y_ac_width_r=5'd4;end
    16'b1011????????????:begin y_ac_value_r=8'h04;y_ac_width_r=5'd4;end
    16'b1100????????????:begin y_ac_value_r=8'h11;y_ac_width_r=5'd4;end
    16'b11010???????????:begin y_ac_value_r=8'h05;y_ac_width_r=5'd5;end
    16'b11011???????????:begin y_ac_value_r=8'h12;y_ac_width_r=5'd5;end
    16'b11100???????????:begin y_ac_value_r=8'h21;y_ac_width_r=5'd5;end
    16'b111010??????????:begin y_ac_value_r=8'h31;y_ac_width_r=5'd6;end
    16'b111011??????????:begin y_ac_value_r=8'h41;y_ac_width_r=5'd6;end
    16'b1111000?????????:begin y_ac_value_r=8'h06;y_ac_width_r=5'd7;end
    16'b1111001?????????:begin y_ac_value_r=8'h13;y_ac_width_r=5'd7;end
    16'b1111010?????????:begin y_ac_value_r=8'h51;y_ac_width_r=5'd7;end
    16'b1111011?????????:begin y_ac_value_r=8'h61;y_ac_width_r=5'd7;end
    16'b11111000????????:begin y_ac_value_r=8'h07;y_ac_width_r=5'd8;end
    16'b11111001????????:begin y_ac_value_r=8'h22;y_ac_width_r=5'd8;end
    16'b11111010????????:begin y_ac_value_r=8'h71;y_ac_width_r=5'd8;end
    16'b111110110???????:begin y_ac_value_r=8'h14;y_ac_width_r=5'd9;end
    16'b111110111???????:begin y_ac_value_r=8'h32;y_ac_width_r=5'd9;end
    16'b111111000???????:begin y_ac_value_r=8'h81;y_ac_width_r=5'd9;end
    16'b111111001???????:begin y_ac_value_r=8'h91;y_ac_width_r=5'd9;end
    16'b111111010???????:begin y_ac_value_r=8'ha1;y_ac_width_r=5'd9;end
    16'b1111110110??????:begin y_ac_value_r=8'h08;y_ac_width_r=5'd10;end
    16'b1111110111??????:begin y_ac_value_r=8'h23;y_ac_width_r=5'd10;end
    16'b1111111000??????:begin y_ac_value_r=8'h42;y_ac_width_r=5'd10;end
    16'b1111111001??????:begin y_ac_value_r=8'hb1;y_ac_width_r=5'd10;end
    16'b1111111010??????:begin y_ac_value_r=8'hc1;y_ac_width_r=5'd10;end
    16'b11111110110?????:begin y_ac_value_r=8'h15;y_ac_width_r=5'd11;end
    16'b11111110111?????:begin y_ac_value_r=8'h52;y_ac_width_r=5'd11;end
    16'b11111111000?????:begin y_ac_value_r=8'hd1;y_ac_width_r=5'd11;end
    16'b11111111001?????:begin y_ac_value_r=8'hf0;y_ac_width_r=5'd11;end
    16'b111111110100????:begin y_ac_value_r=8'h24;y_ac_width_r=5'd12;end
    16'b111111110101????:begin y_ac_value_r=8'h33;y_ac_width_r=5'd12;end
    16'b111111110110????:begin y_ac_value_r=8'h62;y_ac_width_r=5'd12;end
    16'b111111110111????:begin y_ac_value_r=8'h72;y_ac_width_r=5'd12;end
    16'b111111111000000?:begin y_ac_value_r=8'h82;y_ac_width_r=5'd15;end
    16'b1111111110000010:begin y_ac_value_r=8'h09;y_ac_width_r=5'd16;end
    16'b1111111110000011:begin y_ac_value_r=8'h0a;y_ac_width_r=5'd16;end
    16'b1111111110000100:begin y_ac_value_r=8'h16;y_ac_width_r=5'd16;end
    16'b1111111110000101:begin y_ac_value_r=8'h17;y_ac_width_r=5'd16;end
    16'b1111111110000110:begin y_ac_value_r=8'h18;y_ac_width_r=5'd16;end
    16'b1111111110000111:begin y_ac_value_r=8'h19;y_ac_width_r=5'd16;end
    16'b1111111110001000:begin y_ac_value_r=8'h1a;y_ac_width_r=5'd16;end
    16'b1111111110001001:begin y_ac_value_r=8'h25;y_ac_width_r=5'd16;end
    16'b1111111110001010:begin y_ac_value_r=8'h26;y_ac_width_r=5'd16;end
    16'b1111111110001011:begin y_ac_value_r=8'h27;y_ac_width_r=5'd16;end
    16'b1111111110001100:begin y_ac_value_r=8'h28;y_ac_width_r=5'd16;end
    16'b1111111110001101:begin y_ac_value_r=8'h29;y_ac_width_r=5'd16;end
    16'b1111111110001110:begin y_ac_value_r=8'h2a;y_ac_width_r=5'd16;end
    16'b1111111110001111:begin y_ac_value_r=8'h34;y_ac_width_r=5'd16;end
    16'b1111111110010000:begin y_ac_value_r=8'h35;y_ac_width_r=5'd16;end
    16'b1111111110010001:begin y_ac_value_r=8'h36;y_ac_width_r=5'd16;end
    16'b1111111110010010:begin y_ac_value_r=8'h37;y_ac_width_r=5'd16;end
    16'b1111111110010011:begin y_ac_value_r=8'h38;y_ac_width_r=5'd16;end
    16'b1111111110010100:begin y_ac_value_r=8'h39;y_ac_width_r=5'd16;end
    16'b1111111110010101:begin y_ac_value_r=8'h3a;y_ac_width_r=5'd16;end
    16'b1111111110010110:begin y_ac_value_r=8'h43;y_ac_width_r=5'd16;end
    16'b1111111110010111:begin y_ac_value_r=8'h44;y_ac_width_r=5'd16;end
    16'b1111111110011000:begin y_ac_value_r=8'h45;y_ac_width_r=5'd16;end
    16'b1111111110011001:begin y_ac_value_r=8'h46;y_ac_width_r=5'd16;end
    16'b1111111110011010:begin y_ac_value_r=8'h47;y_ac_width_r=5'd16;end
    16'b1111111110011011:begin y_ac_value_r=8'h48;y_ac_width_r=5'd16;end
    16'b1111111110011100:begin y_ac_value_r=8'h49;y_ac_width_r=5'd16;end
    16'b1111111110011101:begin y_ac_value_r=8'h4a;y_ac_width_r=5'd16;end
    16'b1111111110011110:begin y_ac_value_r=8'h53;y_ac_width_r=5'd16;end
    16'b1111111110011111:begin y_ac_value_r=8'h54;y_ac_width_r=5'd16;end
    16'b1111111110100000:begin y_ac_value_r=8'h55;y_ac_width_r=5'd16;end
    16'b1111111110100001:begin y_ac_value_r=8'h56;y_ac_width_r=5'd16;end
    16'b1111111110100010:begin y_ac_value_r=8'h57;y_ac_width_r=5'd16;end
    16'b1111111110100011:begin y_ac_value_r=8'h58;y_ac_width_r=5'd16;end
    16'b1111111110100100:begin y_ac_value_r=8'h59;y_ac_width_r=5'd16;end
    16'b1111111110100101:begin y_ac_value_r=8'h5a;y_ac_width_r=5'd16;end
    16'b1111111110100110:begin y_ac_value_r=8'h63;y_ac_width_r=5'd16;end
    16'b1111111110100111:begin y_ac_value_r=8'h64;y_ac_width_r=5'd16;end
    16'b1111111110101000:begin y_ac_value_r=8'h65;y_ac_width_r=5'd16;end
    16'b1111111110101001:begin y_ac_value_r=8'h66;y_ac_width_r=5'd16;end
    16'b1111111110101010:begin y_ac_value_r=8'h67;y_ac_width_r=5'd16;end
    16'b1111111110101011:begin y_ac_value_r=8'h68;y_ac_width_r=5'd16;end
    16'b1111111110101100:begin y_ac_value_r=8'h69;y_ac_width_r=5'd16;end
    16'b1111111110101101:begin y_ac_value_r=8'h6a;y_ac_width_r=5'd16;end
    16'b1111111110101110:begin y_ac_value_r=8'h73;y_ac_width_r=5'd16;end
    16'b1111111110101111:begin y_ac_value_r=8'h74;y_ac_width_r=5'd16;end
    16'b1111111110110000:begin y_ac_value_r=8'h75;y_ac_width_r=5'd16;end
    16'b1111111110110001:begin y_ac_value_r=8'h76;y_ac_width_r=5'd16;end
    16'b1111111110110010:begin y_ac_value_r=8'h77;y_ac_width_r=5'd16;end
    16'b1111111110110011:begin y_ac_value_r=8'h78;y_ac_width_r=5'd16;end
    16'b1111111110110100:begin y_ac_value_r=8'h79;y_ac_width_r=5'd16;end
    16'b1111111110110101:begin y_ac_value_r=8'h7a;y_ac_width_r=5'd16;end
    16'b1111111110110110:begin y_ac_value_r=8'h83;y_ac_width_r=5'd16;end
    16'b1111111110110111:begin y_ac_value_r=8'h84;y_ac_width_r=5'd16;end
    16'b1111111110111000:begin y_ac_value_r=8'h85;y_ac_width_r=5'd16;end
    16'b1111111110111001:begin y_ac_value_r=8'h86;y_ac_width_r=5'd16;end
    16'b1111111110111010:begin y_ac_value_r=8'h87;y_ac_width_r=5'd16;end
    16'b1111111110111011:begin y_ac_value_r=8'h88;y_ac_width_r=5'd16;end
    16'b1111111110111100:begin y_ac_value_r=8'h89;y_ac_width_r=5'd16;end
    16'b1111111110111101:begin y_ac_value_r=8'h8a;y_ac_width_r=5'd16;end
    16'b1111111110111110:begin y_ac_value_r=8'h92;y_ac_width_r=5'd16;end
    16'b1111111110111111:begin y_ac_value_r=8'h93;y_ac_width_r=5'd16;end
    16'b1111111111000000:begin y_ac_value_r=8'h94;y_ac_width_r=5'd16;end
    16'b1111111111000001:begin y_ac_value_r=8'h95;y_ac_width_r=5'd16;end
    16'b1111111111000010:begin y_ac_value_r=8'h96;y_ac_width_r=5'd16;end
    16'b1111111111000011:begin y_ac_value_r=8'h97;y_ac_width_r=5'd16;end
    16'b1111111111000100:begin y_ac_value_r=8'h98;y_ac_width_r=5'd16;end
    16'b1111111111000101:begin y_ac_value_r=8'h99;y_ac_width_r=5'd16;end
    16'b1111111111000110:begin y_ac_value_r=8'h9a;y_ac_width_r=5'd16;end
    16'b1111111111000111:begin y_ac_value_r=8'ha2;y_ac_width_r=5'd16;end
    16'b1111111111001000:begin y_ac_value_r=8'ha3;y_ac_width_r=5'd16;end
    16'b1111111111001001:begin y_ac_value_r=8'ha4;y_ac_width_r=5'd16;end
    16'b1111111111001010:begin y_ac_value_r=8'ha5;y_ac_width_r=5'd16;end
    16'b1111111111001011:begin y_ac_value_r=8'ha6;y_ac_width_r=5'd16;end
    16'b1111111111001100:begin y_ac_value_r=8'ha7;y_ac_width_r=5'd16;end
    16'b1111111111001101:begin y_ac_value_r=8'ha8;y_ac_width_r=5'd16;end
    16'b1111111111001110:begin y_ac_value_r=8'ha9;y_ac_width_r=5'd16;end
    16'b1111111111001111:begin y_ac_value_r=8'haa;y_ac_width_r=5'd16;end
    16'b1111111111010000:begin y_ac_value_r=8'hb2;y_ac_width_r=5'd16;end
    16'b1111111111010001:begin y_ac_value_r=8'hb3;y_ac_width_r=5'd16;end
    16'b1111111111010010:begin y_ac_value_r=8'hb4;y_ac_width_r=5'd16;end
    16'b1111111111010011:begin y_ac_value_r=8'hb5;y_ac_width_r=5'd16;end
    16'b1111111111010100:begin y_ac_value_r=8'hb6;y_ac_width_r=5'd16;end
    16'b1111111111010101:begin y_ac_value_r=8'hb7;y_ac_width_r=5'd16;end
    16'b1111111111010110:begin y_ac_value_r=8'hb8;y_ac_width_r=5'd16;end
    16'b1111111111010111:begin y_ac_value_r=8'hb9;y_ac_width_r=5'd16;end
    16'b1111111111011000:begin y_ac_value_r=8'hba;y_ac_width_r=5'd16;end
    16'b1111111111011001:begin y_ac_value_r=8'hc2;y_ac_width_r=5'd16;end
    16'b1111111111011010:begin y_ac_value_r=8'hc3;y_ac_width_r=5'd16;end
    16'b1111111111011011:begin y_ac_value_r=8'hc4;y_ac_width_r=5'd16;end
    16'b1111111111011100:begin y_ac_value_r=8'hc5;y_ac_width_r=5'd16;end
    16'b1111111111011101:begin y_ac_value_r=8'hc6;y_ac_width_r=5'd16;end
    16'b1111111111011110:begin y_ac_value_r=8'hc7;y_ac_width_r=5'd16;end
    16'b1111111111011111:begin y_ac_value_r=8'hc8;y_ac_width_r=5'd16;end
    16'b1111111111100000:begin y_ac_value_r=8'hc9;y_ac_width_r=5'd16;end
    16'b1111111111100001:begin y_ac_value_r=8'hca;y_ac_width_r=5'd16;end
    16'b1111111111100010:begin y_ac_value_r=8'hd2;y_ac_width_r=5'd16;end
    16'b1111111111100011:begin y_ac_value_r=8'hd3;y_ac_width_r=5'd16;end
    16'b1111111111100100:begin y_ac_value_r=8'hd4;y_ac_width_r=5'd16;end
    16'b1111111111100101:begin y_ac_value_r=8'hd5;y_ac_width_r=5'd16;end
    16'b1111111111100110:begin y_ac_value_r=8'hd6;y_ac_width_r=5'd16;end
    16'b1111111111100111:begin y_ac_value_r=8'hd7;y_ac_width_r=5'd16;end
    16'b1111111111101000:begin y_ac_value_r=8'hd8;y_ac_width_r=5'd16;end
    16'b1111111111101001:begin y_ac_value_r=8'hd9;y_ac_width_r=5'd16;end
    16'b1111111111101010:begin y_ac_value_r=8'hda;y_ac_width_r=5'd16;end
    16'b1111111111101011:begin y_ac_value_r=8'he1;y_ac_width_r=5'd16;end
    16'b1111111111101100:begin y_ac_value_r=8'he2;y_ac_width_r=5'd16;end
    16'b1111111111101101:begin y_ac_value_r=8'he3;y_ac_width_r=5'd16;end
    16'b1111111111101110:begin y_ac_value_r=8'he4;y_ac_width_r=5'd16;end
    16'b1111111111101111:begin y_ac_value_r=8'he5;y_ac_width_r=5'd16;end
    16'b1111111111110000:begin y_ac_value_r=8'he6;y_ac_width_r=5'd16;end
    16'b1111111111110001:begin y_ac_value_r=8'he7;y_ac_width_r=5'd16;end
    16'b1111111111110010:begin y_ac_value_r=8'he8;y_ac_width_r=5'd16;end
    16'b1111111111110011:begin y_ac_value_r=8'he9;y_ac_width_r=5'd16;end
    16'b1111111111110100:begin y_ac_value_r=8'hea;y_ac_width_r=5'd16;end
    16'b1111111111110101:begin y_ac_value_r=8'hf1;y_ac_width_r=5'd16;end
    16'b1111111111110110:begin y_ac_value_r=8'hf2;y_ac_width_r=5'd16;end
    16'b1111111111110111:begin y_ac_value_r=8'hf3;y_ac_width_r=5'd16;end
    16'b1111111111111000:begin y_ac_value_r=8'hf4;y_ac_width_r=5'd16;end
    16'b1111111111111001:begin y_ac_value_r=8'hf5;y_ac_width_r=5'd16;end
    16'b1111111111111010:begin y_ac_value_r=8'hf6;y_ac_width_r=5'd16;end
    16'b1111111111111011:begin y_ac_value_r=8'hf7;y_ac_width_r=5'd16;end
    16'b1111111111111100:begin y_ac_value_r=8'hf8;y_ac_width_r=5'd16;end
    16'b1111111111111101:begin y_ac_value_r=8'hf9;y_ac_width_r=5'd16;end
    16'b1111111111111110:begin y_ac_value_r=8'hfa;y_ac_width_r=5'd16;end
    default:begin y_ac_value_r=0;y_ac_width_r=0;end
 endcase
end

assign lookup_width_o = y_ac_width_r;
assign lookup_value_o = y_ac_value_r;

endmodule
