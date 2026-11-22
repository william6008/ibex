# Ibex Vivado timing flow

This flow imports `ibex_top` and its lowRISC primitive dependencies into a
Vivado project, then runs out-of-context synthesis, placement, routing, and
timing analysis. Out-of-context mode avoids assigning the CPU's bus ports to
physical package pins, making the result useful for core-level timing
estimation.

## Run

First make Vivado available in the shell. For example:

```sh
source /tools/Xilinx/Vivado/2024.2/settings64.sh
```

From the repository root, run the default `small` configuration at 100 MHz:

```sh
./syn/vivado/run.sh
```

The default part is the Nexys A7-100T (`xc7a100tcsg324-1`). Run `maxperf` at
200 MHz with:

```sh
./syn/vivado/run.sh \
  --part xc7a100tcsg324-1 \
  --period 5.0 \
  --config maxperf \
  --jobs 8
```

Use `./syn/vivado/run.sh --help` for all options. The frequency conversion is:

```text
frequency (MHz) = 1000 / period (ns)
```

For a Nexys A7-50T, select its smaller Artix-7 part instead:

```sh
./syn/vivado/run.sh --part xc7a50tcsg324-1 --period 10.0
```

## Results

Results are written to `build/vivado_ibex/` by default. The main files are:

* `reports/post_route_timing_summary.rpt` - authoritative post-route WNS,
  TNS, hold timing, and unconstrained-path checks.
* `reports/post_route_critical_paths.rpt` - the 50 worst setup paths.
* `reports/post_route_utilization.rpt` - hierarchical FPGA resource usage.
* `reports/fmax_summary.txt` - requested frequency, WNS, and a rough Fmax
  estimate.
* `ibex_post_route.dcp` - routed design checkpoint for inspection in the
  Vivado GUI.

Timing passes at the requested frequency when setup WNS is non-negative, hold
timing also passes, and the report has no unintended unconstrained paths. To
find Fmax, rerun the complete flow with progressively smaller periods. The
rough estimate is only a starting point because synthesis and routing can
change when the timing constraint changes.

The default part and Xilinx primitive mapping target 7-series devices. Change
`--part` for another compatible 7-series FPGA. For a board-level result, put
Ibex inside the complete SoC wrapper and analyze that design with its real
memory, interconnect, clocks, pin constraints, and I/O delays.
