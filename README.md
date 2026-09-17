# AHB-Lite SoC Peripheral Subsystem

A Verilog/SystemVerilog implementation of AMBA AHB-Lite peripherals for a small
SoC-style CPU system, built around a shared bus architecture inspired by
AMBA AHB-Lite. This repo documents an in-progress RTL design and verification
project, developed to `SOC_Design_Specification_For_Students.pdf`, with a
PicoRV32 RISC-V core as the intended system CPU.

> **Status:** GPIO peripheral fully designed, verified, and integrated into
> the top-level bus. Actively extending to the remaining peripherals
> (UART, SPI, I2C, SRAM) using the same design and verification pattern.

---

## Repository Structure

```
├── design/
│   ├── gpio_reg.v              # GPIO register file (DIR / DATA_OUT / DATA_IN)
│   ├── ahb_gpio_sub.v          # AHB-Lite slave interface for GPIO
│   ├── ahb_gpio_wrapper.v      # Top-level instantiation wrapper (interface parity)
│   ├── ahb_decmux.v            # Address decoder + response multiplexer (5 slaves)
│   └── ahb_peripheral_top.v    # Top-level integration of all peripheral slaves
├── verification/
│   ├── ahb_bfm.v               # AHB Bus Functional Model (verification master)
│   └── tb_gpio_basic.sv        # GPIO directed testbench
├── docs/
│   ├── debug-log.md            # Debugged testbench hang (HREADY polling vs hardwired HREADYOUT)
│   ├── Manual_Signal_Tracing.md # Hand-traced signal datapaths through the GPIO RTL
│   └── IHI0033C_amba_ahb_protocol_spec.pdf
├── results/
│   ├── Simulation_Log.txt
│   ├── ReadPhase_Test1&2_TestbenchWaveform.png
│   └── WritePhase_Test3&4_TestbenchWaveform.png
└── README.md
```

---

## Architecture

The system follows a shared AHB-Lite bus architecture: a single active
transaction at a time, memory-mapped peripherals, and a ready/valid handshake.
`ahb_decmux` performs address decoding (selecting one of five slaves) and
multiplexes the response (`HRDATA` / `HREADY`) back to the bus based on which
slave is currently selected.

| Slave | Address Range | Status |
|---|---|---|
| SRAM | `0x0000_0000` – `0x0000_FFFF` | Per spec — not yet implemented |
| UART | `0x2000_0000` – `0x2000_00FF` | Per spec — not yet implemented |
| SPI | `0x3000_0000` – `0x3000_00FF` | Per spec — not yet implemented |
| I2C | `0x4000_0000` – `0x4000_00FF` | Per spec — not yet implemented |
| **GPIO** | `0x5000_0000` – `0x5000_00FF` | **Designed, verified, integrated** |

GPIO was added as an extension beyond the supervisor-issued spec (which
covers SRAM, DMA, UART, SPI, and I2C) to practice the full design →
verification → integration flow independently before tackling the
remaining peripherals.

### GPIO Register Map

| Offset | Register | Access | Description |
|---|---|---|---|
| `0x00` | `DIR` | R/W | Pin direction (1 = output, 0 = input) |
| `0x04` | `DATA_OUT` | R/W | Drives output pins |
| `0x08` | `DATA_IN` | R (read-only) | Synchronously captured input pins |

---

## Current Progress

### ✅ GPIO Peripheral — Designed & Verified

- **`gpio_reg.v`** — register file implementing DIR, DATA_OUT, and DATA_IN,
  with synchronous capture of external input pins
- **`ahb_gpio_sub.v`** — AHB-Lite slave interface handling the two-phase
  pipelined address/data transfer (`HADDR`, `HWDATA`, `HWRITE`, `HTRANS`,
  `HSEL` → `HRDATA`, `HREADYOUT`)
- **`ahb_gpio_wrapper.v`** — thin top-level wrapper giving GPIO the same
  `ahb_<periph>_wrapper` instantiation convention as the other slaves, so it
  drops into `ahb_peripheral_top.v` consistently

### ✅ Bus Integration — GPIO Connected as 5th Slave

- Extended `ahb_decmux` from 4 to 5 slaves (`mux_select` widened to 3 bits),
  adding `HSEL_S4` / `HRDATA_S4` / `HREADYOUT_S4` for GPIO
- Wired `ahb_gpio_wrapper` into `ahb_peripheral_top.v` alongside the SRAM,
  UART, SPI, and I2C slave slots, sharing the common `HADDR` / `HWDATA` /
  `HTRANS` / `HREADY` bus signals

### ✅ Verification — Directed Testbench, All Passing

`tb_gpio_basic.sv` drives the DUT through `ahb_bfm.v` (a verification-only
AHB bus functional model) and checks four directed scenarios:

```
PASS: DIR REG = ffffffff (expected ffffffff)
PASS: GPIO_out = a5a5a5a5 (expected a5a5a5a5)
PASS: DATA_OUT READBACK = a5a5a5a5 (expected a5a5a5a5)
PASS: DATA_IN READ = 12345678 (expected 12345678)
```
*(Synopsys VCS V-2023.12-SP2, full log in [`results/Simulation_Log.txt`](results/Simulation_Log.txt))*

**Waveform evidence** (captured in DVE):
- [`ReadPhase_Test1&2_TestbenchWaveform.png`](results/ReadPhase_Test1&2_TestbenchWaveform.png) — DIR write and DATA_OUT write, traced from `tb_addr`/`tb_wdata` through the BFM, into `ahb_gpio_sub`'s address-phase capture (`addr_ph`), and into `dir_reg` / `data_out_reg`
- [`WritePhase_Test3&4_TestbenchWaveform.png`](results/WritePhase_Test3&4_TestbenchWaveform.png) — DATA_OUT readback and external `GPIO_in` capture, confirming `GPIO_dir` and `data_out_reg` update correctly and on time

### ✅ Debugged: Simulation Hang

Found and resolved a real simulation hang, not just a cosmetic bug — full
writeup in [`docs/debug-log.md`](docs/debug-log.md).

**Summary:** An earlier testbench polled `HREADY` in a `while` loop to detect
transfer completion. But `ahb_gpio_sub.v`'s `HREADYOUT` is hardwired high
(`assign HREADYOUT = 1'b1`) since this is a zero-wait-state slave — so the
signal transition the loop was waiting for could never occur, causing an
infinite loop. Fixed by replacing polling with fixed two-cycle
(address-phase + data-phase) timing in `tb_gpio_basic.sv`, which correctly
matches this slave's deterministic response timing.

### ✅ RTL Comprehension Workflow

Developed and applied a systematic method for reading unfamiliar RTL —
ports → internal logic → wire declarations → module instantiations — to
trace how data actually flows through a design. Applied it directly to the
GPIO register file, documented signal-by-signal in
[`docs/Manual_Signal_Tracing.md`](docs/Manual_Signal_Tracing.md) (e.g. tracing
`GPIO_in` → `data_in_reg` → `reg_rdata` → `HRDATA`). Combined this with
AI-assisted signal/port tracing to speed up identifying key signals before
manually building the waveforms above to confirm design behavior.

---

## Known Design Notes

Honest, self-identified limitations in the current implementation —
tracked here rather than hidden, and feeding directly into the roadmap below:

- **`HREADYOUT` is hardwired high** in `ahb_gpio_sub.v` — valid for a
  zero-wait-state slave (which GPIO genuinely is), but means the interface
  can't yet express a "not ready" state. This will need to change once
  slower peripherals (SRAM, UART, SPI, I2C) are added, since some of them
  will require real wait states.
- **Single-flop synchronizer on `GPIO_in`** — functionally captures external
  input correctly in simulation, but a single flop carries metastability
  risk in real hardware; a proper 2-flop synchronizer is planned.
- **`HWSTRB` is currently unused** in the GPIO slave (byte-lane strobing not
  yet implemented — all writes are full-word).

---

## Tools & Environment

| Purpose | Tool |
|---|---|
| RTL / Testbench editing | VS Code |
| Compilation & Simulation | Synopsys VCS (V-2023.12-SP2) |
| Waveform Debug | DVE / Verdi |
| Languages | Verilog, SystemVerilog |
| Protocol Reference | AMBA AHB Protocol Specification (IHI0033C) |

---

## Roadmap

Development follows a dependency-ordered sequence — each phase is chosen to
avoid rework in the phase after it (e.g., fixing wait-state support *before*
integrating more peripherals, so integration testing exercises real timing
behavior instead of the current always-ready assumption).

### Phase 1 — Harden the GPIO Design *(in progress)*
- Add wait-state support to `ahb_gpio_sub.v` (`HREADYOUT` conditional instead
  of hardwired), and update `tb_gpio_basic.sv` accordingly
- Replace the single-flop `GPIO_in` synchronizer with a proper 2-flop design
- Continuing AMBA AHB-Lite protocol study (IHI0033C) in parallel to inform
  this and later phases

### Phase 2 — Extend the Peripheral Set
- Design and verify UART (transmitter, receiver, baud-rate generator,
  TXDATA/RXDATA/STATUS/CONTROL registers per spec), reusing the GPIO
  design-then-verify pattern
- Follow with SPI (master mode, clock generation, MOSI/MISO, chip select)
  and I2C
- Bring up the SRAM memory controller interfacing to the Synopsys SAED32
  generic memory macro

### Phase 3 — Full SoC-Level Integration
- Extend `ahb_peripheral_top.v` bring-up to all five slaves with real
  (non-stub) peripheral logic behind each wrapper
- Re-verify `ahb_decmux` under multi-peripheral, variable-latency conditions
  now that wait-states exist

### Phase 4 — Verification Maturity
- Add SVA assertions for AHB protocol rules (`HTRANS` stability, `HREADY`
  behavior, address-phase/data-phase consistency)
- Add functional coverage (all register addresses, read/write, reset)
- Introduce constrained-random testing on top of the existing directed tests

### Phase 5 — CPU Integration
- Study the PicoRV32 bus interface and bridge it to AHB-Lite
- Replace `ahb_bfm.v` with PicoRV32 as the real AHB master
- Run firmware that exercises GPIO/UART/SPI/I2C directly from the CPU,
  demonstrating the full path from instruction execution to physical pin

---

## Reference Documents

- `IHI0033C_amba_ahb_protocol_spec.pdf` — AMBA AHB Protocol Specification
- `SOC_Design_Specification_For_Students.pdf` — project specification
- `PicoRV32_Spec.pdf` — CPU core reference for Phase 5 integration
