`default_nettype none

module tt_um_corin (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
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
    .clk(clk),
    .rst(reset),
    .req_data(req_data),
    .req_phase(req_phase),
    .req_rw(req_rw),
    .req_valid(req_valid),
    .resp_data(resp_data),
    .resp_valid(resp_valid),
    .resp_bz(resp_bz),
    .resp_rw(resp_rw)
  );

  assign uo_out  = resp_data;
  assign uio_out = {5'b0, resp_valid, resp_bz, resp_rw};
  assign uio_oe  = 8'b0000_0111;

  wire _unused = &{ena, uio_in[7:6], 1'b0};

endmodule


typedef struct packed {
    logic        valid;
    logic        rw;
    logic [7:0]  addr;
    logic [7:0]  w_data;
    logic [1:0]  bank;
    logic [1:0]  row;
    logic [1:0]  col;
} fifo_entry_t;


// ---------------- decode_addr FIXED ----------------
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
endmodule


// ---------------- bank_tracker ----------------
module bank_tracker #(
    parameter int N_BANKS = 2,
    parameter int ROW_W   = 2
)(
    input  logic                        clk,
    input  logic                        rst,
    input  logic [$clog2(N_BANKS)-1:0]  req_bank,
    input  logic [ROW_W-1:0]            req_row,
    output logic                        is_open,
    output logic                        is_hit,
    output logic                        is_conflict,
    input  logic                        act_en,
    input  logic                        pre_en
);

    logic [N_BANKS-1:0] open_flag;
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
endmodule


// ---------------- fake_memory FIXED ----------------
module fake_memory #(
    parameter int N_BANKS = 2,
    parameter int N_ROWS  = 4,
    parameter int N_COLS  = 4
)(
    input  logic clk,
    input  logic rst,
    input  logic mem_valid,
    input  logic mem_cmd,
    input  logic [$clog2(N_BANKS)-1:0] mem_bank,
    input  logic [$clog2(N_ROWS)-1:0]  mem_row,
    input  logic [$clog2(N_COLS)-1:0]  mem_col,
    input  logic [7:0] mem_wdata,
    output logic mem_resp_valid,
    output logic [7:0] mem_resp_rdata,
    output logic mem_resp_rw
);

    logic [N_BANKS-1:0][N_ROWS-1:0][N_COLS-1:0][7:0] mem_arr;

    logic reg_valid, reg_cmd;
    logic [$clog2(N_BANKS)-1:0] reg_bank;
    logic [$clog2(N_ROWS)-1:0]  reg_row;
    logic [$clog2(N_COLS)-1:0]  reg_col;
    logic [7:0] reg_wdata;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_valid      <= 0;
            mem_resp_valid <= 0;
            mem_arr        <= '0;
        end else begin
            reg_valid <= mem_valid;
            reg_cmd   <= mem_cmd;
            reg_bank  <= mem_bank;
            reg_row   <= mem_row;
            reg_col   <= mem_col;
            reg_wdata <= mem_wdata;

            mem_resp_valid <= 0;
            if (reg_valid) begin
                mem_resp_valid <= 1;
                mem_resp_rw    <= reg_cmd;
                if (!reg_cmd)
                    mem_resp_rdata <= mem_arr[reg_bank][reg_row][reg_col];
                else
                    mem_arr[reg_bank][reg_row][reg_col] <= reg_wdata;
            end
        end
    end
endmodule


// ---------------- mem_ctrl (added default case) ----------------
module mem_ctrl (
    input  logic clk, rst,
    input  logic entry_valid,
    input  fifo_entry_t entry_in,
    output logic entry_accepted,

    output logic mem_valid,
    output logic mem_cmd,
    output logic [1:0] mem_bank, mem_row, mem_col,
    output logic [7:0] mem_wdata,
    input  logic mem_resp_valid,
    input  logic [7:0] mem_resp_rdata,
    input  logic mem_resp_rw,

    output logic resp_valid,
    output logic [7:0] resp_data,
    output logic resp_bz,
    output logic resp_rw
);

    typedef enum logic [2:0] {IDLE, CHECK, PRE, ACT, RW, RESP} state_t;
    state_t cur_state, nxt_state;

    fifo_entry_t reg_entry;

    logic is_open, is_hit, is_conflict;
    logic act_en, pre_en;

    always_ff @(posedge clk or posedge rst)
        if (rst) cur_state <= IDLE;
        else cur_state <= nxt_state;

    always_ff @(posedge clk or posedge rst)
        if (rst) reg_entry <= '0;
        else if (entry_accepted) reg_entry <= entry_in;

    always_comb begin
        nxt_state = cur_state;
        entry_accepted = 0;
        mem_valid = 0;
        mem_cmd = 0;
        mem_bank = reg_entry.bank;
        mem_row  = reg_entry.row;
        mem_col  = reg_entry.col;
        mem_wdata = reg_entry.w_data;
        act_en = 0;
        pre_en = 0;
        resp_valid = 0;
        resp_bz = 0;

        case (cur_state)
            IDLE: if (entry_valid) begin entry_accepted = 1; nxt_state = CHECK; end
            CHECK: nxt_state = is_hit ? RW : (is_conflict ? PRE : ACT);
            PRE:   begin pre_en = 1; nxt_state = ACT; end
            ACT:   begin act_en = 1; nxt_state = RW; end
            RW:    begin mem_valid = 1; mem_cmd = reg_entry.rw; nxt_state = RESP; end
            RESP:  if (mem_resp_valid) begin
                        resp_valid = 1;
                        resp_data  = mem_resp_rdata;
                        resp_rw    = mem_resp_rw;
                        nxt_state  = IDLE;
                   end
            default: nxt_state = IDLE;
        endcase
    end

    bank_tracker u_bt (
        .clk(clk), .rst(rst),
        .req_bank(reg_entry.bank),
        .req_row(reg_entry.row),
        .is_open(is_open),
        .is_hit(is_hit),
        .is_conflict(is_conflict),
        .act_en(act_en),
        .pre_en(pre_en)
    );
endmodule


// ---------------- request_queue FIXED count ----------------
module request_queue #(
    parameter int DEPTH = 4,
    parameter int PTR_W = $clog2(DEPTH)
)(
    input  logic clk, rst,
    input  logic req_valid, req_rw, req_phase,
    input  logic [7:0] req_data,
    input  logic entry_accepted,
    output fifo_entry_t entry_out,
    output logic entry_valid,
    output logic q_full
);

    logic [1:0] dec_bank, dec_row, dec_col;
    logic entry_ready;
    fifo_entry_t assembled_entry;

    fifo_entry_t [DEPTH-1:0] fifo_mem;
    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic [$clog2(DEPTH+1)-1:0] count;

    assign q_full = (count == DEPTH);
    assign entry_valid = (count != 0);
    assign entry_out = fifo_mem[rd_ptr];

    decode_addr u_decode (.addr(req_data), .bank(dec_bank), .row(dec_row), .col(dec_col));

    rq_fsm u_fsm (
        .clk(clk), .rst(rst),
        .req_valid(req_valid),
        .req_rw(req_rw),
        .req_phase(req_phase),
        .in_data(req_data),
        .bank(dec_bank),
        .row(dec_row),
        .col(dec_col),
        .queue_not_full(~q_full),
        .entry_ready(entry_ready),
        .entry(assembled_entry)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0; rd_ptr <= 0; count <= 0;
        end else begin
            if (entry_ready && !q_full) begin
                fifo_mem[wr_ptr] <= assembled_entry;
                wr_ptr <= wr_ptr + 1;
                count  <= count + 1;
            end
            if (entry_accepted && entry_valid) begin
                rd_ptr <= rd_ptr + 1;
                count  <= count - 1;
            end
        end
    end
endmodule
