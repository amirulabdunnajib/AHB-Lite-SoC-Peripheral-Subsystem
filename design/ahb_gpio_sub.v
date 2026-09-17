`timescale 1ns/1ps
// AHB Slave Interface for GPIO
// Base address: 0x5000_0000 - 0x5000_00FF
module ahb_gpio_sub(
	input HCLK,
	input HRESETn,

	// AHB signals (from decmux / bus)
	input  [31:0] HADDR,
	input  [31:0] HWDATA,
	input  [3:0]  HWSTRB,
	input         HWRITE,
	input  [1:0]  HTRANS,
	input         HSEL,

	output     [31:0] HRDATA,
	output             HREADYOUT,

	// Physical GPIO pins
	input  [31:0] GPIO_in,
	output [31:0] GPIO_out,
	output [31:0] GPIO_dir
);

	// AHB non-sequential transfer check
	wire ahb_valid = HSEL && (HTRANS == 2'b10);

	// Address phase capture (AHB is pipelined: address phase -> data phase)
	reg        write_ph;
	reg [3:0]  addr_ph;

	always @(posedge HCLK or negedge HRESETn) begin
		if (!HRESETn) begin
			write_ph <= 1'b0;
			addr_ph  <= 4'h0;
		end
		else if (ahb_valid) begin
			write_ph <= HWRITE;
			addr_ph  <= HADDR[3:0];
		end
	end

	// Register file instantiation
	gpio_reg GPIO_REG(
		.HCLK(HCLK),
		.HRESETn(HRESETn),

		.reg_write(write_ph),
		.reg_addr(addr_ph),
		.reg_wdata(HWDATA),
		.reg_rdata(HRDATA),

		.GPIO_in(GPIO_in),
		.GPIO_out(GPIO_out),
		.GPIO_dir(GPIO_dir)
	);

	// Single-cycle access, always ready
	assign HREADYOUT = 1'b1;

endmodule
