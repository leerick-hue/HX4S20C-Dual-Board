
module sd_card_sec_read_write
#(
	parameter  SPI_LOW_SPEED_DIV = 248,         // spi clk speed = clk speed /((SPI_LOW_SPEED_DIV + 2) * 2 )
	parameter POWERUP_CYCLES = 100000,
	parameter  SPI_HIGH_SPEED_DIV = 0           // spi clk speed = clk speed /((SPI_HIGH_SPEED_DIV + 2) * 2 )
)
(
	input            clk,
	input            rst,
	output reg       sd_init_done,
	input            sd_sec_read,
	input[31:0]      sd_sec_read_addr,
	output[7:0]      sd_sec_read_data,
	output           sd_sec_read_data_valid,
	output           sd_sec_read_end,
	input            sd_sec_write,
	input[31:0]      sd_sec_write_addr,
	input[7:0]       sd_sec_write_data,
	output           sd_sec_write_data_req,
	output           sd_sec_write_end,

	output reg[15:0] spi_clk_div,
	output reg       cmd_req,
	input            cmd_req_ack,
	input            cmd_req_error,
    input [7:0] response_r1,
    input [31:0] response_data,
	output reg[47:0] cmd,
	output reg[7:0]  cmd_r1,
	output reg[15:0] cmd_data_len,
	output reg       block_read_req,
	input            block_read_valid,
	input[7:0]       block_read_data,
	input            block_read_req_ack,
	output reg       block_write_req,
	output[7:0]      block_write_data,
	input            block_write_data_rd,
	input            block_write_req_ack
);
// SDSC v1/v2 and SDHC SPI initialization. CMD58 CCS selects address units.
localparam POWER=0, ISSUE=1, WAIT_CMD=2, READY=3, READ_DATA=4,
           READ_END=5, WRITE_DATA=6, WRITE_END=7, RELEASE=8,
           READ_RELEASE=9;
reg [3:0] state;
reg [5:0] command_id;
reg [31:0] power_count, command_arg, sec_addr;
reg version2, block_addressed;
assign sd_sec_read_data_valid = state==READ_DATA && block_read_valid;
assign sd_sec_read_data = block_read_data;
assign sd_sec_read_end = state==READ_END;
assign sd_sec_write_data_req = state==WRITE_DATA && block_write_data_rd;
assign block_write_data = sd_sec_write_data;
assign sd_sec_write_end = state==WRITE_END;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  state<=POWER; power_count<=0; command_id<=0; command_arg<=0;
  version2<=0; block_addressed<=0; sd_init_done<=0;
  cmd_req<=0; cmd<=0; cmd_r1<=0; cmd_data_len<=0;
  block_read_req<=0; block_write_req<=0; sec_addr<=0;
  spi_clk_div<=SPI_LOW_SPEED_DIV;
 end else case(state)
 POWER: if(power_count==POWERUP_CYCLES-1) begin
  command_id<=0;command_arg<=0;state<=ISSUE;
 end else power_count<=power_count+1'b1;
 ISSUE: begin
  cmd_req<=1; state<=WAIT_CMD;
  cmd<={2'b00,command_id,command_arg,8'hff};
  cmd_data_len<=0;cmd_r1<=0;
  case(command_id)
   0: begin cmd<={8'd0,32'd0,8'h95};cmd_r1<=1;end
   8: begin cmd<={8'd8,32'h1aa,8'h87};cmd_r1<=1;cmd_data_len<=4;end
   55: cmd_r1<=1;
   58: cmd_data_len<=4;
   default: begin end
  endcase
 end
 WAIT_CMD: if(cmd_req_ack) begin
  cmd_req<=0;state<=RELEASE;
  case(command_id)
   0: if(!cmd_req_error) begin command_id<=8;command_arg<=32'h1aa;end
   8: begin
    if(!cmd_req_error && response_data[11:0]==12'h1aa) begin
     version2<=1;command_id<=55;command_arg<=0;
    end else if(response_r1==8'h05) begin
     // Legacy SDSC reports idle + illegal CMD8. Do not mistake timeout for v1.
     version2<=0;command_id<=55;command_arg<=0;
    end
   end
   55: if(!cmd_req_error) begin command_id<=41;command_arg<=version2?32'h40000000:0;end
   41: begin
    if(!cmd_req_error) begin command_id<=58;command_arg<=0;end
    else begin command_id<=55;command_arg<=0;end
   end
   58: if(!cmd_req_error && response_data[31]) begin
    block_addressed<=version2 && response_data[30];
    if(version2 && response_data[30]) begin
     sd_init_done<=1;spi_clk_div<=SPI_HIGH_SPEED_DIV;state<=READY;
    end else begin command_id<=16;command_arg<=512;end
   end
   16: if(!cmd_req_error) begin
    sd_init_done<=1;spi_clk_div<=SPI_HIGH_SPEED_DIV;state<=READY;
   end
   17: if(!cmd_req_error) begin block_read_req<=1;state<=READ_DATA;end
   24: if(!cmd_req_error) begin block_write_req<=1;state<=WRITE_DATA;end
   default: begin command_id<=0;command_arg<=0;end
  endcase
 end
 RELEASE: if(!cmd_req_ack) state<=ISSUE;
 READY: begin
  if(sd_sec_write) begin
   command_id<=24;
   command_arg<=block_addressed?sd_sec_write_addr:(sd_sec_write_addr<<9);
   state<=ISSUE;
  end else if(sd_sec_read) begin
   command_id<=17;
   command_arg<=block_addressed?sd_sec_read_addr:(sd_sec_read_addr<<9);
   state<=ISSUE;
  end
 end
 READ_DATA: if(cmd_req_ack && cmd_req_error) begin
  // The token timed out before any sector bytes were delivered. Reissue the
  // same CMD17/address; retain the client's request and do not report a false end.
  block_read_req<=0;state<=RELEASE;
 end else if(block_read_req_ack) begin block_read_req<=0;state<=READ_END;end
 // End is a one-cycle pulse, but a client in another clock domain cannot
 // withdraw its held request immediately. Do not accept that same request
 // twice: wait until the client has observed completion and released it.
 READ_END: state<=READ_RELEASE;
 READ_RELEASE: if(!sd_sec_read)state<=READY;
 WRITE_DATA: if(block_write_req_ack) begin block_write_req<=0;state<=WRITE_END;end
 WRITE_END: state<=READY;
 default: begin state<=POWER;power_count<=0;sd_init_done<=0;end
 endcase
end
endmodule
