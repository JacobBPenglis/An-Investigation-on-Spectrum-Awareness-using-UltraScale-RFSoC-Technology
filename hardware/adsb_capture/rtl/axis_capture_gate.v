`timescale 1ns / 1ps

// Cuts the continuous ADC stream into finite DMA frames.
//
// The ADC cannot be paused, so input samples are always accepted. Samples are
// dropped while idle. An output stall sets overflow and ends the short frame.
// Place a normal AXI stream FIFO directly after this block.
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
    output wire [2:0]               status_ctrl,

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

    // Write the sample count before changing arm_toggle. These registers move
    // both GPIO values into the stream clock domain.
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

    // Holds one output word if the FIFO stalls.
    reg [DATA_WIDTH-1:0] out_data = {DATA_WIDTH{1'b0}};
    reg                  out_valid = 1'b0;
    reg                  out_last = 1'b0;

    wire arm_event = arm_sync ^ arm_seen;
    wire out_fire = out_valid && m_axis_tready;

    // Always accept the live stream. Drop samples while idle.
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
        end else begin
            frame_samples_meta <= frame_samples_ctrl;
            frame_samples_sync <= frame_samples_meta;
            arm_meta <= arm_toggle_ctrl;
            arm_sync <= arm_meta;
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
                    // Do not start another sample on the last frame cycle.
                    if (!(out_fire && out_last)) begin
                        out_data <= s_axis_tdata;
                        out_valid <= 1'b1;
                        out_last <= (sample_count == frame_samples - 1'b1);
                        sample_count <= sample_count + 1'b1;
                    end
                end else begin
                    // The FIFO stalled while the ADC continued. End the frame
                    // and set overflow so Python rejects it.
                    overflow_axis <= 1'b1;
                    active <= 1'b0;
                    out_last <= 1'b1;
                end
            end
        end
    end

    // Move status bits back to the 100 MHz GPIO clock domain.
    reg done_meta = 1'b0;
    reg done_sync = 1'b0;
    reg overflow_meta = 1'b0;
    reg overflow_sync = 1'b0;
    reg busy_meta = 1'b0;
    reg busy_sync = 1'b0;

    always @(posedge ctrl_clk) begin
        if (!ctrl_resetn) begin
            done_meta <= 1'b0;
            done_sync <= 1'b0;
            overflow_meta <= 1'b0;
            overflow_sync <= 1'b0;
            busy_meta <= 1'b0;
            busy_sync <= 1'b0;
        end else begin
            done_meta <= done_axis;
            done_sync <= done_meta;
            overflow_meta <= overflow_axis;
            overflow_sync <= overflow_meta;
            busy_meta <= active;
            busy_sync <= busy_meta;
        end
    end

    assign status_ctrl = {busy_sync, overflow_sync, done_sync};

endmodule
