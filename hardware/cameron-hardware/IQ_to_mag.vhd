library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity iq_to_power is
    port (
        aclk            : in  std_logic;
        aresetn         : in  std_logic;

        -- Input: Q[31:16] | I[15:0]
        s_axis_tdata    : in  std_logic_vector(31 downto 0);
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;

        -- Output: I^2 + Q^2
        m_axis_tdata    : out std_logic_vector(31 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic
    );
end iq_to_power;


architecture rtl of iq_to_power is

    signal out_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal out_valid : std_logic := '0';

begin

    -- Accept new data whenever output register is empty
    -- or the downstream device accepts the current sample.
    s_axis_tready <= '1'
        when (out_valid = '0' or m_axis_tready = '1')
        else '0';

    m_axis_tdata  <= out_data;
    m_axis_tvalid <= out_valid;


    process(aclk)

        variable i_val : signed(15 downto 0);
        variable q_val : signed(15 downto 0);

        variable i_sq  : unsigned(31 downto 0);
        variable q_sq  : unsigned(31 downto 0);

        variable power : unsigned(31 downto 0);

    begin
        if rising_edge(aclk) then

            if aresetn = '0' then

                out_data  <= (others => '0');
                out_valid <= '0';

            elsif (out_valid = '0' or m_axis_tready = '1') then

                out_valid <= s_axis_tvalid;

                if s_axis_tvalid = '1' then

                    -- Input format:
                    -- [31:16] = Q
                    -- [15:0]  = I
                    i_val := signed(s_axis_tdata(15 downto 0));
                    q_val := signed(s_axis_tdata(31 downto 16));

                    -- Square each signed int16
                    i_sq := unsigned(i_val * i_val);
                    q_sq := unsigned(q_val * q_val);

                    -- Magnitude squared / power
                    power := i_sq + q_sq;

                    out_data <= std_logic_vector(power);

                end if;

            end if;

        end if;
    end process;

end rtl;