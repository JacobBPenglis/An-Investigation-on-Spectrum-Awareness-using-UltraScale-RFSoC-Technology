-- adsb_frame_gate_axi.vhd
--
-- AXI4-Stream ADS-B frame gate with AXI4-Lite configuration.
--
-- Stream format:
--   s_axis_tdata(15 downto 0)  = I, signed int16
--   s_axis_tdata(31 downto 16) = Q, signed int16
--
-- Register map (AXI4-Lite, 100 MHz domain):
--   0x00 CONTROL
--        bit 0 = 0 : AXI stream pass-through
--        bit 0 = 1 : ADS-B preamble detect/capture mode
--   0x04 THRESHOLD
--        uint32 threshold for the energy-domain preamble correlation score
--   0x08 TLAST_COUNT
--        uint32 number of accepted AXI-stream samples per TLAST in pass-through
--        mode. Default = 16384. A value of 0 disables generated TLAST pulses.
--
-- In pass-through mode (CONTROL bit 0 = 0) the core:
--   * Passes the 32-bit IQ stream through unchanged.
--   * Generates M_AXIS_TLAST every TLAST_COUNT accepted samples.
--
-- In detection mode the core:
--   1. Continuously stores incoming IQ samples into a circular buffer.
--   2. Correlates magnitude-squared samples against the 8 us ADS-B preamble.
--   3. On detection, captures a complete 112-bit ADS-B frame plus a 20%
--      buffer before and after the complete 120 us preamble+message frame.
--   4. Replays only that captured window on M_AXIS.
--   5. Pulses M_AXIS_TLAST with the final sample of the captured window.
--
-- IMPORTANT:
--   SAMPLE_RATE_HZ is the EFFECTIVE COMPLEX SAMPLE RATE, not AXIS_ACLK.
--   For the user's current design, AXIS_ACLK can be 160 MHz while the
--   effective sample rate is 10 MSPS if TVALID marks only 10 MSPS samples.
--
-- Default at 10 MSPS:
--   Preamble             = 80 samples
--   112-bit ADS-B data   = 1120 samples
--   Complete frame       = 1200 samples (120 us)
--   20% pre-buffer       = 240 samples
--   20% post-buffer      = 240 samples
--   Output capture       = 1680 samples
--
-- Notes:
--   * The detector uses |I+jQ|^2, so it is phase-independent.
--   * Correlation score = average power in expected preamble pulse slots
--                         - average power in expected quiet slots.
--   * During replay, S_AXIS_TREADY is deasserted so the captured RAM cannot
--     be overwritten. Upstream must obey AXI4-Stream backpressure.
--   * Set THRESHOLD before enabling CONTROL bit 0.
--
-- VHDL-2008 / Vivado compatible style.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adsb_frame_gate_axi is
    generic (
        -- Effective IQ sample rate. This is NOT the AXI stream clock rate.
        SAMPLE_RATE_HZ : positive := 10_000_000;

        -- Standard ADS-B Extended Squitter message length.
        ADSB_DATA_BITS : positive := 112;

        -- Buffer on each side as a percentage of the complete
        -- preamble + ADS-B message duration.
        BUFFER_PERCENT : natural := 20;

        -- Number of preamble correlation taps evaluated per AXIS clock.
        -- At 10 MSPS and 160 MHz AXIS clock, 8 taps/clock evaluates the
        -- 80-sample preamble in 10 clocks, comfortably inside the 16-clock
        -- interval between samples.
        CORR_TAPS_PER_CLK : positive := 8;

        -- Circular sample RAM depth. Must be >= OUTPUT_SAMPLES.
        -- 2048 is sufficient for the default 10 MSPS configuration.
        RAM_DEPTH      : positive := 2048
    );
    port (
        --------------------------------------------------------------------
        -- AXI4-Stream domain -- 160 MHz in the user's design
        --------------------------------------------------------------------
        axis_aclk       : in  std_logic;
        axis_aresetn    : in  std_logic;

        s_axis_tdata    : in  std_logic_vector(31 downto 0);
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;

        m_axis_tdata    : out std_logic_vector(31 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;

        --------------------------------------------------------------------
        -- AXI4-Lite domain -- 100 MHz in the user's design
        --------------------------------------------------------------------
        s_axi_aclk      : in  std_logic;
        s_axi_aresetn   : in  std_logic;

        s_axi_awaddr    : in  std_logic_vector(3 downto 0);
        s_axi_awvalid   : in  std_logic;
        s_axi_awready   : out std_logic;

        s_axi_wdata     : in  std_logic_vector(31 downto 0);
        s_axi_wstrb     : in  std_logic_vector(3 downto 0);
        s_axi_wvalid    : in  std_logic;
        s_axi_wready    : out std_logic;

        s_axi_bresp     : out std_logic_vector(1 downto 0);
        s_axi_bvalid    : out std_logic;
        s_axi_bready    : in  std_logic;

        s_axi_araddr    : in  std_logic_vector(3 downto 0);
        s_axi_arvalid   : in  std_logic;
        s_axi_arready   : out std_logic;

        s_axi_rdata     : out std_logic_vector(31 downto 0);
        s_axi_rresp     : out std_logic_vector(1 downto 0);
        s_axi_rvalid    : out std_logic;
        s_axi_rready    : in  std_logic
    );
end entity;

architecture rtl of adsb_frame_gate_axi is

    ------------------------------------------------------------------------
    -- Timing constants for ADS-B / Mode S
    --
    -- ADS-B preamble pulse starts, in 0.5 us units:
    --   0.0 us, 1.0 us, 3.5 us, 4.5 us
    -- Each pulse is 0.5 us wide.
    ------------------------------------------------------------------------
    constant HALF_US_SAMPLES : positive := SAMPLE_RATE_HZ / 2_000_000;

    constant PREAMBLE_SAMPLES : positive := 16 * HALF_US_SAMPLES; -- 8 us
    constant DATA_SAMPLES     : positive := 2 * ADSB_DATA_BITS * HALF_US_SAMPLES;
    constant FRAME_SAMPLES    : positive := PREAMBLE_SAMPLES + DATA_SAMPLES;

    constant BUFFER_SAMPLES   : natural := (FRAME_SAMPLES * BUFFER_PERCENT) / 100;
    constant OUTPUT_SAMPLES   : positive := FRAME_SAMPLES + (2 * BUFFER_SAMPLES);

    -- Current sample is the final preamble sample at trigger time, so these
    -- are the samples still required after the trigger.
    constant CAPTURE_AFTER_TRIGGER : positive := DATA_SAMPLES + BUFFER_SAMPLES;

    constant PREAMBLE_ON_SAMPLES  : positive := 4 * HALF_US_SAMPLES;
    constant PREAMBLE_OFF_SAMPLES : positive := PREAMBLE_SAMPLES - PREAMBLE_ON_SAMPLES;

    -- Number of accepted samples that must already exist before a trigger
    -- is permitted, ensuring both a complete preamble history and the full
    -- pre-trigger buffer are valid in RAM.
    constant MIN_HISTORY_SAMPLES : positive := PREAMBLE_SAMPLES + BUFFER_SAMPLES;

    ------------------------------------------------------------------------
    -- Helper functions
    ------------------------------------------------------------------------
    function merge_wstrb(
        old_value : std_logic_vector(31 downto 0);
        new_value : std_logic_vector(31 downto 0);
        wstrb     : std_logic_vector(3 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(31 downto 0) := old_value;
    begin
        for b in 0 to 3 loop
            if wstrb(b) = '1' then
                result((8*b)+7 downto 8*b) := new_value((8*b)+7 downto 8*b);
            end if;
        end loop;
        return result;
    end function;

    function inc_ptr(ptr : integer) return integer is
    begin
        if ptr = RAM_DEPTH - 1 then
            return 0;
        else
            return ptr + 1;
        end if;
    end function;

    function wrap_sub(ptr : integer; amount : natural) return integer is
        variable a : integer;
    begin
        a := integer(amount mod RAM_DEPTH);
        return (ptr - a + RAM_DEPTH) mod RAM_DEPTH;
    end function;

    function preamble_is_on(sample_index : natural) return boolean is
        variable h : natural := HALF_US_SAMPLES;
    begin
        -- Pulse 1: 0.0 to 0.5 us
        if sample_index < h then
            return true;
        end if;

        -- Pulse 2: 1.0 to 1.5 us
        if (sample_index >= 2*h) and (sample_index < 3*h) then
            return true;
        end if;

        -- Pulse 3: 3.5 to 4.0 us
        if (sample_index >= 7*h) and (sample_index < 8*h) then
            return true;
        end if;

        -- Pulse 4: 4.5 to 5.0 us
        if (sample_index >= 9*h) and (sample_index < 10*h) then
            return true;
        end if;

        return false;
    end function;

    ------------------------------------------------------------------------
    -- AXI4-Lite register bank
    ------------------------------------------------------------------------
    signal control_reg_axi     : std_logic_vector(31 downto 0) := (others => '0');
    signal threshold_reg_axi   : std_logic_vector(31 downto 0) := (others => '0');
    signal tlast_count_reg_axi : std_logic_vector(31 downto 0) := x"00004000"; -- 16384
    signal control_toggle_axi     : std_logic := '0';
    signal threshold_toggle_axi   : std_logic := '0';
    signal tlast_count_toggle_axi : std_logic := '0';

    signal aw_hold_valid : std_logic := '0';
    signal awaddr_hold   : std_logic_vector(3 downto 0) := (others => '0');
    signal w_hold_valid  : std_logic := '0';
    signal wdata_hold    : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb_hold    : std_logic_vector(3 downto 0) := (others => '0');

    signal bvalid_i : std_logic := '0';
    signal rvalid_i : std_logic := '0';
    signal rdata_i  : std_logic_vector(31 downto 0) := (others => '0');

    ------------------------------------------------------------------------
    -- Configuration CDC: 100 MHz AXI-Lite -> 160 MHz stream domain
    --
    -- Data buses are allowed to settle through three synchronizer stages.
    -- A toggle is used as the commit indication so the stream domain latches
    -- a coherent configuration after a software write.
    ------------------------------------------------------------------------
    signal control_sync1, control_sync2, control_sync3 : std_logic_vector(31 downto 0) := (others => '0');
    signal threshold_sync1, threshold_sync2, threshold_sync3 : std_logic_vector(31 downto 0) := (others => '0');
    signal tlast_count_sync1, tlast_count_sync2, tlast_count_sync3 : std_logic_vector(31 downto 0) := x"00004000";
    signal control_toggle_sync1, control_toggle_sync2, control_toggle_sync3, control_toggle_seen : std_logic := '0';
    signal threshold_toggle_sync1, threshold_toggle_sync2, threshold_toggle_sync3, threshold_toggle_seen : std_logic := '0';
    signal tlast_count_toggle_sync1, tlast_count_toggle_sync2, tlast_count_toggle_sync3, tlast_count_toggle_seen : std_logic := '0';
    signal cdc_init_count : integer range 0 to 3 := 0;
    signal cdc_init_done  : std_logic := '0';

    signal axi_awready_i : std_logic := '0';
    signal axi_wready_i  : std_logic := '0';
    signal axi_arready_i : std_logic := '0';
    signal axis_tready_i : std_logic := '0';

    signal detector_enable    : std_logic := '0';
    signal threshold_stream   : unsigned(31 downto 0) := (others => '0');
    signal tlast_count_stream : unsigned(31 downto 0) := to_unsigned(16384, 32);
    signal tlast_count_update : std_logic := '0';

    -- Pass-through TLAST counter. Counts accepted transfers, not clock cycles.
    signal pass_sample_count : unsigned(31 downto 0) := (others => '0');

    ------------------------------------------------------------------------
    -- Detector / capture RAM
    ------------------------------------------------------------------------
    subtype power_t is unsigned(32 downto 0);
    subtype sum_t   is unsigned(47 downto 0);

    -- Small circular history used by the time-multiplexed preamble correlator.
    -- This is intentionally separate from the IQ capture RAM.
    type power_mem_t is array (0 to PREAMBLE_SAMPLES-1) of power_t;
    signal power_mem : power_mem_t := (others => (others => '0'));

    signal power_wr_ptr  : integer range 0 to PREAMBLE_SAMPLES-1 := 0;
    signal corr_base_ptr : integer range 0 to PREAMBLE_SAMPLES-1 := 0;
    signal corr_index    : integer range 0 to PREAMBLE_SAMPLES := 0;
    signal corr_busy     : std_logic := '0';
    signal corr_on_acc   : sum_t := (others => '0');
    signal corr_off_acc  : sum_t := (others => '0');

    type sample_ram_t is array (0 to RAM_DEPTH-1) of std_logic_vector(31 downto 0);
    signal sample_ram : sample_ram_t;

    attribute ram_style : string;
    attribute ram_style of power_mem  : signal is "distributed";
    attribute ram_style of sample_ram : signal is "block";

    type gate_state_t is (SEARCH, CAPTURE, PLAYBACK);
    signal gate_state : gate_state_t := SEARCH;

    signal write_ptr         : integer range 0 to RAM_DEPTH-1 := 0;
    signal capture_start_ptr : integer range 0 to RAM_DEPTH-1 := 0;
    signal read_ptr          : integer range 0 to RAM_DEPTH-1 := 0;

    signal seen_samples : integer range 0 to MIN_HISTORY_SAMPLES := 0;
    signal capture_remaining : integer range 0 to CAPTURE_AFTER_TRIGGER := 0;
    signal play_loaded       : integer range 0 to OUTPUT_SAMPLES := 0;

    signal out_data_i  : std_logic_vector(31 downto 0) := (others => '0');
    signal out_valid_i : std_logic := '0';

begin

    ------------------------------------------------------------------------
    -- Static configuration checks
    ------------------------------------------------------------------------
    assert SAMPLE_RATE_HZ mod 2_000_000 = 0
        report "SAMPLE_RATE_HZ must be an integer multiple of 2 MHz so the 0.5 us ADS-B pulse timing maps exactly to samples."
        severity failure;

    assert RAM_DEPTH >= OUTPUT_SAMPLES
        report "RAM_DEPTH is too small for the requested ADS-B frame plus pre/post buffers."
        severity failure;

    assert CORR_TAPS_PER_CLK <= PREAMBLE_SAMPLES
        report "CORR_TAPS_PER_CLK cannot exceed PREAMBLE_SAMPLES."
        severity failure;

    ------------------------------------------------------------------------
    -- AXI4-Lite combinational outputs
    ------------------------------------------------------------------------
    axi_awready_i <= '1' when (aw_hold_valid = '0' and bvalid_i = '0') else '0';
    axi_wready_i  <= '1' when (w_hold_valid  = '0' and bvalid_i = '0') else '0';
    s_axi_awready <= axi_awready_i;
    s_axi_wready  <= axi_wready_i;

    s_axi_bresp  <= "00"; -- OKAY
    s_axi_bvalid <= bvalid_i;

    axi_arready_i <= not rvalid_i;
    s_axi_arready <= axi_arready_i;
    s_axi_rresp   <= "00"; -- OKAY
    s_axi_rvalid  <= rvalid_i;
    s_axi_rdata   <= rdata_i;

    ------------------------------------------------------------------------
    -- AXI4-Lite register access
    ------------------------------------------------------------------------
    axi_lite_proc : process(s_axi_aclk)
        variable merged : std_logic_vector(31 downto 0);
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                control_reg_axi     <= (others => '0');
                threshold_reg_axi   <= (others => '0');
                tlast_count_reg_axi <= x"00004000";
                control_toggle_axi     <= '0';
                threshold_toggle_axi   <= '0';
                tlast_count_toggle_axi <= '0';

                aw_hold_valid <= '0';
                awaddr_hold   <= (others => '0');
                w_hold_valid  <= '0';
                wdata_hold    <= (others => '0');
                wstrb_hold    <= (others => '0');

                bvalid_i <= '0';
                rvalid_i <= '0';
                rdata_i  <= (others => '0');
            else
                ------------------------------------------------------------
                -- Capture independent AXI-Lite write address/data channels
                ------------------------------------------------------------
                if (s_axi_awvalid = '1') and (axi_awready_i = '1') then
                    aw_hold_valid <= '1';
                    awaddr_hold   <= s_axi_awaddr;
                end if;

                if (s_axi_wvalid = '1') and (axi_wready_i = '1') then
                    w_hold_valid <= '1';
                    wdata_hold   <= s_axi_wdata;
                    wstrb_hold   <= s_axi_wstrb;
                end if;

                ------------------------------------------------------------
                -- Write response completion
                ------------------------------------------------------------
                if (bvalid_i = '1') and (s_axi_bready = '1') then
                    bvalid_i <= '0';
                end if;

                ------------------------------------------------------------
                -- Perform write once both address and data have arrived
                ------------------------------------------------------------
                if (bvalid_i = '0') and
                   (aw_hold_valid = '1') and
                   (w_hold_valid = '1') then

                    case awaddr_hold(3 downto 2) is
                        when "00" => -- 0x00 CONTROL
                            merged := merge_wstrb(control_reg_axi, wdata_hold, wstrb_hold);
                            control_reg_axi <= merged;
                            control_toggle_axi <= not control_toggle_axi;

                        when "01" => -- 0x04 THRESHOLD
                            merged := merge_wstrb(threshold_reg_axi, wdata_hold, wstrb_hold);
                            threshold_reg_axi <= merged;
                            threshold_toggle_axi <= not threshold_toggle_axi;

                        when "10" => -- 0x08 TLAST_COUNT
                            merged := merge_wstrb(tlast_count_reg_axi, wdata_hold, wstrb_hold);
                            tlast_count_reg_axi <= merged;
                            tlast_count_toggle_axi <= not tlast_count_toggle_axi;

                        when others =>
                            null;
                    end case;

                    aw_hold_valid <= '0';
                    w_hold_valid  <= '0';
                    bvalid_i      <= '1';
                end if;

                ------------------------------------------------------------
                -- AXI-Lite reads
                ------------------------------------------------------------
                if (rvalid_i = '1') and (s_axi_rready = '1') then
                    rvalid_i <= '0';
                end if;

                if (s_axi_arvalid = '1') and (axi_arready_i = '1') then
                    case s_axi_araddr(3 downto 2) is
                        when "00" =>
                            rdata_i <= control_reg_axi;
                        when "01" =>
                            rdata_i <= threshold_reg_axi;
                        when "10" =>
                            rdata_i <= tlast_count_reg_axi;
                        when others =>
                            rdata_i <= (others => '0');
                    end case;
                    rvalid_i <= '1';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- Configuration clock-domain crossing
    ------------------------------------------------------------------------
    cfg_cdc_proc : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if axis_aresetn = '0' then
                control_sync1   <= (others => '0');
                control_sync2   <= (others => '0');
                control_sync3   <= (others => '0');
                threshold_sync1 <= (others => '0');
                threshold_sync2 <= (others => '0');
                threshold_sync3 <= (others => '0');
                tlast_count_sync1 <= x"00004000";
                tlast_count_sync2 <= x"00004000";
                tlast_count_sync3 <= x"00004000";
                control_toggle_sync1   <= '0';
                control_toggle_sync2   <= '0';
                control_toggle_sync3   <= '0';
                control_toggle_seen    <= '0';
                threshold_toggle_sync1 <= '0';
                threshold_toggle_sync2 <= '0';
                threshold_toggle_sync3 <= '0';
                threshold_toggle_seen  <= '0';
                tlast_count_toggle_sync1 <= '0';
                tlast_count_toggle_sync2 <= '0';
                tlast_count_toggle_sync3 <= '0';
                tlast_count_toggle_seen  <= '0';
                cdc_init_count  <= 0;
                cdc_init_done   <= '0';
                detector_enable    <= '0';
                threshold_stream   <= (others => '0');
                tlast_count_stream <= to_unsigned(16384, 32);
                tlast_count_update <= '0';
            else
                control_sync1   <= control_reg_axi;
                control_sync2   <= control_sync1;
                control_sync3   <= control_sync2;

                threshold_sync1 <= threshold_reg_axi;
                threshold_sync2 <= threshold_sync1;
                threshold_sync3 <= threshold_sync2;

                tlast_count_sync1 <= tlast_count_reg_axi;
                tlast_count_sync2 <= tlast_count_sync1;
                tlast_count_sync3 <= tlast_count_sync2;

                control_toggle_sync1   <= control_toggle_axi;
                control_toggle_sync2   <= control_toggle_sync1;
                control_toggle_sync3   <= control_toggle_sync2;
                threshold_toggle_sync1 <= threshold_toggle_axi;
                threshold_toggle_sync2 <= threshold_toggle_sync1;
                threshold_toggle_sync3 <= threshold_toggle_sync2;
                tlast_count_toggle_sync1 <= tlast_count_toggle_axi;
                tlast_count_toggle_sync2 <= tlast_count_toggle_sync1;
                tlast_count_toggle_sync3 <= tlast_count_toggle_sync2;

                -- Default low; pulsed for one AXIS clock when TLAST_COUNT commits.
                tlast_count_update <= '0';

                -- Initial load also makes the CDC robust if only the stream
                -- domain is reset after software has already configured regs.
                if cdc_init_done = '0' then
                    if cdc_init_count < 3 then
                        cdc_init_count <= cdc_init_count + 1;
                    else
                        detector_enable       <= control_sync3(0);
                        threshold_stream      <= unsigned(threshold_sync3);
                        tlast_count_stream    <= unsigned(tlast_count_sync3);
                        control_toggle_seen   <= control_toggle_sync3;
                        threshold_toggle_seen <= threshold_toggle_sync3;
                        tlast_count_toggle_seen <= tlast_count_toggle_sync3;
                        tlast_count_update    <= '1';
                        cdc_init_done         <= '1';
                    end if;
                else
                    if control_toggle_sync3 /= control_toggle_seen then
                        detector_enable     <= control_sync3(0);
                        control_toggle_seen <= control_toggle_sync3;
                    end if;

                    if threshold_toggle_sync3 /= threshold_toggle_seen then
                        threshold_stream      <= unsigned(threshold_sync3);
                        threshold_toggle_seen <= threshold_toggle_sync3;
                    end if;

                    if tlast_count_toggle_sync3 /= tlast_count_toggle_seen then
                        tlast_count_stream      <= unsigned(tlast_count_sync3);
                        tlast_count_toggle_seen <= tlast_count_toggle_sync3;
                        tlast_count_update      <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- AXI4-Stream routing
    ------------------------------------------------------------------------
    s_axis_tready <= axis_tready_i;

    stream_mux_proc : process(
        detector_enable,
        m_axis_tready,
        s_axis_tdata,
        s_axis_tvalid,
        tlast_count_stream,
        pass_sample_count,
        gate_state,
        corr_busy,
        out_data_i,
        out_valid_i,
        play_loaded
    )
    begin
        if detector_enable = '0' then
            -- Transparent pass-through mode.
            axis_tready_i <= m_axis_tready;
            m_axis_tdata  <= s_axis_tdata;
            m_axis_tvalid <= s_axis_tvalid;

            -- Generate TLAST on every Nth accepted sample. Keeping TLAST
            -- combinational from the current count ensures it remains asserted
            -- with the same sample if downstream deasserts TREADY.
            if (tlast_count_stream /= 0) and
               (pass_sample_count = (tlast_count_stream - 1)) and
               (s_axis_tvalid = '1') then
                m_axis_tlast <= '1';
            else
                m_axis_tlast <= '0';
            end if;
        else
            -- Detection/capture mode.
            -- Input runs freely while searching/capturing, then is stalled
            -- briefly while the completed event window is replayed.
            if gate_state = PLAYBACK then
                axis_tready_i <= '0';
            elsif (gate_state = SEARCH) and (corr_busy = '1') then
                -- The correlator is time-multiplexed across several 160 MHz
                -- clocks. At the default 10 MSPS effective sample rate there
                -- is ample time before the next sample arrives.
                axis_tready_i <= '0';
            else
                axis_tready_i <= '1';
            end if;

            m_axis_tdata  <= out_data_i;
            m_axis_tvalid <= out_valid_i;

            if (gate_state = PLAYBACK) and
               (out_valid_i = '1') and
               (play_loaded = OUTPUT_SAMPLES) then
                m_axis_tlast <= '1';
            else
                m_axis_tlast <= '0';
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- Pass-through TLAST counter
    --
    -- The counter advances only on a completed AXI transfer. Therefore TLAST
    -- is based on samples actually accepted by the downstream slave, exactly
    -- matching the behaviour of the original axis_tlast_generator block.
    ------------------------------------------------------------------------
    passthrough_tlast_proc : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if axis_aresetn = '0' then
                pass_sample_count <= (others => '0');
            else
                -- Start a fresh pass-through frame when the interval changes,
                -- or while detection mode is active.
                if (detector_enable = '1') or (tlast_count_update = '1') then
                    pass_sample_count <= (others => '0');
                elsif (detector_enable = '0') and
                      (s_axis_tvalid = '1') and
                      (m_axis_tready = '1') then
                    if tlast_count_stream = 0 then
                        pass_sample_count <= (others => '0');
                    elsif pass_sample_count = (tlast_count_stream - 1) then
                        pass_sample_count <= (others => '0');
                    else
                        pass_sample_count <= pass_sample_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- ADS-B preamble detector, frame capture and replay
    ------------------------------------------------------------------------
    detector_proc : process(axis_aclk)
        variable i_s, q_s : signed(15 downto 0);
        variable i_sq, q_sq : signed(31 downto 0);
        variable power_v : power_t;
        variable tap_power_v : power_t;

        variable on_group_v, off_group_v : sum_t;
        variable on_total_v, off_total_v : sum_t;

        variable corr_lhs_v, corr_score_v : unsigned(63 downto 0);
        variable threshold_scaled_v : unsigned(63 downto 0);

        variable next_wr_v : integer range 0 to RAM_DEPTH-1;
        variable next_power_wr_v : integer range 0 to PREAMBLE_SAMPLES-1;
        variable tap_index_v : integer;
        variable mem_index_v : integer range 0 to PREAMBLE_SAMPLES-1;
    begin
        if rising_edge(axis_aclk) then
            if axis_aresetn = '0' then
                gate_state <= SEARCH;

                write_ptr         <= 0;
                capture_start_ptr <= 0;
                read_ptr          <= 0;

                seen_samples      <= 0;
                capture_remaining <= 0;
                play_loaded       <= 0;

                out_data_i  <= (others => '0');
                out_valid_i <= '0';

                power_mem      <= (others => (others => '0'));
                power_wr_ptr   <= 0;
                corr_base_ptr  <= 0;
                corr_index     <= 0;
                corr_busy      <= '0';
                corr_on_acc    <= (others => '0');
                corr_off_acc   <= (others => '0');
            else
                ----------------------------------------------------------------
                -- Disabled: keep detector reset while the stream passes through.
                ----------------------------------------------------------------
                if detector_enable = '0' then
                    gate_state <= SEARCH;
                    write_ptr  <= 0;
                    read_ptr   <= 0;
                    seen_samples      <= 0;
                    capture_remaining <= 0;
                    play_loaded       <= 0;
                    out_valid_i       <= '0';

                    power_wr_ptr  <= 0;
                    corr_base_ptr <= 0;
                    corr_index    <= 0;
                    corr_busy     <= '0';
                    corr_on_acc   <= (others => '0');
                    corr_off_acc  <= (others => '0');

                else
                    case gate_state is

                        --------------------------------------------------------
                        -- Search for an ADS-B preamble.
                        --------------------------------------------------------
                        when SEARCH =>
                            out_valid_i <= '0';
                            play_loaded <= 0;

                            ----------------------------------------------------
                            -- Time-multiplexed energy-domain matched correlator.
                            --
                            -- With 10 MSPS input and 160 MHz AXIS clock there
                            -- are 16 fabric clocks per sample. The default
                            -- 8 taps/clock processes the 80-sample preamble in
                            -- 10 clocks, avoiding an 80-adder combinational path.
                            ----------------------------------------------------
                            if corr_busy = '1' then
                                on_group_v  := (others => '0');
                                off_group_v := (others => '0');

                                for lane in 0 to CORR_TAPS_PER_CLK-1 loop
                                    tap_index_v := corr_index + lane;

                                    if tap_index_v < PREAMBLE_SAMPLES then
                                        mem_index_v := (corr_base_ptr + tap_index_v) mod PREAMBLE_SAMPLES;
                                        tap_power_v := power_mem(mem_index_v);

                                        if preamble_is_on(tap_index_v) then
                                            on_group_v := on_group_v + resize(tap_power_v, on_group_v'length);
                                        else
                                            off_group_v := off_group_v + resize(tap_power_v, off_group_v'length);
                                        end if;
                                    end if;
                                end loop;

                                on_total_v  := corr_on_acc  + on_group_v;
                                off_total_v := corr_off_acc + off_group_v;

                                if (corr_index + CORR_TAPS_PER_CLK) >= PREAMBLE_SAMPLES then
                                    -- For the ADS-B preamble, Noff = 3*Non.
                                    --
                                    -- avg_on - avg_off >= THRESHOLD
                                    -- is equivalent to
                                    -- 3*sum_on - sum_off >= Noff*THRESHOLD.
                                    --
                                    -- This avoids hardware division and keeps
                                    -- THRESHOLD in intuitive average-power units.
                                    corr_lhs_v := shift_left(resize(on_total_v, 64), 1) +
                                                  resize(on_total_v, 64);

                                    if corr_lhs_v > resize(off_total_v, 64) then
                                        corr_score_v := corr_lhs_v - resize(off_total_v, 64);
                                    else
                                        corr_score_v := (others => '0');
                                    end if;

                                    threshold_scaled_v := threshold_stream *
                                                          to_unsigned(PREAMBLE_OFF_SAMPLES, 32);

                                    corr_busy    <= '0';
                                    corr_index   <= 0;
                                    corr_on_acc  <= (others => '0');
                                    corr_off_acc <= (others => '0');

                                    -- Do not trigger until the circular IQ RAM
                                    -- contains the requested pre-trigger buffer.
                                    if (seen_samples >= MIN_HISTORY_SAMPLES) and
                                       (corr_score_v >= threshold_scaled_v) then

                                        -- write_ptr already points one sample
                                        -- beyond the candidate preamble end,
                                        -- because input is backpressured while
                                        -- the correlator is running.
                                        capture_start_ptr <= wrap_sub(
                                            write_ptr,
                                            PREAMBLE_SAMPLES + BUFFER_SAMPLES
                                        );

                                        capture_remaining <= CAPTURE_AFTER_TRIGGER;
                                        gate_state <= CAPTURE;
                                    end if;
                                else
                                    corr_on_acc  <= on_total_v;
                                    corr_off_acc <= off_total_v;
                                    corr_index   <= corr_index + CORR_TAPS_PER_CLK;
                                end if;

                            ----------------------------------------------------
                            -- Accept the next IQ sample only when the previous
                            -- correlation has completed.
                            ----------------------------------------------------
                            elsif (s_axis_tvalid = '1') and (axis_tready_i = '1') then
                                ------------------------------------------------
                                -- Store IQ sample in circular capture RAM.
                                ------------------------------------------------
                                sample_ram(write_ptr) <= s_axis_tdata;
                                next_wr_v := inc_ptr(write_ptr);
                                write_ptr <= next_wr_v;

                                ------------------------------------------------
                                -- Magnitude-squared power = I^2 + Q^2.
                                ------------------------------------------------
                                i_s := signed(s_axis_tdata(15 downto 0));
                                q_s := signed(s_axis_tdata(31 downto 16));

                                i_sq := i_s * i_s;
                                q_sq := q_s * q_s;

                                power_v := resize(unsigned(i_sq), power_v'length) +
                                           resize(unsigned(q_sq), power_v'length);

                                ------------------------------------------------
                                -- Add newest power sample to the circular
                                -- preamble history. The next write pointer is
                                -- also the oldest sample in a full history.
                                ------------------------------------------------
                                power_mem(power_wr_ptr) <= power_v;

                                if power_wr_ptr = PREAMBLE_SAMPLES-1 then
                                    next_power_wr_v := 0;
                                else
                                    next_power_wr_v := power_wr_ptr + 1;
                                end if;

                                power_wr_ptr  <= next_power_wr_v;
                                corr_base_ptr <= next_power_wr_v;

                                -- Start a fresh correlation pass. The memory
                                -- write above is visible by the first correlator
                                -- cycle on the following AXIS clock.
                                corr_index   <= 0;
                                corr_on_acc  <= (others => '0');
                                corr_off_acc <= (others => '0');
                                corr_busy    <= '1';

                                if seen_samples < MIN_HISTORY_SAMPLES then
                                    seen_samples <= seen_samples + 1;
                                end if;
                            end if;

                        --------------------------------------------------------
                        -- Capture the 112 us data field plus post-buffer.
                        --------------------------------------------------------
                        when CAPTURE =>
                            out_valid_i <= '0';
                            corr_busy   <= '0';

                            if (s_axis_tvalid = '1') and (axis_tready_i = '1') then
                                sample_ram(write_ptr) <= s_axis_tdata;
                                next_wr_v := inc_ptr(write_ptr);
                                write_ptr <= next_wr_v;

                                if capture_remaining = 1 then
                                    capture_remaining <= 0;
                                    read_ptr    <= capture_start_ptr;
                                    play_loaded <= 0;
                                    out_valid_i <= '0';
                                    gate_state  <= PLAYBACK;
                                else
                                    capture_remaining <= capture_remaining - 1;
                                end if;
                            end if;

                        --------------------------------------------------------
                        -- Replay exactly one complete buffered ADS-B event.
                        --------------------------------------------------------
                        when PLAYBACK =>
                            corr_busy <= '0';

                            -- Load a new output word whenever the output
                            -- register is empty or the previous word was
                            -- accepted by the downstream AXI slave.
                            if (out_valid_i = '0') or (m_axis_tready = '1') then
                                if play_loaded < OUTPUT_SAMPLES then
                                    out_data_i  <= sample_ram(read_ptr);
                                    read_ptr    <= inc_ptr(read_ptr);
                                    play_loaded <= play_loaded + 1;
                                    out_valid_i <= '1';
                                else
                                    -- Final word has just been accepted.
                                    out_valid_i <= '0';
                                    gate_state  <= SEARCH;
                                    seen_samples <= 0;
                                    play_loaded <= 0;

                                    -- Refill a fresh power history before the
                                    -- next trigger is permitted.
                                    power_wr_ptr  <= 0;
                                    corr_base_ptr <= 0;
                                    corr_index    <= 0;
                                    corr_on_acc   <= (others => '0');
                                    corr_off_acc  <= (others => '0');
                                end if;
                            end if;

                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture;
