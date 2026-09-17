`timescale 1ns/1ps
// AHB GPIO Wrapper
// Base address: 0x5000_0000 - 0x5000_00FF
//
// Matches the ahb_<periph>_wrapper convention used by the SRAM/UART/SPI/I2C
// wrappers so GPIO can be instantiated at ahb_peripheral_top the same way as
// the other slaves.
//
// Unlike the other peripherals, ahb_gpio_sub already performs its own address
// -phase pipelining and instantiates gpio_reg directly (no separate sl_* bus
// or *_controller stage), so this wrapper is a thin pass-through that just
// gives GPIO a top-level instance name/port list consistent with its siblings.
module ahb_gpio_wrapper(

	input HCLK,
	input HRESETn,

	input [31:0] HADDR,
	input [31:0] HWDATA,
	input [3:0] HWSTRB,
	input HWRITE,

	input HSEL,
	input [1:0] HTRANS,
	input HREADY,      // unused: ahb_gpio_sub is single-cycle/always-ready.
	                   // Kept in the port list purely for interface parity
	                   // with the other _wrapper modules.

	output [31:0] HRDATA,
	output HREADYOUT,

	// Physical GPIO pins
	input  [31:0] GPIO_in,
	output [31:0] GPIO_out,
	output [31:0] GPIO_dir
);

ahb_gpio_sub AHB_GPIO_SUB(

	.HCLK      (HCLK),
	.HRESETn   (HRESETn),
	.HADDR     (HADDR),
	.HWDATA    (HWDATA),
	.HWSTRB    (HWSTRB),
	.HWRITE    (HWRITE),
	.HTRANS    (HTRANS),
	.HSEL      (HSEL),
	.HRDATA    (HRDATA),
	.HREADYOUT (HREADYOUT),
	.GPIO_in   (GPIO_in),
	.GPIO_out  (GPIO_out),
	.GPIO_dir  (GPIO_dir)
);

endmodule
