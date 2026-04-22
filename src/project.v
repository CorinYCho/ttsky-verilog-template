/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// fifo_entry_t packed layout (24 bits total):
//  [23]    valid
//  [22]    rw
//  [21:14] addr
//  [13:6]  w_data
//  [5:4]   bank
//  [3:2]   row
//  [1:0]   col
`define ENTRY_W      24
`define E_VALID      23
`define E_RW         22
`define E_ADDR       21:14
`define E_WDATA      13:6
`define E_BANK       5:4
`define E_ROW        3:2
`define E_COL        1:0

module tt_um_corin (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire reset  = ~rst_n;

  wire        req_phase = uio_in[3];
  wire        req_rw    = uio_in[4];
  wire        req_valid = uio_in[5];
  wire [7:0]  req_data  = ui_in;

  wire [7:0]  resp_data;
  wire        resp_valid;
  wire        resp_bz;
  wire        resp_rw;

  mem_top u_ctlr (
    .clk      (clk),
    .rst      (reset),
    .req_data (req_data),
    .req_phase(req_phase),
    .req_rw   (req_rw),
    .req_valid(req_valid),
    .resp_data (resp_data),
    .resp_valid(resp_valid),
    .resp_bz   (resp_bz),
    .resp_rw   (resp_rw)
  );

  assign uo_out  = resp_data;
  assign uio_out = {5'b0, resp_valid, resp_bz, resp_rw};
  assign uio_oe  = 8'b0000_0111;

  wire _unused = &{ena, uio_in[7:6], uio_in[2:0], 1'b0};

endmodule


// bank_tracker: tracks which row is open in each bank
module bank_tracker #(
    parameter integer N_BANKS = 2,
    parameter integer ROW_W   = 2
)(
    input  logic                        clk,
    input  logic                        rst,
    input  logic                        req_bank,   // 1-bit: only 2 banks
    input  logic [ROW_W-1:0]            req_row,
    output logic                        is_open,
    output logic                        is_hit,
    output logic                        is_conflict,
    input  logic                        act_en,
    input  logic                        pre_en
);

    logic [N_BANKS-1:0]            open_flag;
    logic [N_BANKS-1:0][ROW_W-1:0] open_row;

    always_comb begin
        is_open     = open_flag[req_bank];
        is_hit      = is_open && (open_row[req_bank] == req_row);
        is_conflict = is_open && (open_row[req_bank] != req_row);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            open_flag <= '0;
            open_row  <= '0;
        end else begin
            if (pre_en) open_flag[req_bank] <= 1'b0;
            if (act_en) begin
                open_flag[req_bank] <= 1'b1;
                open_row[req_bank]  <= req_row;
            end
        end
    end

endmodule : bank_tracker


// fake_memory: single-cycle registered read/write
module fake_memory #(
    parameter integer N_BANKS = 2,
    parameter integer N_ROWS  = 2,
    parameter integer N_COLS  = 2
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       mem_valid,
    input  logic       mem_cmd,       // 0=RD 1=WR
    input  logic [1:0] mem_bank,
    input  logic [1:0] mem_row,
    input  logic [1:0] mem_col,
    input  logic [7:0] mem_wdata,
    output logic       mem_resp_valid,
    output logic [7:0] mem_resp_rdata,
    output logic       mem_resp_rw
);

    logic [N_BANKS-1:0][N_ROWS-1:0][N_COLS-1:0][7:0] mem_arr;

    logic       reg_valid, reg_cmd;
    logic [1:0] reg_bank, reg_row, reg_col;
    logic [7:0] reg_wdata;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_valid      <= 1'b0;
            mem_resp_valid <= 1'b0;
            mem_resp_rdata <= 8'h00;
            mem_resp_rw    <= 1'b0;
            mem_arr        <= '0;
        end else begin
            reg_valid <= mem_valid;
            reg_cmd   <= mem_cmd;
            reg_bank  <= mem_bank;
            reg_row   <= mem_row;
            reg_col   <= mem_col;
            reg_wdata <= mem_wdata;

            mem_resp_valid <= 1'b0;
            if (reg_valid) begin
                mem_resp_valid <= 1'b1;
                mem_resp_rw    <= reg_cmd;
                if (!reg_cmd) begin
                    mem_resp_rdata <= mem_arr[reg_bank][reg_row][reg_col];
                end else begin
                    mem_arr[reg_bank][reg_row][reg_col] <= reg_wdata;
                    mem_resp_rdata                      <= 8'h00;
                end
            end
        end
    end

endmodule : fake_memory


// mem_ctrl: FSM that sequences PRE/ACT/RD/WR commands to fake_memory
module mem_ctrl (
    input  logic        clk,
    input  logic        rst,

    // request interface
    input  logic                  entry_valid,
    input  logic [`ENTRY_W-1:0]   entry_in,
    output logic                  entry_accepted,

    // memory interface
    output logic        mem_valid,
    output logic        mem_cmd,
    output logic [1:0]  mem_bank,
    output logic [1:0]  mem_row,
    output logic [1:0]  mem_col,
    output logic [7:0]  mem_wdata,
    input  logic        mem_resp_valid,
    input  logic [7:0]  mem_resp_rdata,
    input  logic        mem_resp_rw,

    // response interface
    output logic        resp_valid,
    output logic [7:0]  resp_data,
    output logic        resp_bz,
    output logic        resp_rw
);

    // FSM states as localparams (Yosys-safe)
    localparam logic [2:0]
        IDLE  = 3'd0,
        CHECK = 3'd1,
        PRE   = 3'd2,
        ACT   = 3'd3,
        RW    = 3'd4,
        RESP  = 3'd5;

    logic [2:0] cur_state, nxt_state;

    logic [`ENTRY_W-1:0] reg_entry;

    logic is_open, is_hit, is_conflict;
    logic act_en, pre_en;

    // Suppress unused fields (valid, addr are decoded but not forwarded to mem)
    wire _unused_ctrl = &{is_open, reg_entry[`E_VALID], reg_entry[`E_ADDR], 1'b0};

    always_ff @(posedge clk or posedge rst) begin
        if (rst) cur_state <= IDLE;
        else     cur_state <= nxt_state;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) reg_entry <= '0;
        else if (entry_accepted) reg_entry <= entry_in;
    end

    always_comb begin
        nxt_state      = cur_state;
        entry_accepted = 1'b0;
        mem_valid      = 1'b0;
        mem_cmd        = 1'b0;
        mem_bank       = reg_entry[`E_BANK];
        mem_row        = reg_entry[`E_ROW];
        mem_col        = reg_entry[`E_COL];
        mem_wdata      = reg_entry[`E_WDATA];
        act_en         = 1'b0;
        pre_en         = 1'b0;
        resp_valid     = 1'b0;
        resp_data      = 8'h00;
        resp_bz        = 1'b0;
        resp_rw        = 1'b0;

        case (cur_state)
            IDLE: begin
                if (entry_valid) begin
                    entry_accepted = 1'b1;
                    nxt_state      = CHECK;
                end
            end
            CHECK: begin
                resp_bz = 1'b1;
                if (is_hit)           nxt_state = RW;
                else if (is_conflict) nxt_state = PRE;
                else                  nxt_state = ACT;
            end
            PRE: begin
                resp_bz   = 1'b1;
                pre_en    = 1'b1;
                nxt_state = ACT;
            end
            ACT: begin
                resp_bz   = 1'b1;
                act_en    = 1'b1;
                nxt_state = RW;
            end
            RW: begin
                resp_bz   = 1'b1;
                mem_valid = 1'b1;
                mem_cmd   = reg_entry[`E_RW];
                nxt_state = RESP;
            end
            RESP: begin
                resp_bz = 1'b1;
                if (mem_resp_valid) begin
                    resp_valid = 1'b1;
                    resp_data  = mem_resp_rdata;
                    resp_rw    = mem_resp_rw;
                    resp_bz    = 1'b0;
                    nxt_state  = IDLE;
                end
            end
            default: ; // unreachable states
        endcase
    end

    bank_tracker #(
        .N_BANKS(2),
        .ROW_W  (2)
    ) u_bank_tracker (
        .clk        (clk),
        .rst        (rst),
        .req_bank   (reg_entry[4]),    // bit 4 = LSB of E_BANK [5:4]
        .req_row    (reg_entry[`E_ROW]),
        .is_open    (is_open),
        .is_hit     (is_hit),
        .is_conflict(is_conflict),
        .act_en     (act_en),
        .pre_en     (pre_en)
    );

endmodule : mem_ctrl


// mem_top: top-level glue connecting request_queue, mem_ctrl, fake_memory
module mem_top (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  req_data,
    input  logic        req_phase,
    input  logic        req_rw,
    input  logic        req_valid,
    output logic [7:0]  resp_data,
    output logic        resp_valid,
    output logic        resp_bz,
    output logic        resp_rw
);

    logic [`ENTRY_W-1:0] entry_out;
    logic                entry_valid;
    logic                entry_accepted;
    logic                q_full;

    wire _unused_top = &{q_full, 1'b0};

    logic        mem_valid, mem_cmd;
    logic [1:0]  mem_bank, mem_row, mem_col;
    logic [7:0]  mem_wdata;
    logic        mem_resp_valid;
    logic [7:0]  mem_resp_rdata;
    logic        mem_resp_rw;

    request_queue #(.DEPTH(8)) u_rq (
        .clk            (clk),
        .rst            (rst),
        .req_valid      (req_valid),
        .req_rw         (req_rw),
        .req_phase      (req_phase),
        .req_data       (req_data),
        .entry_accepted (entry_accepted),
        .entry_out      (entry_out),
        .entry_valid    (entry_valid),
        .q_full         (q_full)
    );

    mem_ctrl u_ctrl (
        .clk            (clk),
        .rst            (rst),
        .entry_valid    (entry_valid),
        .entry_in       (entry_out),
        .entry_accepted (entry_accepted),
        .mem_valid      (mem_valid),
        .mem_cmd        (mem_cmd),
        .mem_bank       (mem_bank),
        .mem_row        (mem_row),
        .mem_col        (mem_col),
        .mem_wdata      (mem_wdata),
        .mem_resp_valid (mem_resp_valid),
        .mem_resp_rdata (mem_resp_rdata),
        .mem_resp_rw    (mem_resp_rw),
        .resp_valid     (resp_valid),
        .resp_data      (resp_data),
        .resp_bz        (resp_bz),
        .resp_rw        (resp_rw)
    );

    fake_memory #(
        .N_BANKS(2),
        .N_ROWS (2),
        .N_COLS (2)
    ) u_fake_mem (
        .clk            (clk),
        .rst            (rst),
        .mem_valid      (mem_valid),
        .mem_cmd        (mem_cmd),
        .mem_bank       (mem_bank),
        .mem_row        (mem_row),
        .mem_col        (mem_col),
        .mem_wdata      (mem_wdata),
        .mem_resp_valid (mem_resp_valid),
        .mem_resp_rdata (mem_resp_rdata),
        .mem_resp_rw    (mem_resp_rw)
    );

endmodule : mem_top


// rq_fsm: assembles fifo entries from CPU request stream
module rq_fsm (
    input  logic       clk,
    input  logic       rst,
    input  logic       req_valid,
    input  logic       req_rw,
    input  logic       req_phase,
    input  logic [7:0] in_data,
    input  logic [1:0] bank,
    input  logic [1:0] row,
    input  logic [1:0] col,
    input  logic       queue_not_full,
    output logic       entry_ready,
    output logic [`ENTRY_W-1:0] entry
);

    logic [`ENTRY_W-1:0] entry_reg;
    assign entry = entry_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            entry_reg   <= '0;
            entry_ready <= 1'b0;
        end else if (req_valid && queue_not_full) begin
            if (!req_rw) begin // read request
                entry_ready          <= 1'b1;
                entry_reg[`E_VALID]  <= 1'b1;
                entry_reg[`E_RW]     <= 1'b0;
                entry_reg[`E_ADDR]   <= in_data;
                entry_reg[`E_WDATA]  <= 8'h00;
                entry_reg[`E_BANK]   <= bank;
                entry_reg[`E_ROW]    <= row;
                entry_reg[`E_COL]    <= col;
            end else begin // write request
                if (!req_phase) begin // address phase
                    entry_ready          <= 1'b0;
                    entry_reg[`E_ADDR]   <= in_data;
                    entry_reg[`E_BANK]   <= bank;
                    entry_reg[`E_ROW]    <= row;
                    entry_reg[`E_COL]    <= col;
                    entry_reg[`E_VALID]  <= 1'b0;
                    entry_reg[`E_RW]     <= 1'b1;
                end else begin // data phase
                    entry_ready          <= 1'b1;
                    entry_reg[`E_WDATA]  <= in_data;
                    entry_reg[`E_VALID]  <= 1'b1;
                end
            end
        end else begin
            entry_ready <= 1'b0;
        end
    end

endmodule : rq_fsm


// decode_addr: combinational address decoder
module decode_addr (
    input  logic [7:0] addr,
    output logic [1:0] bank,
    output logic [1:0] row,
    output logic [1:0] col
);
    always_comb begin
        bank = addr[7:6];
        row  = addr[5:4];
        col  = addr[3:2];
    end
    wire _unused_dec = &{addr[1:0], 1'b0};

endmodule : decode_addr


// request_queue: FIFO that holds pending memory requests
module request_queue #(
    parameter integer DEPTH = 4,
    parameter integer PTR_W = $clog2(DEPTH)
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       req_valid,
    input  logic       req_rw,
    input  logic       req_phase,
    input  logic [7:0] req_data,
    input  logic       entry_accepted,
    output logic [`ENTRY_W-1:0] entry_out,
    output logic       entry_valid,
    output logic       q_full
);

    logic [1:0] dec_bank, dec_row, dec_col;
    logic       entry_ready;
    logic [`ENTRY_W-1:0] assembled_entry;

    logic [`ENTRY_W-1:0] fifo_mem [0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic [PTR_W:0]   count;

    localparam [PTR_W:0] DEPTH_SIZED = DEPTH[PTR_W:0];

    assign q_full      = (count == DEPTH_SIZED);
    assign entry_valid = (count != '0);
    assign entry_out   = fifo_mem[rd_ptr];

    decode_addr u_decode (
        .addr (req_data),
        .bank (dec_bank),
        .row  (dec_row),
        .col  (dec_col)
    );

    rq_fsm u_rq_fsm (
        .clk            (clk),
        .rst            (rst),
        .req_valid      (req_valid),
        .req_rw         (req_rw),
        .req_phase      (req_phase),
        .in_data        (req_data),
        .bank           (dec_bank),
        .row            (dec_row),
        .col            (dec_col),
        .queue_not_full (~q_full),
        .entry_ready    (entry_ready),
        .entry          (assembled_entry)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            if (entry_ready && !q_full) begin
                fifo_mem[wr_ptr] <= assembled_entry;
                wr_ptr           <= wr_ptr + 1'b1;
                count            <= count + 1'b1;
            end
            if (entry_accepted && entry_valid) begin
                rd_ptr <= rd_ptr + 1'b1;
                count  <= count - 1'b1;
            end
        end
    end

endmodule : request_queue

