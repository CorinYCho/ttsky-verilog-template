`default_nettype none
`timescale 1ns/1ps


// when entry_ready asserted, immediately serviced to request fifo unless 
// request_fifo outputs a queue full, then the cpu will not be sending requests

// basically, queue_full signal is a backfire signal

// module description - fsm receiving signals from tb cpu and interacting with
// fifo to store requests

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


    input  logic        req_valid,
    input  logic        req_rw,
    input  logic        req_phase,
    input  logic [7:0]  req_data,

  
    input  logic        entry_accepted,
    output fifo_entry_t entry_out,
    output logic        entry_valid,
    output logic        q_full
);


    logic [1:0] dec_bank, dec_row, dec_col;


    logic        entry_ready;
    fifo_entry_t assembled_entry;


    fifo_entry_t [DEPTH-1:0] fifo_mem;
    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic [PTR_W:0]   count;

    assign q_full      = (count == DEPTH);
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
            // PUSH 
            if (entry_ready && !q_full) begin
                fifo_mem[wr_ptr] <= assembled_entry;
                wr_ptr           <= wr_ptr + 1'b1;
                count            <= count + 1'b1;
            end
            // POP 
            if (entry_accepted && entry_valid) begin
                rd_ptr <= rd_ptr + 1'b1;
                count  <= count - 1'b1;
            end
        end
    end

endmodule : request_queue