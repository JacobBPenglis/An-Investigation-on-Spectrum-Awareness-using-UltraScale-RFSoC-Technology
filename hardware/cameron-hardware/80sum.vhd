library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_sum80 is
    port (
        aclk    : in  std_logic;
        aresetn : in  std_logic;

        -- AXI Stream input: unsigned 64-bit
        s_axis_tdata  : in  std_logic_vector(63 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;

        -- AXI Stream output:
        -- 71-bit full-precision result zero-padded to 72 bits
        m_axis_tdata  : out std_logic_vector(71 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic
    );
end entity;


architecture rtl of axis_sum80 is

    constant TAPS   : integer := 80;
    constant DATA_W : integer := 64;
    constant ACC_W  : integer := 71;

    ------------------------------------------------------------
    -- 80-sample circular delay line
    ------------------------------------------------------------

    type sample_array_t is array (0 to TAPS-1)
        of unsigned(DATA_W-1 downto 0);

    signal delay_line : sample_array_t :=
        (others => (others => '0'));

    signal wr_ptr : integer range 0 to TAPS-1 := 0;


    ------------------------------------------------------------
    -- Full-precision 71-bit running sum
    ------------------------------------------------------------

    signal running_sum : unsigned(ACC_W-1 downto 0) :=
        (others => '0');


    ------------------------------------------------------------
    -- AXI output register
    ------------------------------------------------------------

    signal out_data : std_logic_vector(71 downto 0) :=
        (others => '0');

    signal out_valid : std_logic := '0';

    signal in_ready : std_logic;

begin

    ------------------------------------------------------------
    -- AXI Stream connections
    ------------------------------------------------------------

    in_ready <= (not out_valid) or m_axis_tready;

    s_axis_tready <= in_ready;

    m_axis_tdata  <= out_data;
    m_axis_tvalid <= out_valid;


    ------------------------------------------------------------
    -- 80-sample moving sum
    --
    -- y[n] = x[n] + x[n-1] + ... + x[n-79]
    --
    -- Implemented efficiently as:
    --
    -- new_sum = old_sum - oldest_sample + new_sample
    --
    ------------------------------------------------------------

    process(aclk)

        variable input_sample : unsigned(DATA_W-1 downto 0);
        variable old_sample   : unsigned(DATA_W-1 downto 0);

        variable input_ext : unsigned(ACC_W-1 downto 0);
        variable old_ext   : unsigned(ACC_W-1 downto 0);

        variable new_sum : unsigned(ACC_W-1 downto 0);

    begin

        if rising_edge(aclk) then

            if aresetn = '0' then

                delay_line <= (others => (others => '0'));

                wr_ptr      <= 0;
                running_sum <= (others => '0');

                out_data  <= (others => '0');
                out_valid <= '0';

            else

                ----------------------------------------------------
                -- Current output consumed without replacement
                ----------------------------------------------------

                if (out_valid = '1') and
                   (m_axis_tready = '1') then

                    out_valid <= '0';

                end if;


                ----------------------------------------------------
                -- New AXI sample accepted
                ----------------------------------------------------

                if (s_axis_tvalid = '1') and
                   (in_ready = '1') then

                    input_sample := unsigned(s_axis_tdata);

                    ------------------------------------------------
                    -- Read sample that is leaving the 80-sample
                    -- window
                    ------------------------------------------------

                    old_sample := delay_line(wr_ptr);


                    ------------------------------------------------
                    -- Extend both to full accumulator width
                    ------------------------------------------------

                    input_ext := resize(
                        input_sample,
                        ACC_W
                    );

                    old_ext := resize(
                        old_sample,
                        ACC_W
                    );


                    ------------------------------------------------
                    -- Full-precision sliding sum
                    ------------------------------------------------

                    new_sum :=
                        running_sum
                        - old_ext
                        + input_ext;

                    running_sum <= new_sum;


                    ------------------------------------------------
                    -- Store newest sample
                    ------------------------------------------------

                    delay_line(wr_ptr) <= input_sample;


                    ------------------------------------------------
                    -- Circular buffer pointer
                    ------------------------------------------------

                    if wr_ptr = TAPS-1 then

                        wr_ptr <= 0;

                    else

                        wr_ptr <= wr_ptr + 1;

                    end if;


                    ------------------------------------------------
                    -- Output full 71-bit result on 72-bit AXI bus
                    --
                    -- bit 71    = zero padding
                    -- bits 70:0 = full-precision sum
                    ------------------------------------------------

                    out_data(71) <= '0';

                    out_data(70 downto 0) <=
                        std_logic_vector(new_sum);

                    out_valid <= '1';

                end if;

            end if;

        end if;

    end process;

end architecture;