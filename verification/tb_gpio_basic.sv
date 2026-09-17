`timescale 1ns/1ps
// Basic GPIO Testbench (timing-corrected)
// Tests: DIR write, DATA_OUT write -> readback, DATA_IN capture from external pins
module tb_gpio_basic;

	logic HCLK;
	logic HRESETn;

	logic [31:0] HRDATA;
	logic HREADY;

	logic [31:0] HADDR;
	logic [31:0] HWDATA;
	logic [3:0] HWSTRB;
	logic HWRITE;
	logic [1:0] HTRANS;

	// Testbench Stimulus
	logic [31:0] tb_addr;
	logic [31:0] tb_wdata;
	logic [3:0] tb_wstrb;
	logic tb_write;
	logic [1:0] tb_trans;

	logic [31:0] tb_rdata;

	// GPIO physical pins
	logic [31:0] GPIO_in;
	wire  [31:0] GPIO_out;
	wire  [31:0] GPIO_dir;

	// GPIO register addresses
	localparam ADDR_DIR      = 32'h5000_0000;
	localparam ADDR_DATA_OUT = 32'h5000_0004;
	localparam ADDR_DATA_IN  = 32'h5000_0008;

ahb_bfm AHB_BFM(

	.HCLK(HCLK),
	.HRESETn(HRESETn),

	.HRDATA(HRDATA),
	.HREADY(HREADY),

	.HADDR(HADDR),
	.HWDATA(HWDATA),
	.HWSTRB(HWSTRB),
	.HWRITE(HWRITE),
	.HTRANS(HTRANS),

	.tb_addr(tb_addr),
	.tb_wdata(tb_wdata),
	.tb_wstrb(tb_wstrb),
	.tb_write(tb_write),
	.tb_trans(tb_trans),

	.tb_rdata(tb_rdata)
);

// Standalone: GPIO tested directly, not through ahb_decmux/ahb_peripheral_top
ahb_gpio_sub DUT(

	.HCLK(HCLK),
	.HRESETn(HRESETn),

	.HADDR(HADDR),
	.HWDATA(HWDATA),
	.HWSTRB(HWSTRB),
	.HWRITE(HWRITE),
	.HTRANS(HTRANS),
	.HSEL(1'b1),           // always selected (standalone test)

	.HRDATA(HRDATA),
	.HREADYOUT(HREADY),

	.GPIO_in(GPIO_in),
	.GPIO_out(GPIO_out),
	.GPIO_dir(GPIO_dir)
);

initial begin

	$vcdpluson;
end

initial begin

	HCLK = 0;
	forever #5 HCLK = ~HCLK;
end

// Task: perform one AHB write transaction (address phase + data phase)
task ahb_write(input [31:0] addr, input [31:0] wdata);
begin
	tb_addr  = addr;
	tb_wdata = wdata;
	tb_wstrb = 4'b1111;
	tb_write = 1'b1;
	tb_trans = 2'b10;

	@(posedge HCLK); // address phase captured
	@(posedge HCLK); // data phase completes, register written

	tb_trans = 2'b00; // go idle so it doesn't repeat
	tb_write = 1'b0;

	@(negedge HCLK); // settle before next action / check
end
endtask

// Task: perform one AHB read transaction, result lands in tb_rdata
task ahb_read(input [31:0] addr);
begin
	tb_addr  = addr;
	tb_write = 1'b0;
	tb_trans = 2'b10;

	@(posedge HCLK); // address phase captured
	@(posedge HCLK); // data phase completes, HRDATA valid, BFM captures into tb_rdata

	tb_trans = 2'b00; // go idle

	@(negedge HCLK); // settle
end
endtask

initial begin

	HRESETn = 1'b0;
	GPIO_in = 32'h0000_0000;

	tb_addr  = 32'h0000_0000;
	tb_wdata = 32'h0000_0000;
	tb_wstrb = 4'b0000;
	tb_write = 1'b0;
	tb_trans = 2'b00;

	repeat (2) @(posedge HCLK);

	@(negedge HCLK);
	HRESETn = 1'b1;

	@(negedge HCLK);

	// ---- TEST 1: Write DIR = all output (0xFFFFFFFF) ----
	ahb_write(ADDR_DIR, 32'hFFFF_FFFF);

	if (GPIO_dir === 32'hFFFF_FFFF)
		$display("PASS: DIR REG = %h (expected ffffffff)", GPIO_dir);
	else
		$display("FAIL: DIR REG = %h (expected ffffffff)", GPIO_dir);

	// ---- TEST 2: Write DATA_OUT = 0xA5A5A5A5, check GPIO_out ----
	ahb_write(ADDR_DATA_OUT, 32'hA5A5_A5A5);

	if (GPIO_out === 32'hA5A5_A5A5)
		$display("PASS: GPIO_out = %h (expected a5a5a5a5)", GPIO_out);
	else
		$display("FAIL: GPIO_out = %h (expected a5a5a5a5)", GPIO_out);

	// ---- TEST 3: Read back DATA_OUT register via AHB ----
	ahb_read(ADDR_DATA_OUT);

	if (tb_rdata === 32'hA5A5_A5A5)
		$display("PASS: DATA_OUT READBACK = %h (expected a5a5a5a5)", tb_rdata);
	else
		$display("FAIL: DATA_OUT READBACK = %h (expected a5a5a5a5)", tb_rdata);

	// ---- TEST 4: Drive external GPIO_in, read DATA_IN via AHB ----
	GPIO_in = 32'h1234_5678;
	@(negedge HCLK); // allow synchronous capture into data_in_reg
	@(negedge HCLK); // extra settle margin

	ahb_read(ADDR_DATA_IN);

	if (tb_rdata === 32'h1234_5678)
		$display("PASS: DATA_IN READ = %h (expected 12345678)", tb_rdata);
	else
		$display("FAIL: DATA_IN READ = %h (expected 12345678)", tb_rdata);

	// IDLE
	tb_addr  = 32'h0000_0000;
	tb_wdata = 32'h0000_0000;
	tb_wstrb = 4'b0000;
	tb_write = 1'b0;
	tb_trans = 2'b00;

	#1_000;
	$finish;
end

endmodule
