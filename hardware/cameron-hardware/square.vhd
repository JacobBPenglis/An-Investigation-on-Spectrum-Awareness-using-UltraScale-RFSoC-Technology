library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity square_signed is

    generic (
        DATA_WIDTH : positive := 32
    );

    port (
        aclk    : in  std_logic;
        aresetn : in  std_logic;

        -- Input AXI Stream
        s_axis_tdata  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;

        -- Output AXI Stream
        m_axis_tdata  : out std_logic_vector((2*DATA_WIDTH)-1 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic
    );

end square_signed;


architecture rtl of square_signed is

    signal out_data  : std_logic_vector((2*DATA_WIDTH)-1 downto 0)
                       := (others => '0');

    signal out_valid : std_logic := '0';

begin

    -- Make sure AXI TDATA width is byte aligned
    assert (DATA_WIDTH mod 8 = 0)
        report "DATA_WIDTH must be a multiple of 8"
        severity failure;


    -- AXI Stream handshake
    s_axis_tready <= not out_valid or m_axis_tready;

    m_axis_tdata  <= out_data;
    m_axis_tvalid <= out_valid;


    process(aclk)

        variable input_signed : signed(DATA_WIDTH-1 downto 0);

        variable product_signed :
            signed((2*DATA_WIDTH)-1 downto 0);

    begin

        if rising_edge(aclk) then

            if aresetn = '0' then

                out_data  <= (others => '0');
                out_valid <= '0';

            elsif out_valid = '0' or m_axis_tready = '1' then

                out_valid <= s_axis_tvalid;

                if s_axis_tvalid = '1' then

                    -- Interpret FIR output as signed two's complement
                    input_signed := signed(s_axis_tdata);

                    -- Signed N-bit × N-bit = signed 2N-bit
                    product_signed :=
                        input_signed * input_signed;

                    -- Square is always non-negative
                    out_data <= std_logic_vector(product_signed);

                end if;

            end if;

        end if;

    end process;

end rtl;