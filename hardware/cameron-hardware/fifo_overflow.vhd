library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;


entity axis_lossy_fifo is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        --------------------------------------------------------------------
        -- Clock / reset
        --------------------------------------------------------------------
        aclk    : in  std_logic;
        aresetn : in  std_logic;

        --------------------------------------------------------------------
        -- AXI4-Stream input
        --
        -- TREADY remains HIGH during normal operation.
        -- If the FIFO fills, incoming samples are discarded.
        --------------------------------------------------------------------
        s_axis_tdata  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;

        --------------------------------------------------------------------
        -- AXI4-Stream output
        --
        -- This side obeys normal AXI4-Stream backpressure.
        --------------------------------------------------------------------
        m_axis_tdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;

        --------------------------------------------------------------------
        -- Debug / ILA outputs
        --------------------------------------------------------------------
        fifo_full      : out std_logic;
        fifo_empty     : out std_logic;

        -- 14 bits required to represent 0..8192
        fifo_count     : out std_logic_vector(13 downto 0);

        -- One-clock pulse whenever an input sample is dropped
        overflow_pulse : out std_logic;

        -- Total number of dropped samples since reset
        drop_count     : out std_logic_vector(31 downto 0)
    );
end entity axis_lossy_fifo;


architecture rtl of axis_lossy_fifo is

    ------------------------------------------------------------------------
    -- XPM FIFO signals
    ------------------------------------------------------------------------
    signal fifo_rst : std_logic;

    signal fifo_din  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal fifo_dout : std_logic_vector(DATA_WIDTH-1 downto 0);

    signal fifo_wr_en : std_logic;
    signal fifo_rd_en : std_logic;

    signal fifo_full_i  : std_logic;
    signal fifo_empty_i : std_logic;

    signal fifo_overflow_i : std_logic;

    signal fifo_wr_rst_busy : std_logic;
    signal fifo_rd_rst_busy : std_logic;

    signal fifo_wr_count : std_logic_vector(13 downto 0);
    signal fifo_rd_count : std_logic_vector(13 downto 0);

    signal drop_count_i : unsigned(31 downto 0) := (others => '0');


    ------------------------------------------------------------------------
    -- Vivado Block Design interface attributes
    ------------------------------------------------------------------------
    attribute X_INTERFACE_INFO : string;
    attribute X_INTERFACE_PARAMETER : string;

    ------------------------------------------------------------------------
    -- Clock
    ------------------------------------------------------------------------
    attribute X_INTERFACE_INFO of aclk : signal is
        "xilinx.com:signal:clock:1.0 aclk CLK";

    attribute X_INTERFACE_PARAMETER of aclk : signal is
        "ASSOCIATED_BUSIF s_axis:m_axis, ASSOCIATED_RESET aresetn";

    ------------------------------------------------------------------------
    -- Reset
    ------------------------------------------------------------------------
    attribute X_INTERFACE_INFO of aresetn : signal is
        "xilinx.com:signal:reset:1.0 aresetn RST";

    attribute X_INTERFACE_PARAMETER of aresetn : signal is
        "POLARITY ACTIVE_LOW";

    ------------------------------------------------------------------------
    -- AXI input
    ------------------------------------------------------------------------
    attribute X_INTERFACE_INFO of s_axis_tdata : signal is
        "xilinx.com:interface:axis:1.0 s_axis TDATA";

    attribute X_INTERFACE_INFO of s_axis_tvalid : signal is
        "xilinx.com:interface:axis:1.0 s_axis TVALID";

    attribute X_INTERFACE_INFO of s_axis_tready : signal is
        "xilinx.com:interface:axis:1.0 s_axis TREADY";

    ------------------------------------------------------------------------
    -- AXI output
    ------------------------------------------------------------------------
    attribute X_INTERFACE_INFO of m_axis_tdata : signal is
        "xilinx.com:interface:axis:1.0 m_axis TDATA";

    attribute X_INTERFACE_INFO of m_axis_tvalid : signal is
        "xilinx.com:interface:axis:1.0 m_axis TVALID";

    attribute X_INTERFACE_INFO of m_axis_tready : signal is
        "xilinx.com:interface:axis:1.0 m_axis TREADY";


begin

    ------------------------------------------------------------------------
    -- XPM FIFO uses active-HIGH reset.
    --
    -- aresetn should normally come from a Processor System Reset block
    -- clocked from the same clock as aclk.
    ------------------------------------------------------------------------
    fifo_rst <= not aresetn;


    ------------------------------------------------------------------------
    -- INPUT AXI INTERFACE
    --
    -- Deliberately NEVER apply backpressure during normal operation.
    ------------------------------------------------------------------------
    s_axis_tready <= '1' when aresetn = '1' else '0';

    fifo_din <= s_axis_tdata;


    ------------------------------------------------------------------------
    -- Request a FIFO write for every valid input sample.
    --
    -- IMPORTANT:
    --
    -- We deliberately DO NOT gate this with fifo_full.
    --
    -- If the FIFO is full, XPM_FIFO_SYNC rejects the write and asserts
    -- its overflow output. This is exactly the behaviour wanted here:
    --
    --     input keeps running
    --     FIFO contents remain valid
    --     newest sample gets discarded
    ------------------------------------------------------------------------
    fifo_wr_en <= s_axis_tvalid
                  when (
                      aresetn = '1' and
                      fifo_wr_rst_busy = '0' and
                      fifo_rd_rst_busy = '0'
                  )
                  else '0';


    ------------------------------------------------------------------------
    -- OUTPUT AXI INTERFACE
    --
    -- First-Word Fall-Through mode means fifo_dout already contains the
    -- next FIFO entry whenever fifo_empty_i = 0.
    ------------------------------------------------------------------------
    m_axis_tdata <= fifo_dout;

    m_axis_tvalid <= not fifo_empty_i
                     when (
                         aresetn = '1' and
                         fifo_rd_rst_busy = '0'
                     )
                     else '0';


    ------------------------------------------------------------------------
    -- Remove a word only when an AXI transfer actually occurs:
    --
    --       TVALID = 1
    --   AND TREADY = 1
    ------------------------------------------------------------------------
    fifo_rd_en <= m_axis_tready and
                  (not fifo_empty_i) and
                  (not fifo_rd_rst_busy) and
                  aresetn;


    ------------------------------------------------------------------------
    -- Debug outputs
    ------------------------------------------------------------------------
    fifo_full  <= fifo_full_i;
    fifo_empty <= fifo_empty_i;

    -- Write-side count represents FIFO occupancy for this equal-width,
    -- common-clock FIFO.
    fifo_count <= fifo_wr_count;

    overflow_pulse <= fifo_overflow_i;

    drop_count <= std_logic_vector(drop_count_i);


    ------------------------------------------------------------------------
    -- Dropped sample counter
    --
    -- XPM overflow pulses whenever a requested write was rejected because
    -- the FIFO was full.
    ------------------------------------------------------------------------
    process(aclk)
    begin
        if rising_edge(aclk) then

            if aresetn = '0' then
                drop_count_i <= (others => '0');

            else

                if fifo_overflow_i = '1' then
                    drop_count_i <= drop_count_i + 1;
                end if;

            end if;

        end if;
    end process;


    ------------------------------------------------------------------------
    -- XPM synchronous FIFO
    --
    -- Depth : 8192 samples
    -- Width : DATA_WIDTH, default 32 bits
    --
    -- For 32-bit IQ:
    --
    --     8192 × 32 bits
    --     = 262144 bits
    --     = 32 KiB
    --
    -- Block RAM is explicitly selected.
    ------------------------------------------------------------------------
    xpm_fifo_sync_inst : xpm_fifo_sync
        generic map (

            ----------------------------------------------------------------
            -- FIFO configuration
            ----------------------------------------------------------------
            FIFO_MEMORY_TYPE => "block",
            ECC_MODE         => "no_ecc",

            FIFO_WRITE_DEPTH => 8192,

            WRITE_DATA_WIDTH => DATA_WIDTH,
            READ_DATA_WIDTH  => DATA_WIDTH,

            ----------------------------------------------------------------
            -- 8192 entries:
            --
            -- log2(8192) + 1 = 14
            ----------------------------------------------------------------
            WR_DATA_COUNT_WIDTH => 14,
            RD_DATA_COUNT_WIDTH => 14,

            ----------------------------------------------------------------
            -- First Word Fall Through is ideal for AXI Stream.
            --
            -- dout contains the next valid word whenever EMPTY = 0.
            ----------------------------------------------------------------
            READ_MODE         => "fwft",
            FIFO_READ_LATENCY => 0,

            ----------------------------------------------------------------
            -- Reset
            ----------------------------------------------------------------
            FULL_RESET_VALUE => 0,
            DOUT_RESET_VALUE => "0",

            ----------------------------------------------------------------
            -- Programmable thresholds are unused, but valid values must
            -- still be supplied.
            ----------------------------------------------------------------
            PROG_FULL_THRESH  => 8180,
            PROG_EMPTY_THRESH => 10,

            ----------------------------------------------------------------
            -- Default advanced features include overflow and data counts.
            ----------------------------------------------------------------
            USE_ADV_FEATURES => "0707",

            ----------------------------------------------------------------
            -- Other XPM settings
            ----------------------------------------------------------------
            WAKEUP_TIME    => 0,
            CASCADE_HEIGHT => 0,
            SIM_ASSERT_CHK => 0
        )

        port map (

            ----------------------------------------------------------------
            -- Clock / reset
            ----------------------------------------------------------------
            rst    => fifo_rst,
            wr_clk => aclk,

            ----------------------------------------------------------------
            -- Write interface
            ----------------------------------------------------------------
            din   => fifo_din,
            wr_en => fifo_wr_en,

            full     => fifo_full_i,
            overflow => fifo_overflow_i,

            wr_data_count => fifo_wr_count,

            wr_rst_busy => fifo_wr_rst_busy,

            ----------------------------------------------------------------
            -- Read interface
            ----------------------------------------------------------------
            dout  => fifo_dout,
            rd_en => fifo_rd_en,

            empty => fifo_empty_i,

            rd_data_count => fifo_rd_count,

            rd_rst_busy => fifo_rd_rst_busy,

            ----------------------------------------------------------------
            -- Unused status outputs
            ----------------------------------------------------------------
            almost_full  => open,
            almost_empty => open,

            prog_full  => open,
            prog_empty => open,

            underflow => open,
            wr_ack    => open,
            data_valid => open,

            ----------------------------------------------------------------
            -- ECC unused
            ----------------------------------------------------------------
            sbiterr => open,
            dbiterr => open,

            injectsbiterr => '0',
            injectdbiterr => '0',

            ----------------------------------------------------------------
            -- Dynamic sleep unused
            ----------------------------------------------------------------
            sleep => '0'
        );


end architecture rtl;