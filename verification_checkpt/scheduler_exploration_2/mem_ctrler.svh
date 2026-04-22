`ifndef MEM_CTRLER_SVH
`define MEM_CTRLER_SVH

// ============================================================
//  mem_ctrler.svh  –  Shared types for the fake memory controller
// ============================================================

typedef struct packed {
    logic        valid;
    logic        rw;        // 0=RD, 1=WR
    logic [7:0]  addr;      // original address (kept for reference)
    logic [7:0]  w_data;    // write data (don't-care for reads)
    logic [1:0]  bank;
    logic [1:0]  row;
    logic [1:0]  col;
} fifo_entry_t;

`endif // MEM_CTRLER_SVH
