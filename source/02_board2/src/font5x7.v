`timescale 1ns/1ps
// Original 5x7 ASCII glyph ROM. Bit 34 is the upper-left dot.
module font5x7(input wire [7:0] character, input wire [2:0] column,
               input wire [2:0] row, output reg pixel);
    reg [34:0] glyph;
    always @* begin
        case(character)
            8'd32: glyph=35'h000000000; //  
            8'd48: glyph=35'h3a33ae62e; // 0
            8'd49: glyph=35'h11842108e; // 1
            8'd50: glyph=35'h3a211111f; // 2
            8'd51: glyph=35'h78217043e; // 3
            8'd52: glyph=35'h08ca97c42; // 4
            8'd53: glyph=35'h7e10f043e; // 5
            8'd54: glyph=35'h3a10f462e; // 6
            8'd55: glyph=35'h7c2222108; // 7
            8'd56: glyph=35'h3a317462e; // 8
            8'd57: glyph=35'h3a317842e; // 9
            8'd65: glyph=35'h3a31fc631; // A
            8'd66: glyph=35'h7a31f463e; // B
            8'd67: glyph=35'h3e108420f; // C
            8'd68: glyph=35'h7a318c63e; // D
            8'd69: glyph=35'h7e10f421f; // E
            8'd70: glyph=35'h7e10f4210; // F
            8'd71: glyph=35'h3e10bc62f; // G
            8'd72: glyph=35'h4631fc631; // H
            8'd73: glyph=35'h38842108e; // I
            8'd74: glyph=35'h04210c62e; // J
            8'd75: glyph=35'h4654c5251; // K
            8'd76: glyph=35'h42108421f; // L
            8'd77: glyph=35'h4775ac631; // M
            8'd78: glyph=35'h47359c631; // N
            8'd79: glyph=35'h3a318c62e; // O
            8'd80: glyph=35'h7a31f4210; // P
            8'd81: glyph=35'h3a318d64d; // Q
            8'd82: glyph=35'h7a31f5251; // R
            8'd83: glyph=35'h3e107043e; // S
            8'd84: glyph=35'h7c8421084; // T
            8'd85: glyph=35'h46318c62e; // U
            8'd86: glyph=35'h46318c544; // V
            8'd87: glyph=35'h4631ad6aa; // W
            8'd88: glyph=35'h462a22a31; // X
            8'd89: glyph=35'h462a21084; // Y
            8'd90: glyph=35'h7c222221f; // Z
            8'd58: glyph=35'h008401080; // :
            8'd46: glyph=35'h0000000c6; // .
            8'd43: glyph=35'h0084f9080; // +
            8'd45: glyph=35'h0000f8000; // -
            8'd47: glyph=35'h044422210; // /
            default:glyph=0;
        endcase
        pixel=0;
        if(column<5 && row<7) pixel=glyph[34-row*5-column];
    end
endmodule
