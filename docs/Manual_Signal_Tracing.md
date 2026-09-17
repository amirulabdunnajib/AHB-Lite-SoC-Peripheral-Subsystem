# Manual Signal & Port Tracing — GPIO Datapaths

Hand-traced signal paths through the GPIO RTL, done as part of a systematic
RTL comprehension workflow: read the port list first, then the internal
logic, then wire declarations, then module instantiations — tracing each
signal from its source to its destination across module boundaries.

Each trace below follows one signal from its entry point (an AHB bus signal
or a physical pin) through every module it passes through, down to where it
finally lands.

---

## 1. GPIO Input Read Path — `GPIO_in` → `HRDATA`

How an external input pin value becomes readable over the AHB bus at the
`DATA_IN` register (offset `0x08`).

```
input  [31:0] GPIO_in                         (ahb_gpio_sub.v port)
   │
   ▼  .GPIO_in(GPIO_in)                        (instantiation into gpio_reg)
input  [31:0] GPIO_in                          (gpio_reg.v port)
   │
   ▼  synchronous capture:
      always @(posedge HCLK or negedge HRESETn)
          data_in_reg <= GPIO_in;
reg [31:0] data_in_reg                         (gpio_reg.v internal register)
   │
   ▼  read mux, selected when reg_addr == ADDR_DATA_IN:
      always @(*)
          case (reg_addr)
              ADDR_DATA_IN: reg_rdata = data_in_reg;
output reg [31:0] reg_rdata                    (gpio_reg.v port)
   │
   ▼  .reg_rdata(HRDATA)                       (instantiation back in ahb_gpio_sub)
output reg [31:0] HRDATA                       (ahb_gpio_sub.v port → AHB bus)
```

**Key point:** `GPIO_in` is *not* combinationally forwarded to the bus — it's
captured synchronously into `data_in_reg` first. A read of `DATA_IN` always
returns the value of `GPIO_in` as of the last clock edge, not the
instantaneous pin value. This is the reasoning behind the "external `GPIO_in`
drive → AHB read" test in `tb_gpio_basic.sv`, which inserts settle cycles
before issuing the read.

---

## 2. DATA_OUT Write Path — `HWDATA` → `GPIO_out`

How a bus write reaches the physical output pins.

```
input  [31:0] HWDATA                           (ahb_gpio_sub.v port, from AHB bus)
   │
   ▼  .reg_wdata(HWDATA)                       (instantiation into gpio_reg)
input  [31:0] reg_wdata                        (gpio_reg.v port)
   │
   ▼  write mux, selected when reg_addr == ADDR_DATA_OUT and reg_write is set:
      always @(posedge HCLK or negedge HRESETn)
          case (reg_addr)
              ADDR_DATA_OUT: data_out_reg <= reg_wdata;
reg [31:0] data_out_reg                        (gpio_reg.v internal register)
   │
   ├──▼  read-back path:
   │     always @(*)
   │         case (reg_addr)
   │             ADDR_DATA_OUT: reg_rdata = data_out_reg;
   │     output reg [31:0] reg_rdata  →  HRDATA   (same path as Trace 1)
   │
   └──▼  physical pin path:
         assign GPIO_out = data_out_reg;
      output [31:0] GPIO_out                   (gpio_reg.v port → physical pin)
```

**Key point:** `data_out_reg` feeds two destinations independently — the
read-back path (so software can read back what it wrote) and the physical
`GPIO_out` pin (so the value actually drives hardware). Both update from the
same register on the same clock edge, so there's no read-back/hardware
mismatch.

---

## 3. DIR Write Path — `HWDATA` → `GPIO_dir`

Structurally identical to Trace 2, targeting the `DIR` register instead of
`DATA_OUT`:

```
input  [31:0] HWDATA
   │
   ▼  .reg_wdata(HWDATA)
input  [31:0] reg_wdata
   │
   ▼  case (reg_addr == ADDR_DIR): dir_reg <= reg_wdata;
reg [31:0] dir_reg
   │
   ├──▼  read-back: case (reg_addr == ADDR_DIR): reg_rdata = dir_reg;  →  HRDATA
   │
   └──▼  physical pin: assign GPIO_dir = dir_reg;
      output [31:0] GPIO_dir
```

---

## 4. Clarifying `HRDATA` vs `GPIO_out` / `GPIO_dir`

These two output ports are easy to conflate at first glance since both
ultimately trace back to the same internal registers — the distinction is
*what each one is for*:

| Signal | Purpose | Driven by |
|---|---|---|
| `HRDATA` | The AHB bus read-data response — whatever register the current `reg_addr` selects | `reg_rdata`, muxed by `reg_addr` on every access |
| `GPIO_out` | The physical output pin state — always reflects `data_out_reg` directly | `data_out_reg`, unconditionally |
| `GPIO_dir` | The physical direction pin state — always reflects `dir_reg` directly | `dir_reg`, unconditionally |

`HRDATA` is a **read window** into whichever register software last asked
for. `GPIO_out`/`GPIO_dir` are **direct, permanent hardware connections** —
they don't depend on what address was last accessed. This is why a read of
`DIR` returns `dir_reg` on `HRDATA`, but `GPIO_dir` reflects `dir_reg`
continuously regardless of whether anyone is reading it at all.

---

## Workflow Notes

This tracing was done by reading each module in a fixed order — ports,
then internal logic (`always` blocks), then wire declarations, then
instantiations — to avoid missing a hop where a signal changes name across
a module boundary (e.g. `HWDATA` → `reg_wdata`, `reg_rdata` → `HRDATA`).
AI-assisted signal/port tracing was used first to shortlist which signals
mattered before manually confirming each path here and building the
corresponding testbench waveforms (see `results/`) to verify the traced
behavior actually holds in simulation.
