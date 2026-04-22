`default_nettype none
`timescale 1ns/1ps
`include "mem_ctrler.svh"

module bank_tracker #(
    parameter int N_BANKS = 2,
    parameter int ROW_W   = 2
)(
    input  logic                        clk,
    input  logic                        rst,

    // query
    input  logic [$clog2(N_BANKS)-1:0]  req_bank,
    input  logic [ROW_W-1:0]            req_row,
    output logic                        is_open,
    output logic                        is_hit,
    output logic                        is_conflict,

    // fsm updates
    input  logic                        act_en,   // activate: open req_row in req_bank
    input  logic                        pre_en    // precharge: close req_bank
);

    logic [N_BANKS-1:0]                 open_flag;
    logic [N_BANKS-1:0][ROW_W-1:0]      open_row;

    
    always_comb begin
        is_open     = open_flag[req_bank];
        is_hit      = is_open && (open_row[req_bank] == req_row);
        is_conflict = is_open && (open_row[req_bank] != req_row);
    end


    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < N_BANKS; i++) begin
                open_flag[i] <= '0;
                open_row[i]  <= '0;
            end
        end else begin
            if (pre_en) begin
                open_flag[req_bank] <= 1'b0;
            end
            if (act_en) begin
                open_flag[req_bank] <= 1'b1;
                open_row[req_bank]  <= req_row;
            end
        end
    end

endmodule : bank_tracker



//    fake_memory
//    single cycle read and write latency for now
//
//    mem_cmd, indicates read(0) or write (1)

//    mem_bank, tells memory which bank
//    mem_row , tells memory which row
//    mem_col , tells memory which col
//    mem_wdata, write data for write command


module fake_memory #(
    parameter int N_BANKS = 2,
    parameter int N_ROWS  = 4,
    parameter int N_COLS  = 4
)(
    input  logic                        clk,
    input  logic                        rst,

    input  logic                        mem_valid,
    input  logic                        mem_cmd,        // 0=RD 1=WR
    input  logic [$clog2(N_BANKS):0]    mem_bank,
    input  logic [$clog2(N_ROWS):0]     mem_row,
    input  logic [$clog2(N_COLS):0]     mem_col,
    input  logic [7:0]                  mem_wdata,

    output logic                        mem_resp_valid,
    output logic [7:0]                  mem_resp_rdata,
    output logic                        mem_resp_rw
);

    // memory array
    logic [N_BANKS-1:0][N_ROWS-1:0][N_COLS-1:0][7:0] mem_arr;

    // register to account for cycle delay
    logic        reg_valid;
    logic        reg_cmd;
    logic [1:0]  reg_bank, reg_row, reg_col;
    logic [7:0]  reg_wdata;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_valid      <= 1'b0;
            mem_resp_valid <= 1'b0;
            mem_resp_rdata <= 8'h00;
            mem_resp_rw    <= 1'b0;
            mem_arr        <= 'd0;
        end else begin
            // register incoming commands
            reg_valid <= mem_valid;
            reg_cmd   <= mem_cmd;
            reg_bank  <= mem_bank;
            reg_row   <= mem_row;
            reg_col   <= mem_col;
            reg_wdata <= mem_wdata;

            // execute response, response ready the following cycle
            mem_resp_valid <= 1'b0;
            if (reg_valid) begin
                mem_resp_valid <= 1'b1;
                mem_resp_rw    <= reg_cmd;
                if (!reg_cmd) begin // read
                    mem_resp_rdata <= mem_arr[reg_bank][reg_row][reg_col];
                end else begin // write
                    mem_arr[reg_bank][reg_row][reg_col] <= reg_wdata;
                    mem_resp_rdata                      <= 8'h00;
                end
            end
        end
    end

endmodule : fake_memory



//  memory controller


module mem_ctrl (
    input  logic        clk,
    input  logic        rst,

    // request interface
    input  logic        entry_valid,
    input  fifo_entry_t entry_in,
    output logic        entry_accepted, // pop signal (one-cycle pulse)

    // memory interface
    output logic        mem_valid,
    output logic        mem_cmd,        // read (0), write (1)
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
    output logic        resp_bz,        // busy: not yet ready to accept new req
    output logic        resp_rw
);

    typedef enum logic [2:0] {
        IDLE  = 3'd0,
        CHECK = 3'd1,   // one cycle to read bank_tracker output
        PRE   = 3'd2,   // precharge conflicting row
        ACT   = 3'd3,   // activate target row
        RW    = 3'd4,   // issue RD or WR to fake_memory
        RESP  = 3'd5    // forward response to CPU
    } state_t;

    state_t cur_state, nxt_state;

    // register entry
    fifo_entry_t reg_entry;

  
    logic is_open, is_hit, is_conflict;
    logic act_en, pre_en;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) cur_state <= IDLE;
        else     cur_state <= nxt_state;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_entry <= '0;
        end else if (entry_accepted) begin
            reg_entry <= entry_in;
        end
    end


    always_comb begin
        nxt_state      = cur_state;
        entry_accepted = 1'b0;
        mem_valid      = 1'b0;
        mem_cmd        = 1'b0;
        mem_bank       = reg_entry.bank;
        mem_row        = reg_entry.row;
        mem_col        = reg_entry.col;
        mem_wdata      = reg_entry.w_data;
        act_en         = 1'b0;
        pre_en         = 1'b0;
        resp_valid     = 1'b0;
        resp_data      = 8'h00;
        resp_bz        = 1'b0;
        resp_rw        = 1'b0;

        case (cur_state)
            IDLE: begin
                if (entry_valid) begin
                    entry_accepted = 1'b1;  // pop 
                    nxt_state      = CHECK;
                end
            end
            CHECK: begin
                resp_bz = 1'b1;
                if (is_hit) begin
                    nxt_state = RW;         
                end else if (is_conflict) begin
                    nxt_state = PRE;        // wrong row open, precharge first
                end else begin
                    nxt_state = ACT;        // bank closed, just activate
                end
            end
            PRE: begin
                resp_bz = 1'b1;
                pre_en  = 1'b1;             // tell bank_tracker to close this bank
                nxt_state = ACT;
            end
            ACT: begin
                resp_bz = 1'b1;
                act_en  = 1'b1;             // tell bank_tracker row is now open
                nxt_state = RW;
            end
            RW: begin
                resp_bz   = 1'b1;
                mem_valid = 1'b1;
                mem_cmd   = reg_entry.rw;   // 0=RD, 1=WR
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

        endcase
    end

    // bank table
    bank_tracker #(
        .N_BANKS (2),
        .ROW_W   (2)
    ) u_bank_tracker (
        .clk        (clk),
        .rst        (rst),
        .req_bank   (reg_entry.bank),
        .req_row    (reg_entry.row),
        .is_open    (is_open),
        .is_hit     (is_hit),
        .is_conflict(is_conflict),
        .act_en     (act_en),
        .pre_en     (pre_en)
    );

endmodule : mem_ctrl


// memory
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

    // request queue connection to mem_ctrl 
    fifo_entry_t entry_out;
    logic        entry_valid;
    logic        entry_accepted;
    logic        q_full;

    // mem_ctrl connection to fake_memory 
    logic        mem_valid;
    logic        mem_cmd;
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
        .N_BANKS (2),
        .N_ROWS  (4),
        .N_COLS  (4)
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
