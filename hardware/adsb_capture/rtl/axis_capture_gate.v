`timescale 1ns / 1ps

// Finite DMA frames derived from the continuous ADC stream.
//
// The ADC cannot be paused, so input samples are always accepted. Samples are
// dropped while idle. An output stall sets overflow and ends the short frame.
// A standard AXI stream FIFO follows this block in the block design.
//
// AXI GPIO control:
//   frame_samples_ctrl : GPIO channel 1, 32-bit output
//   arm_toggle_ctrl    : GPIO channel 2, 1-bit output; toggle for every frame
//   status_ctrl[0]     : done
//   status_ctrl[1]     : overflow (discard the frame)
//   status_ctrl[2]     : busy
module axis_capture_gate #(
    parameter integer DATA_WIDTH = 32
) (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME axis_clk, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET axis_resetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 axis_clk CLK" *)
    input  wire                     axis_clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME axis_resetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 axis_resetn RST" *)
    input  wire                     axis_resetn,

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ctrl_clk, ASSOCIATED_RESET ctrl_resetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ctrl_clk CLK" *)
    input  wire                     ctrl_clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ctrl_resetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ctrl_resetn RST" *)
    input  wire                     ctrl_resetn,

    input  wire [31:0]              frame_samples_ctrl,
    input  wire                     arm_toggle_ctrl,
    // [31:16] identifies the verified RFDC8/PL32 design.
    // [15:3] reports the most recently measured number of axis_clk cycles
    //        between input TVALID pulses.
    // [2:0]  remains {busy, overflow, done}.
    output wire [31:0]              status_ctrl,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [DATA_WIDTH-1:0]     s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire                     s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire                     s_axis_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [DATA_WIDTH-1:0]     m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire                     m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire                     m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire                     m_axis_tlast
);

    // The sample count is written before arm_toggle changes. Both GPIO values
    // cross into the stream clock domain through these registers.
    reg [31:0] frame_samples_meta = 32'd1;
    reg [31:0] frame_samples_sync = 32'd1;
    reg        arm_meta = 1'b0;
    reg        arm_sync = 1'b0;
    reg        arm_seen = 1'b0;

    reg [31:0] frame_samples = 32'd1;
    reg [31:0] sample_count = 32'd0;
    reg        active = 1'b0;
    reg        done_axis = 1'b0;
    reg        overflow_axis = 1'b0;

    // The selector-5 path must produce one complex sample every 16 cycles of
    // the 160 MHz RFDC fabric clock.  Exposing the measured interval makes a
    // stale/deepest-decimator bitstream immediately distinguishable: that
    // path reports 128 and produces the observed 1.25 MSPS stream.
    reg [12:0] valid_gap_counter_axis = 13'd0;
    reg [12:0] valid_interval_axis = 13'd0;

    // One output word is retained during a FIFO stall.
    reg [DATA_WIDTH-1:0] out_data = {DATA_WIDTH{1'b0}};
    reg                  out_valid = 1'b0;
    reg                  out_last = 1'b0;

    wire arm_event = arm_sync ^ arm_seen;
    wire out_fire = out_valid && m_axis_tready;

    // The live input remains ready; idle samples are discarded.
    assign s_axis_tready = 1'b1;
    assign m_axis_tdata = out_data;
    assign m_axis_tvalid = out_valid;
    assign m_axis_tlast = out_last;

    always @(posedge axis_clk) begin
        if (!axis_resetn) begin
            frame_samples_meta <= 32'd1;
            frame_samples_sync <= 32'd1;
            arm_meta <= 1'b0;
            arm_sync <= 1'b0;
            valid_gap_counter_axis <= 13'd0;
            valid_interval_axis <= 13'd0;
        end else begin
            frame_samples_meta <= frame_samples_ctrl;
            frame_samples_sync <= frame_samples_meta;
            arm_meta <= arm_toggle_ctrl;
            arm_sync <= arm_meta;

            if (s_axis_tvalid) begin
                valid_interval_axis <= valid_gap_counter_axis + 1'b1;
                valid_gap_counter_axis <= 13'd0;
            end else if (valid_gap_counter_axis != 13'h1fff) begin
                valid_gap_counter_axis <= valid_gap_counter_axis + 1'b1;
            end
        end
    end

    always @(posedge axis_clk) begin
        if (!axis_resetn) begin
            arm_seen <= 1'b0;
            frame_samples <= 32'd1;
            sample_count <= 32'd0;
            active <= 1'b0;
            done_axis <= 1'b0;
            overflow_axis <= 1'b0;
            out_data <= {DATA_WIDTH{1'b0}};
            out_valid <= 1'b0;
            out_last <= 1'b0;
        end else if (arm_event) begin
            arm_seen <= arm_sync;
            frame_samples <= (frame_samples_sync == 0) ? 32'd1 : frame_samples_sync;
            sample_count <= 32'd0;
            active <= 1'b1;
            done_axis <= 1'b0;
            overflow_axis <= 1'b0;
            out_valid <= 1'b0;
            out_last <= 1'b0;
        end else begin
            if (out_fire) begin
                out_valid <= 1'b0;
                if (out_last) begin
                    out_last <= 1'b0;
                    active <= 1'b0;
                    done_axis <= 1'b1;
                end
            end

            if (active && s_axis_tvalid) begin
                if (!out_valid || out_fire) begin
                    // No new sample starts on the final frame cycle.
                    if (!(out_fire && out_last)) begin
                        out_data <= s_axis_tdata;
                        out_valid <= 1'b1;
                        out_last <= (sample_count == frame_samples - 1'b1);
                        sample_count <= sample_count + 1'b1;
                    end
                end else begin
                    // A FIFO stall during live acquisition terminates the
                    // frame and sets the rejection status.
                    overflow_axis <= 1'b1;
                    active <= 1'b0;
                    out_last <= 1'b1;
                end
            end
        end
    end

    // Status returns to the 100 MHz GPIO clock domain.
    reg done_meta = 1'b0;
    reg done_sync = 1'b0;
    reg overflow_meta = 1'b0;
    reg overflow_sync = 1'b0;
    reg busy_meta = 1'b0;
    reg busy_sync = 1'b0;
    reg [12:0] valid_interval_meta = 13'd0;
    reg [12:0] valid_interval_sync = 13'd0;

    always @(posedge ctrl_clk) begin
        if (!ctrl_resetn) begin
            done_meta <= 1'b0;
            done_sync <= 1'b0;
            overflow_meta <= 1'b0;
            overflow_sync <= 1'b0;
            busy_meta <= 1'b0;
            busy_sync <= 1'b0;
            valid_interval_meta <= 13'd0;
            valid_interval_sync <= 13'd0;
        end else begin
            done_meta <= done_axis;
            done_sync <= done_meta;
            overflow_meta <= overflow_axis;
            overflow_sync <= overflow_meta;
            busy_meta <= active;
            busy_sync <= busy_meta;
            valid_interval_meta <= valid_interval_axis;
            valid_interval_sync <= valid_interval_meta;
        end
    end

    assign status_ctrl = {
        16'hA832,
        valid_interval_sync,
        busy_sync,
        overflow_sync,
        done_sync
    };

endmodule
