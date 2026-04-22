// // module scheduler #(
// //     parameter int DEPTH  = 8,
// //     parameter int PTR_W  = $clog2(DEPTH),
// //     parameter int N_BANKS = 2,
// //     parameter int ROW_W  = 2
// // )(
// //     // bank open state from bank_tracker
// //     input  logic [N_BANKS-1:0]             bank_open_flag,
// //     input  logic [N_BANKS-1:0][ROW_W-1:0]  bank_open_row,

// //     // full FIFO snapshot
// //     input  fifo_entry_t [DEPTH-1:0]             fifo,
// //     input  logic        [DEPTH-1:0][DEPTH-1:0]  age_array, // age_array[i] = push seq

// //     // result
// //     output logic                                sched_valid,
// //     output fifo_entry_t                         sched_entry,
// //     output logic [PTR_W-1:0]                    sched_idx // to update fifo
// // );


// //     logic [DEPTH-1:0] is_row_hit;

// //     always_comb begin
// //         for (int i = 0; i < DEPTH; i++) begin
// //             is_row_hit[i] = fifo[i].valid &&
// //             bank_open_flag[fifo[i].bank] &&
// //             (bank_open_row[fifo[i].bank] == fifo[i].row);
// //         end
// //     end


// //     logic [DEPTH-1:0] raw_hazard;
// //     // RAW hazard: for each READ entry i, check if any WRITE entry j with
// //     // age_array[j] < age_array[i] targets the same address.
// //     always_comb begin
// //         for (int i = 0; i < DEPTH; i++) begin
// //             raw_hazard[i] = 1'b0;
// //             if (fifo[i].valid && !fifo[i].rw) begin
// //                 // it's a READ – scan for older writes to same address
// //                 for (int j = 0; j < DEPTH; j++) begin
// //                     if (i != j &&
// //                         fifo[j].valid &&
// //                         fifo[j].rw &&                        // is a WRITE
// //                         (fifo[j].bank == fifo[i].bank) &&
// //                         (fifo[j].row  == fifo[i].row)  &&
// //                         (fifo[j].col  == fifo[i].col)  &&
// //                         (age_array[j] < age_array[i]))       // older write
// //                     begin
// //                         raw_hazard[i] = 1'b1;
// //                     end
// //                 end
// //             end
// //         end
// //     end

   
// //     //  Priority selection – four passes, pick best in each tier

// //     //  Every tier is gated by (valid && !raw_hazard[i]).

// //     //  raw_hazard[i] is only ever asserted for READ entries (writes cannot
// //     //  be RAW-hazardous), so:

// //     //    - Tier 1 row-hit reads  : blocked if RAW hazard present
// //     //    - Tier 2 row-hit writes : raw_hazard always 0 for writes, unblocked
// //     //    - Tier 3 oldest reads   : blocked if RAW hazard present
// //     //    - Tier 4 oldest writes  : raw_hazard always 0 for writes, unblocked


// //     // Intermediate winners per tier
// //     logic        t1_found, t2_found, t3_found, t4_found;
// //     logic [PTR_W-1:0] t1_idx, t2_idx, t3_idx, t4_idx;
// //     logic [DEPTH-1:0] t1_age, t2_age, t3_age, t4_age;

// //     always_comb begin
// //         t1_found = 1'b0; t1_idx = '0; t1_age = '1;
// //         t2_found = 1'b0; t2_idx = '0; t2_age = '1;
// //         t3_found = 1'b0; t3_idx = '0; t3_age = '1;
// //         t4_found = 1'b0; t4_idx = '0; t4_age = '1;

// //         for (int i = 0; i < DEPTH; i++) begin
// //             if (fifo[i].valid) begin
// //                 // Tier 1: row-hit read
// //                 if (is_row_hit[i] && !fifo[i].rw && !raw_hazard[i]) begin
// //                     if (!t1_found || age_array[i] < t1_age) begin
// //                         t1_found = 1'b1;
// //                         t1_idx   = PTR_W'(i);
// //                         t1_age   = age_array[i];
// //                     end
// //                 end
// //                 // Tier 2: row-hit write
// //                 if (is_row_hit[i] && fifo[i].rw) begin
// //                     if (!t2_found || age_array[i] < t2_age) begin
// //                         t2_found = 1'b1;
// //                         t2_idx   = PTR_W'(i);
// //                         t2_age   = age_array[i];
// //                     end
// //                 end
// //                 // Tier 3: any read (oldest)
// //                 if (!fifo[i].rw && !raw_hazard[i]) begin
// //                     if (!t3_found || age_array[i] < t3_age) begin
// //                         t3_found = 1'b1;
// //                         t3_idx   = PTR_W'(i);
// //                         t3_age   = age_array[i];
// //                     end
// //                 end
// //                 // Tier 4: any write (oldest)
// //                 if (fifo[i].rw) begin
// //                     if (!t4_found || age_array[i] < t4_age) begin
// //                         t4_found = 1'b1;
// //                         t4_idx   = PTR_W'(i);
// //                         t4_age   = age_array[i];
// //                     end
// //                 end
// //             end
// //         end

// //         // Pick highest available tier
// //         if (t1_found) begin
// //             sched_valid = 1'b1;
// //             sched_idx   = t1_idx;
// //         end else if (t2_found) begin
// //             sched_valid = 1'b1;
// //             sched_idx   = t2_idx;
// //         end else if (t3_found) begin
// //             sched_valid = 1'b1;
// //             sched_idx   = t3_idx;
// //         end else if (t4_found) begin
// //             sched_valid = 1'b1;
// //             sched_idx   = t4_idx;
// //         end else begin
// //             sched_valid = 1'b0;
// //             sched_idx   = '0;
// //         end
        
// //         sched_entry = fifo[sched_idx];
// //     end

// // endmodule : scheduler


// module scheduler #(
//     parameter int DEPTH  = 8,
//     parameter int PTR_W  = $clog2(DEPTH),
//     parameter int N_BANKS = 2,
//     parameter int ROW_W  = 2
// )(
//     // bank open state from bank_tracker
//     input  logic [N_BANKS-1:0]             bank_open_flag,
//     input  logic [N_BANKS-1:0][ROW_W-1:0]  bank_open_row,

//     // full FIFO snapshot
//     input  fifo_entry_t [DEPTH-1:0]             fifo,
//     input  logic        [DEPTH-1:0][DEPTH-1:0]  age_array,

//     // result
//     output logic                                sched_valid,
//     output fifo_entry_t                         sched_entry,
//     output logic [PTR_W-1:0]                    sched_idx
// );

//     // -----------------------------
//     // Row hit detection
//     // -----------------------------
//     logic [DEPTH-1:0] is_row_hit;

//     always_comb begin
//         for (int i = 0; i < DEPTH; i++) begin
//             is_row_hit[i] = fifo[i].valid &&
//                             bank_open_flag[fifo[i].bank] &&
//                             (bank_open_row[fifo[i].bank] == fifo[i].row);
//         end
//     end

//     // -----------------------------
//     // RAW hazard detection
//     // -----------------------------
//     logic [DEPTH-1:0] raw_hazard;

//     always_comb begin
//         for (int i = 0; i < DEPTH; i++) begin
//             raw_hazard[i] = 1'b0;

//             if (fifo[i].valid && !fifo[i].rw) begin // READ
//                 for (int j = 0; j < DEPTH; j++) begin
//                     if (i != j &&
//                         fifo[j].valid &&
//                         fifo[j].rw && // WRITE
//                         (fifo[j].bank == fifo[i].bank) &&
//                         (fifo[j].row  == fifo[i].row)  &&
//                         (fifo[j].col  == fifo[i].col)  &&
//                         (age_array[j] < age_array[i])) begin
//                         raw_hazard[i] = 1'b1;
//                     end
//                 end
//             end
//         end
//     end

//     // -----------------------------
//     // Priority selection (5 tiers)
//     // -----------------------------
//     logic        t1_found, t2_found, t3_found, t4_found, t5_found;
//     logic [PTR_W-1:0] t1_idx, t2_idx, t3_idx, t4_idx, t5_idx;
//     logic [DEPTH-1:0] t1_age, t2_age, t3_age, t4_age, t5_age;

//     always_comb begin
//         // Initialize
//         t1_found = 0; t1_idx = '0; t1_age = '1;
//         t2_found = 0; t2_idx = '0; t2_age = '1;
//         t3_found = 0; t3_idx = '0; t3_age = '1;
//         t4_found = 0; t4_idx = '0; t4_age = '1;
//         t5_found = 0; t5_idx = '0; t5_age = '1;

//         // Scan all entries
//         for (int i = 0; i < DEPTH; i++) begin
//             if (fifo[i].valid) begin

//                 // Tier 1: row-hit READ (no RAW hazard)
//                 if (is_row_hit[i] && !fifo[i].rw && !raw_hazard[i]) begin
//                     if (!t1_found || age_array[i] < t1_age) begin
//                         t1_found = 1;
//                         t1_idx   = PTR_W'(i);
//                         t1_age   = age_array[i];
//                     end
//                 end

//                 // Tier 2: row-hit WRITE
//                 if (is_row_hit[i] && fifo[i].rw) begin
//                     if (!t2_found || age_array[i] < t2_age) begin
//                         t2_found = 1;
//                         t2_idx   = PTR_W'(i);
//                         t2_age   = age_array[i];
//                     end
//                 end

//                 // Tier 3: any READ (no RAW hazard)
//                 if (!fifo[i].rw && !raw_hazard[i]) begin
//                     if (!t3_found || age_array[i] < t3_age) begin
//                         t3_found = 1;
//                         t3_idx   = PTR_W'(i);
//                         t3_age   = age_array[i];
//                     end
//                 end

//                 // Tier 4: any WRITE
//                 if (fifo[i].rw) begin
//                     if (!t4_found || age_array[i] < t4_age) begin
//                         t4_found = 1;
//                         t4_idx   = PTR_W'(i);
//                         t4_age   = age_array[i];
//                     end
//                 end

//                 // Tier 5: fallback → oldest VALID entry
//                 if (!t5_found || age_array[i] < t5_age) begin
//                     t5_found = 1;
//                     t5_idx   = PTR_W'(i);
//                     t5_age   = age_array[i];
//                 end
//             end
//         end

//         // Final selection
//         if (t1_found) begin
//             sched_valid = 1;
//             sched_idx   = t1_idx;
//         end else if (t2_found) begin
//             sched_valid = 1;
//             sched_idx   = t2_idx;
//         end else if (t3_found) begin
//             sched_valid = 1;
//             sched_idx   = t3_idx;
//         end else if (t4_found) begin
//             sched_valid = 1;
//             sched_idx   = t4_idx;
//         end else if (t5_found) begin
//             sched_valid = 1;
//             sched_idx   = t5_idx;
//         end else begin
//             sched_valid = 0;
//             sched_idx   = '0;
//         end

//         // Safe assignment
//         sched_entry = sched_valid ? fifo[sched_idx] : '0;
//     end

// endmodule : scheduler

module scheduler #(
    parameter int DEPTH  = 8,
    parameter int PTR_W  = $clog2(DEPTH),
    parameter int N_BANKS = 2,
    parameter int ROW_W  = 2
)(
    // bank open state from bank_tracker
    input  logic [N_BANKS-1:0]             bank_open_flag,
    input  logic [N_BANKS-1:0][ROW_W-1:0]  bank_open_row,

    // full FIFO snapshot
    input  fifo_entry_t [DEPTH-1:0]             fifo,
    input  logic        [DEPTH-1:0][DEPTH-1:0]  age_array,

    // result
    output logic                                sched_valid,
    output fifo_entry_t                         sched_entry,
    output logic [PTR_W-1:0]                    sched_idx
);

    always_comb begin
        sched_valid = 1'b0;
        sched_idx   = '0;
        sched_entry = '0;

        // Find first valid entry
        for (int i = 0; i < DEPTH; i++) begin
            if (!sched_valid && fifo[i].valid) begin
                sched_valid = 1'b1;
                sched_idx   = PTR_W'(i);
                sched_entry = fifo[i];
            end
        end
    end

endmodule : scheduler