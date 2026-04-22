`default_nettype none
`timescale 1ns/1ps



module rq_fsm (
    input  logic        clk,
    input  logic        rst,

    // interacting with fake cpu interface (testbench)
    input  logic        req_valid,      // cpu is telling us, they have a req
    input  logic        req_rw,         // 0=RD, 1=WR
    input  logic        req_phase,      // applies only for WR: 0 = addr phase, 1 = data phase
    input  logic [7:0]  in_data,        // address OR data to be written to mem

    // decoded addr
    input  logic [1:0]  bank,
    input  logic [1:0]  row,
    input  logic [1:0]  col,

    // interacting with the fifo
    input  logic        queue_not_full,
    output logic        entry_ready,    
    output fifo_entry_t entry
);

    fifo_entry_t entry_reg;

    assign entry = entry_reg;

    always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
            entry_reg <= '0;
            entry_ready <= 'd0;
        end else if (req_valid && queue_not_full) begin
            if (!req_rw) begin // read
                entry_ready      <= 1'b1;
                entry_reg.valid  <= 1'b1;
                entry_reg.rw     <= 1'b0;
                entry_reg.addr   <= in_data;
                entry_reg.w_data <= 8'h00;
                entry_reg.bank   <= bank;
                entry_reg.row    <= row;
                entry_reg.col    <= col;
            end else begin // write
                if (!req_phase) begin // take address
                    entry_ready      <= 1'b0;
                    entry_reg.addr   <= in_data;
                    entry_reg.bank   <= bank;
                    entry_reg.row    <= row;
                    entry_reg.col    <= col;
                    entry_reg.valid  <= 1'b0;   // not ready yet
                    entry_reg.rw     <= 1'b1;
                end
                else begin // take data
                    entry_ready      <= 1'b1;
                    entry_reg.w_data <= in_data;
                    entry_reg.valid  <= 1'b1;
                end
            end
        end else begin
            // No valid request 
            entry_ready      <= 1'b0;
        end
    end
endmodule : rq_fsm


// combinational address decoder that decodes the address into bank, row, and 
// col
// for now, implemented with 2 banks, 4 rows, and 4 cols 

module decode_addr (
    input  logic [7:0] addr,
    output logic [1:0] bank,
    output logic [1:0] row,
    output logic [1:0] col
);
    always_comb begin
        bank = addr[7];
        row  = addr[6:5];
        col  = addr[4:3];
    end

endmodule : decode_addr

module request_queue #(
    parameter int DEPTH = 4,
    parameter int PTR_W = $clog2(DEPTH)
)(
    input  logic        clk,
    input  logic        rst,

    // cpu side
    input  logic        req_valid,
    input  logic        req_rw,
    input  logic        req_phase,
    input  logic [7:0]  req_data,

    // cmd operator side
    input  logic        entry_accepted,
    input  logic        sched_idx,
    // output fifo_entry_t entry_out,
    output logic        entry_valid,
    output logic        q_full,

    output fifo_entry_t [DEPTH-1:0] fifo_array,
    output logic        [DEPTH-1:0][DEPTH-1:0] age_array  
);


    logic [1:0] dec_bank, dec_row, dec_col;


    logic        entry_ready;
    fifo_entry_t assembled_entry;


    fifo_entry_t [DEPTH-1:0] fifo_mem;
    logic [DEPTH-1:0][DEPTH-1:0] age_mem;
    logic [PTR_W-1:0] wr_ptr;
    logic [PTR_W-1:0] nxt_wr_ptr;
    logic [PTR_W-1:0] cand;
    logic [PTR_W:0]   count;
    logic [PTR_W:0] push_seq;


    assign fifo_array  = fifo_mem;
    assign age_array   = age_mem;
    assign q_full      = (count == DEPTH);
    assign entry_valid = (count != '0); 
    // assign entry_out   = fifo_mem[rd_ptr];


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

    logic do_push, do_pop, found;
    assign do_push = entry_ready && !q_full;
    assign do_pop  = entry_accepted && entry_valid;

    always_comb begin
        found      = 1'b0;
        nxt_wr_ptr = wr_ptr;
        for (int k = 1; k <= DEPTH; k++) begin
            cand = wr_ptr + k;
            if (!found) begin
                if (!fifo_mem[cand].valid) begin
                    nxt_wr_ptr = cand;
                    found      = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= '0;
            push_seq <= '0;
            count  <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                fifo_mem[i] <= '0;
                age_mem[i]  <= '0;
            end
        end else begin
            // PUSH 
            count <= count + do_push - do_pop;
            if (do_push) begin
                fifo_mem[wr_ptr] <= assembled_entry;
                age_mem[wr_ptr]  <= push_seq;
                wr_ptr           <= nxt_wr_ptr;   
                push_seq         <= push_seq + 1'b1;
            end
            // POP 
            if (do_pop) begin
                fifo_mem[sched_idx].valid <= 1'b0;
                age_mem[sched_idx]        <= '0;
            end
        end
    end

endmodule : request_queue