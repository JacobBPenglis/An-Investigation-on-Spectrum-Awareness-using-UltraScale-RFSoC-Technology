library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;


entity tb_axis_lossy_fifo is
end entity tb_axis_lossy_fifo;


architecture sim of tb_axis_lossy_fifo is

    ------------------------------------------------------------------------
    -- Constants
    ------------------------------------------------------------------------
    constant DATA_WIDTH : integer := 32;

    -- 100 MHz simulation clock
    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------------
    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal s_axis_tdata  : std_logic_vector(DATA_WIDTH-1 downto 0)
                         := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;

    signal m_axis_tdata  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '0';

    signal fifo_full      : std_logic;
    signal fifo_empty     : std_logic;
    signal fifo_count     : std_logic_vector(13 downto 0);
    signal overflow_pulse : std_logic;
    signal drop_count     : std_logic_vector(31 downto 0);


    ------------------------------------------------------------------------
    -- Input counter
    ------------------------------------------------------------------------
    signal input_counter : unsigned(DATA_WIDTH-1 downto 0)
                         := (others => '0');


begin

    ------------------------------------------------------------------------
    -- DUT
    ------------------------------------------------------------------------
    dut : entity work.axis_lossy_fifo
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            aclk    => aclk,
            aresetn => aresetn,

            s_axis_tdata  => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,

            m_axis_tdata  => m_axis_tdata,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,

            fifo_full      => fifo_full,
            fifo_empty     => fifo_empty,
            fifo_count     => fifo_count,
            overflow_pulse => overflow_pulse,
            drop_count     => drop_count
        );


    ------------------------------------------------------------------------
    -- Clock generation
    ------------------------------------------------------------------------
    clock_proc : process
    begin
        while true loop

            aclk <= '0';
            wait for CLK_PERIOD / 2;

            aclk <= '1';
            wait for CLK_PERIOD / 2;

        end loop;
    end process;


    ------------------------------------------------------------------------
    -- Input counter generator
    --
    -- A new counter value is presented every clock while TVALID = 1.
    --
    -- Because the DUT deliberately keeps TREADY high, every input sample
    -- is considered consumed from the upstream point of view, even if the
    -- internal FIFO later has to discard it.
    ------------------------------------------------------------------------
    input_proc : process(aclk)
    begin
        if rising_edge(aclk) then

            if aresetn = '0' then

                input_counter <= (others => '0');
                s_axis_tdata  <= (others => '0');

            else

                if s_axis_tvalid = '1' and
                   s_axis_tready = '1' then

                    s_axis_tdata <=
                        std_logic_vector(input_counter + 1);

                    input_counter <= input_counter + 1;

                end if;

            end if;

        end if;
    end process;


    ------------------------------------------------------------------------
    -- Main test sequence
    ------------------------------------------------------------------------
    stimulus_proc : process
    begin

        --------------------------------------------------------------------
        -- Initial state
        --------------------------------------------------------------------
        s_axis_tvalid <= '0';
        m_axis_tready <= '0';
        aresetn       <= '0';


        --------------------------------------------------------------------
        -- Reset for 10 clock cycles
        --------------------------------------------------------------------
        wait for 10 * CLK_PERIOD;

        wait until falling_edge(aclk);

        aresetn <= '1';


        --------------------------------------------------------------------
        -- Give XPM FIFO some time to leave reset/busy state
        --------------------------------------------------------------------
        wait for 20 * CLK_PERIOD;


        --------------------------------------------------------------------
        -- TEST 1:
        -- Fill the FIFO.
        --
        -- The downstream is deliberately stalled:
        --
        --      m_axis_tready = 0
        --
        -- while the upstream sends one sample every clock.
        --------------------------------------------------------------------
        report "Starting FIFO fill test"
            severity note;

        m_axis_tready <= '0';
        s_axis_tvalid <= '1';


        --------------------------------------------------------------------
        -- FIFO depth is 8192.
        --
        -- Send significantly more than 8192 samples so that we definitely
        -- reach FULL and cause overflow.
        --
        -- 8500 cycles means approximately:
        --
        --      8192 stored samples
        --       308 dropped samples
        --
        -- assuming no output reads occur.
        --------------------------------------------------------------------
        for i in 0 to 8499 loop
            wait until rising_edge(aclk);
        end loop;


        --------------------------------------------------------------------
        -- Stop input momentarily
        --------------------------------------------------------------------
        wait until falling_edge(aclk);

        s_axis_tvalid <= '0';


        wait for 5 * CLK_PERIOD;


        --------------------------------------------------------------------
        -- Display results
        --------------------------------------------------------------------
        report "FIFO fill complete"
            severity note;

        report "FIFO count = " &
               integer'image(
                   to_integer(unsigned(fifo_count))
               )
            severity note;

        report "Drop count = " &
               integer'image(
                   to_integer(unsigned(drop_count))
               )
            severity note;


        --------------------------------------------------------------------
        -- Check FIFO became full
        --------------------------------------------------------------------
        assert fifo_full = '1'
            report "ERROR: FIFO did not become full."
            severity error;


        --------------------------------------------------------------------
        -- Check that samples were actually dropped.
        --------------------------------------------------------------------
        assert unsigned(drop_count) > 0
            report "ERROR: No samples were dropped."
            severity error;


        --------------------------------------------------------------------
        -- TEST 2:
        -- Drain the FIFO.
        --------------------------------------------------------------------
        report "Starting FIFO drain test"
            severity note;

        wait until falling_edge(aclk);

        m_axis_tready <= '1';


        --------------------------------------------------------------------
        -- Wait until FIFO reports empty.
        --------------------------------------------------------------------
        wait until fifo_empty = '1';


        --------------------------------------------------------------------
        -- Give it a few extra clocks
        --------------------------------------------------------------------
        wait for 10 * CLK_PERIOD;


        --------------------------------------------------------------------
        -- Stop downstream
        --------------------------------------------------------------------
        wait until falling_edge(aclk);

        m_axis_tready <= '0';


        --------------------------------------------------------------------
        -- Check FIFO drained correctly
        --------------------------------------------------------------------
        assert fifo_empty = '1'
            report "ERROR: FIFO did not drain."
            severity error;


        report "FIFO successfully drained"
            severity note;

        report "Final drop count = " &
               integer'image(
                   to_integer(unsigned(drop_count))
               )
            severity note;


        --------------------------------------------------------------------
        -- End simulation
        --------------------------------------------------------------------
        report "TESTBENCH COMPLETE"
            severity note;

        stop;

        wait;

    end process;


    ------------------------------------------------------------------------
    -- Output monitor
    --
    -- Prints samples as they are actually transferred out of the FIFO.
    --
    -- Comment this process out if the transcript becomes too verbose.
    ------------------------------------------------------------------------
    output_monitor : process(aclk)
    begin
        if rising_edge(aclk) then

            if m_axis_tvalid = '1' and
               m_axis_tready = '1' then

                report "FIFO OUTPUT = " &
                       integer'image(
                           to_integer(unsigned(m_axis_tdata))
                       );

            end if;

        end if;
    end process;


    ------------------------------------------------------------------------
    -- Overflow monitor
    ------------------------------------------------------------------------
    overflow_monitor : process(aclk)
    begin
        if rising_edge(aclk) then

            if overflow_pulse = '1' then

                report "FIFO OVERFLOW - sample dropped. Drop count = " &
                       integer'image(
                           to_integer(unsigned(drop_count))
                       )
                    severity note;

            end if;

        end if;
    end process;


end architecture sim;