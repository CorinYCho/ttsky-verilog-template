`default_nettype none
`timescale 1ns/1ps
`include "mem_ctrler.svh"

module tb_mem_top;

    
    logic clk = 0;
    always #5 clk = ~clk;          

    logic rst;


    logic [7:0] req_data;
    logic       req_phase;
    logic       req_rw;
    logic       req_valid;

    logic [7:0] resp_data;
    logic       resp_valid;
    logic       resp_bz;
    logic       resp_rw;


    mem_top dut (
        .clk        (clk),
        .rst        (rst),
        .req_data   (req_data),
        .req_phase  (req_phase),
        .req_rw     (req_rw),
        .req_valid  (req_valid),
        .resp_data  (resp_data),
        .resp_valid (resp_valid),
        .resp_bz    (resp_bz),
        .resp_rw    (resp_rw)
    );

 
    int pass_cnt = 0;
    int fail_cnt = 0;


    // does nothing
    task idle_cycle();
        req_valid = 0; req_rw = 0; req_phase = 0; req_data = '0;
        @(posedge clk); #1;
    endtask

    // issue cpu write

    task cpu_write(input logic [7:0] addr, input logic [7:0] wdata);
        // addr phase
        @(posedge clk); #1;
        req_valid = 1; req_rw = 1; req_phase = 0; req_data = addr;

        // data phase
        @(posedge clk); #1;
        req_valid = 1; req_rw = 1; req_phase = 1; req_data = wdata;

        // de-assert
        @(posedge clk); #1;
        req_valid = 0;

        // wait for write ack
        wait (resp_valid && resp_rw);
        @(posedge clk); #1;
    endtask

    // issue cpu read
    task cpu_read(input logic [7:0] addr, output logic [7:0] rdata);
        @(posedge clk); #1;
        req_valid = 1; req_rw = 0; req_phase = 0; req_data = addr;

        @(posedge clk); #1;
        req_valid = 0;

        // wait for read response
        wait (resp_valid && !resp_rw);
        rdata = resp_data;
        @(posedge clk); #1;
    endtask

    // Write then read back and compare
    task check_write_read(input logic [7:0] addr, input logic [7:0] wdata);
        logic [7:0] rdata;
        cpu_write(addr, wdata);
        cpu_read(addr, rdata);
        if (rdata === wdata) begin
            $display("\n PASSED");
            pass_cnt++;
        end else begin
            fail_cnt++;
        end
    endtask

    // function to make the address
    function logic [7:0] make_addr(
        input logic [0:0] bank,
        input logic [1:0] row,
        input logic [1:0] col
    );
        return {bank, row, col, 3'b000};
    endfunction

    // test bench
    initial begin
        req_valid = 0; req_rw = 0; req_phase = 0; req_data = '0;
        rst = 1;
        @(posedge clk);
        rst = 0;
        @(posedge clk);

        // TEST 0
        $display("\n TEST 0 initialization");
        begin
            logic [7:0] rdata;
            cpu_read(make_addr(0, 2'd2, 2'd3), rdata);
            if (rdata === 8'h00) begin
                $display("\n PASSED");
                pass_cnt++;
            end else begin
                fail_cnt++;
            end
        end
   

        // simple write + read in bank 0
        $display("\n TEST 1 WRITE AND READ IN BANK 0");
        check_write_read(make_addr(0, 2'd0, 2'd0), 8'hAB);

        idle_cycle();

        // simple write + read in bank 1
        $display("\n TEST 2 WRITE AND READ IN BANK 1");
        check_write_read(make_addr(1, 2'd1, 2'd2), 8'h5A);

        idle_cycle();

        // row conflict - write to row 0 then row 1 for bank 0
        $display("\n TEST 3 TESTING ROW CONFLICT");
        check_write_read(make_addr(0, 2'd0, 2'd1), 8'hDE);
        check_write_read(make_addr(0, 2'd1, 2'd1), 8'hAD);

        // check if the first address still stores the data
        begin
            logic [7:0] rdata;
            $display("\n TEST 4 READ THAT BANK 0 STILL HAS OLD DATA");
            cpu_read(make_addr(0, 2'd0, 2'd1), rdata);
            if (rdata === 8'hDE) begin
                $display("\n PASSED");
                pass_cnt++;
            end else begin
                fail_cnt++;
            end
        end

        idle_cycle();

        // overwrite to the same address
        $display("\nTEST 5 OVERWRITING PREVIOUS ADDRESS");
        cpu_write(make_addr(1, 2'd3, 2'd3), 8'hFF);
        cpu_write(make_addr(1, 2'd3, 2'd3), 8'h11);   // need to overwrite here

        begin
            logic [7:0] rdata;
            cpu_read(make_addr(1, 2'd3, 2'd3), rdata);
            if (rdata === 8'h11) begin
                $display("\n PASSED");
                pass_cnt++;
            end else begin
                fail_cnt++;
            end
        end

        idle_cycle();

        $display("\n TEST 6 ALL ZEROS DATA");
        check_write_read(make_addr(0, 2'd0, 2'd0), 8'h00);
        idle_cycle();

    
        $display("\n TEST 7 ALL ONES DATA");
        check_write_read(make_addr(1, 2'd1, 2'd1), 8'hFF);
        idle_cycle();

        $display("\n TEST 8 SAME ROW COL FOR DIFFERENT BANKS");
        begin
            logic [7:0] rdata0, rdata1;
            cpu_write(make_addr(0, 2'd0, 2'd0), 8'hAA);
            cpu_write(make_addr(1, 2'd0, 2'd0), 8'h55);
            cpu_read(make_addr(0, 2'd0, 2'd0), rdata0);
            cpu_read(make_addr(1, 2'd0, 2'd0), rdata1);
            if (rdata0 === 8'hAA && rdata1 === 8'h55) begin
                $display("\n PASSED");
                pass_cnt++;
            end else begin
                $display("\n FAILED bank0=0x%0h bank1=0x%0h", rdata0, rdata1);
                fail_cnt++;
            end
        end

        idle_cycle();

        // read and write on the same cycle
        $display("\n TEST 9 WRITE READ WRITE READ SAME CELL");
        begin
            logic [7:0] rdata;
            cpu_write(make_addr(0, 2'd1, 2'd0), 8'hC3);
            cpu_read (make_addr(0, 2'd1, 2'd0), rdata);
            if (rdata !== 8'hC3) begin
                $display("\n FAILED first write: got 0x%0h", rdata);
                fail_cnt++;
            end
            cpu_write(make_addr(0, 2'd1, 2'd0), 8'h3C);
            cpu_read (make_addr(0, 2'd1, 2'd0), rdata);
            if (rdata === 8'h3C) begin
                $display("\n PASSED");
                pass_cnt++;
            end else begin
                $display("\n FAILED second write: got 0x%0h", rdata);
                fail_cnt++;
            end
        end

        idle_cycle();

 

        $display("\n TEST 11 EXHAUSTIVE FILL ALL 8 CELLS");
        begin
            logic [7:0] expected [0:1][0:1][0:1];
            logic [7:0] rdata;
            logic       all_pass;
            all_pass = 1;
            // fill
            for (int b = 0; b < 2; b++) begin
                for (int r = 0; r < 2; r++) begin
                    for (int c = 0; c < 2; c++) begin
                        expected[b][r][c] = 8'(b * 4 + r * 2 + c + 1); 
                        cpu_write(make_addr(b[0], r[1:0], c[1:0]), expected[b][r][c]);
                    end
                end
            end
            // verify
            for (int b = 0; b < 2; b++) begin
                for (int r = 0; r < 2; r++) begin
                    for (int c = 0; c < 2; c++) begin
                        cpu_read(make_addr(b[0], r[1:0], c[1:0]), rdata);
                        if (rdata !== expected[b][r][c]) begin
                            $display("\n FAILED bank%0d row%0d col%0d: got 0x%0h exp 0x%0h",
                                     b, r, c, rdata, expected[b][r][c]);
                            all_pass = 0;
                            fail_cnt++;
                        end
                    end
                end
            end
            if (all_pass) begin
                $display("\n PASSED");
                pass_cnt++;
            end
        end

        idle_cycle();

        
        $display("\n TEST 12 BACK TO BACK READS NO WRITE");
        begin
            logic [7:0] r1, r2;
            // reset to clear memory state
            rst = 1; @(posedge clk); #1;
            rst = 0; @(posedge clk); #1;
            cpu_read(make_addr(0, 2'd0, 2'd0), r1);
            cpu_read(make_addr(0, 2'd0, 2'd0), r2);
            if (r1 === 8'h00 && r2 === 8'h00) begin
                $display("\n PASSED");
                pass_cnt++;
            end else begin
                $display("\n FAILED r1=0x%0h r2=0x%0h", r1, r2);
                fail_cnt++;
            end
        end

        idle_cycle();


        // scoreboard
        // $display("  Results: %0d PASSED  /  %0d FAILED", pass_cnt, fail_cnt);

        @(posedge clk);
        $finish;
    end

    // timeout if all goes wrong...
    initial begin
        repeat(2000) @(posedge clk);
        $display("should've ended by now");
        $finish;
    end

    // for waveform
    initial begin
        $dumpfile("tb_mem_top.vcd");
        $dumpvars(0, tb_mem_top);
    end

endmodule : tb_mem_top
