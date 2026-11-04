`timescale 1ns/1ps
// Round-robin owner for the single sector mailbox in sd_sector_cdc.
// The mailbox requires client_req to be held, with a stable address, until the
// sector's last byte, so a grant may only be released on sector_end. Both
// clients (JPEG frames and the soundtrack) fetch whole sectors, which is what
// makes this workable. Ties alternate so neither stream can starve the other.
module sd_sector_arbiter(
    input  wire        clk,
    input  wire        rst,
    input  wire        a_req,
    input  wire [31:0] a_addr,
    output reg         a_valid,
    output reg         a_end,
    input  wire        b_req,
    input  wire [31:0] b_addr,
    output reg         b_valid,
    output reg         b_end,
    input  wire        sec_valid,
    input  wire [7:0]  sec_data,
    output reg  [7:0]  data,
    input  wire        sec_end,
    output wire        req,
    output reg  [31:0] addr,
    output reg  [1:0]  grant
);
    localparam NONE = 2'd0, A = 2'd1, B = 2'd2;

    reg a_last;
    assign req = (grant == A) ? a_req : ((grant == B) ? b_req : 1'b0);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            grant   <= NONE;
            a_last  <= 0;
            addr    <= 0;
            data    <= 0;
            a_valid <= 0;
            a_end   <= 0;
            b_valid <= 0;
            b_end   <= 0;
        end else begin
            a_valid <= 0;
            a_end   <= 0;
            b_valid <= 0;
            b_end   <= 0;
            data    <= sec_data;
            case (grant)
                NONE: begin
                    if (a_req && b_req) begin
                        if (a_last) begin
                            grant <= B;
                            addr  <= b_addr;
                        end else begin
                            grant <= A;
                            addr  <= a_addr;
                            a_last<= 1;
                        end
                    end else if (a_req) begin
                        grant  <= A;
                        addr   <= a_addr;
                        a_last <= 1;
                    end else if (b_req) begin
                        grant  <= B;
                        addr   <= b_addr;
                        a_last <= 0;
                    end
                end
                A: begin
                    a_valid <= sec_valid;
                    addr    <= a_addr;
                    if (sec_end) begin
                        a_end   <= 1;
                        grant   <= NONE;
                    end
                end
                B: begin
                    b_valid <= sec_valid;
                    addr    <= b_addr;
                    if (sec_end) begin
                        b_end   <= 1;
                        grant   <= NONE;
                    end
                end
                default: grant <= NONE;
            endcase
        end
    end
endmodule
