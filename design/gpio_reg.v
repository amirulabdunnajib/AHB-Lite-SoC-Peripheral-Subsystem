`timescale 1ns/1ps
// GPIO Register File
// Holds DIRECTION, DATA_OUT, DATA_IN registers
// DIR bit = 1 -> pin is OUTPUT, DIR bit = 0 -> pin is INPUT
module gpio_reg(
	input HCLK,
	input HRESETn,

	// Register write interface (from ahb_gpio_sub)
	input        reg_write,
	input  [3:0] reg_addr,     // register offset (word-aligned: 0x0, 0x4, 0x8)
	input [31:0] reg_wdata,
	output reg [31:0] reg_rdata,

	// Physical GPIO pins
	input  [31:0] GPIO_in,
	output [31:0] GPIO_out,
	output [31:0] GPIO_dir
);

	// Register offsets
	localparam ADDR_DIR      = 4'h0; // 0x00
	localparam ADDR_DATA_OUT = 4'h4; // 0x04
	localparam ADDR_DATA_IN  = 4'h8; // 0x08

	reg [31:0] dir_reg;
	reg [31:0] data_out_reg;
	reg [31:0] data_in_reg;

	// Write logic
	always @(posedge HCLK or negedge HRESETn) begin
		if (!HRESETn) begin
			dir_reg      <= 32'h0000_0000;
			data_out_reg <= 32'h0000_0000;
		end
		else if (reg_write) begin
			case (reg_addr)
				ADDR_DIR:      dir_reg      <= reg_wdata;
				ADDR_DATA_OUT: data_out_reg <= reg_wdata;
				default: ; // DATA_IN is read-only, ignore writes
			endcase
		end
	end

	// Capture input pins (synchronous)
	always @(posedge HCLK or negedge HRESETn) begin
		if (!HRESETn)
			data_in_reg <= 32'h0000_0000;
		else
			data_in_reg <= GPIO_in;
	end

	// Read logic
	always @(*) begin
		case (reg_addr)
			ADDR_DIR:      reg_rdata = dir_reg;
			ADDR_DATA_OUT: reg_rdata = data_out_reg;
			ADDR_DATA_IN:  reg_rdata = data_in_reg;
			default:       reg_rdata = 32'h0000_0000;
		endcase
	end

	// Drive physical pins
	assign GPIO_out = data_out_reg;
	assign GPIO_dir = dir_reg;

endmodule
