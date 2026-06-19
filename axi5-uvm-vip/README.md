# AXI5-UVM-VIP

A complete, reusable **UVM Verification IP (VIP) for AMBA AXI5** (ARM IHI 0022H),
with full coverage, an assertion-based protocol checker, a scoreboard, and a
corner-case sequence library.

> Status: synthesizable-free, simulator-agnostic UVM source. Tested structure
> targets IEEE 1800-2017 SystemVerilog + UVM 1.2 / IEEE 1800.2-2020.

## Features

- **Full AXI5 channel set**: AW, W, B, AR, R with AXI5 sidebands.
- **AXI5 additions**: `AWATOP` atomic ops, QoS, Region, `AWUNIQUE`, `AxTRACE`,
  `AxLOOP`, MMU/MPAM sideband wiring (`AxMMUVALID`), and Wakeup (`AWAKEUP`).
- **Exclusive access** monitor (EXOKAY pairing), **atomic transactions**
  (store/load/swap/compare), and **QoS/Region** decoding.
- **Configurable widths**: address/data/id/user are macro-driven and scale the
  whole VIP together (override `+define+AXI5_DATA_WIDTH=128`, etc.).
- **Master & slave agents**, active/passive, with a shared analysis fabric.
- **Protocol checker**: SVA assertions for handshake stability, 4KB boundary,
  burst legality, exclusive length/alignment, response rules, X-checks.
- **Functional coverage**: per-channel covergroups with cross-coverage of
  len×size×burst, response×exclusive, atomic-op×size, QoS, and corner bins.
- **Scoreboard**: in-order & out-of-order (per-ID) write/read checking with a
  reference memory model.
- **Corner-case sequence library**: narrow/unaligned, WRAP boundaries, max-len
  bursts, single-beat, back-to-back, interleaved IDs, exclusive pass/fail,
  atomics, 4KB-edge, write-strobe holes, zero-delay & max-backpressure.

## Repository layout

```
axi5-uvm-vip/
├── README.md
├── LICENSE
├── Makefile                  # questa/vcs/xcelium/lint targets
├── .gitignore
├── .github/workflows/ci.yml  # Verilator lint + structure check
├── rtl/
│   └── axi5_slave_mem.sv      # simple AXI5 slave memory (DUT)
├── sim/
│   ├── filelist.f
│   └── run.f
├── tb/
│   └── axi5_tb_top.sv
└── src/
    ├── axi5_if.sv             # interface + clocking blocks + SVA bind
    ├── axi5_sva_checker.sv    # bound protocol-assertion module
    ├── axi5_pkg.sv            # the UVM package (includes everything below)
    └── uvm/
        ├── axi5_defines.svh   # width macros (compile first)
        ├── axi5_types.svh
        ├── axi5_seq_item.svh
        ├── axi5_config.svh
        ├── axi5_sequencer.svh
        ├── axi5_driver.svh
        ├── axi5_monitor.svh
        ├── axi5_coverage.svh
        ├── axi5_protocol_checker.svh
        ├── axi5_scoreboard.svh
        ├── axi5_ref_mem.svh
        ├── axi5_agent.svh
        ├── axi5_env.svh
        ├── seq/
        │   ├── axi5_base_seq.svh
        │   ├── axi5_write_seq.svh
        │   ├── axi5_read_seq.svh
        │   ├── axi5_corner_seqs.svh
        │   └── axi5_reg_traffic_seq.svh
        └── test/
            ├── axi5_base_test.svh
            ├── axi5_smoke_test.svh
            └── axi5_corner_test.svh
```

## Quick start

```bash
git clone https://github.com/kaushikvelapareddy-vlsi/AXI5_UVM_VIP
cd axi5-uvm-vip

# Questa / ModelSim
make questa TEST=axi5_smoke_test

# Synopsys VCS
make vcs TEST=axi5_corner_test

# Cadence Xcelium
make xcelium TEST=axi5_corner_test

# List available tests
make help
```

All three flows compile the same `sim/filelist.f` and run the UVM test named by
`TEST=` (passed via `+UVM_TESTNAME`). Seeds: `SEED=random` or `SEED=<int>`.

## ARM specification compliance

This VIP targets the **AMBA AXI and ACE Protocol Specification, AXI5 (IHI
0022H)**.The protocol
checker encodes the normative rules; the coverage model targets the
specification's transaction space. Cache-coherency (ACE5) snoop channels are
out of scope for this AXI5-Full release and are tracked as a roadmap item.

## License

MIT — see [LICENSE](LICENSE).
