/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

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

  // // All output pins must be assigned. If not used, assign to 0.
  // assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in


  // // List all unused inputs to prevent warnings
  // wire _unused = &{ena, clk, rst_n, 1'b0};

  wire reset  = ~rst_n;

  wire        go     = uio_in[0];
  wire        finish = uio_in[1];
  wire [7:0]  data_in = ui_in;

  wire [7:0]  range;
  wire        error;

  RangeFinder #(.WIDTH(8)) rf (
    .data_in(data_in),
    .clock  (clk),
    .reset  (reset),
    .go     (go),
    .finish (finish),
    .range  (range),
    .error  (error)
  );

  assign uo_out = range;
  assign uio_out = {7'b0, error};
  assign uio_oe  = 8'b0000_0001;

  // wire _unused = &{ena, 1'b0};
  wire _unused = &{ena, uio_in[7:2], 1'b0};


endmodule


module RangeFinder
  #(parameter WIDTH=16)
(
  input  logic [WIDTH-1:0] data_in,
  input  logic             clock, reset,
  input  logic             go, finish,
  output logic [WIDTH-1:0] range,
  output logic             error
);

  logic [WIDTH-1:0] max, min;

  enum logic [1:0] {IDLE, COLLECT, ERROR} cs, ns;

  logic go_prev;
  logic go_edge;

  assign go_edge = go & ~go_prev;

  always_comb begin
    ns = cs;
    error = 'd0;

    case (cs)
      IDLE: begin
         ns = (finish) ? ERROR :
              (go_edge) ? COLLECT
              : IDLE;
         error = (finish) ? 'd1 : 'd0;
      end
      COLLECT: begin
         ns = (go_edge) ? ERROR :
              (finish) ? IDLE:
              COLLECT;
         error = (go_edge) ? 'd1 : 'd0;
      end
      ERROR: begin
         ns = (go_edge) ? COLLECT : ERROR;
         error = 'd1;
      end
    endcase
  end


  always_ff @(posedge clock, posedge reset) begin
    if (reset) begin
      max   <= '0;
      min   <= '1;
      cs    <= IDLE;
      go_prev  <= 1'b0;
    end
    else begin
      go_prev <= go;
      if (go || (cs == COLLECT)) begin
        if (data_in > max) max <= data_in;
        if (data_in < min) min <= data_in;
      end
      cs <= ns;
    end
  end

  assign range = max - min;

endmodule



