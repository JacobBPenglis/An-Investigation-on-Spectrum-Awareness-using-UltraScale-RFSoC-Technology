library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- VHDL-93. Both input streams must contain one value per IQ sample, in order.
-- Fixed threshold: 16*C > (1/5)*15*P is exactly 16*C > 3*P.
-- Decision stream sends EVERY decision, including zeros; do not filter it.
entity adsb_fixed_detector is
    port (
        aclk                 : in  std_logic;
        aresetn              : in  std_logic;
        s_axis_c_tdata       : in  std_logic_vector(63 downto 0);
        s_axis_c_tvalid      : in  std_logic;
        s_axis_c_tready      : out std_logic;
        s_axis_p_tdata       : in  std_logic_vector(63 downto 0);
        s_axis_p_tvalid      : in  std_logic;
        s_axis_p_tready      : out std_logic;
        m_axis_detect_tdata  : out std_logic_vector(7 downto 0);
        m_axis_detect_tvalid : out std_logic;
        m_axis_detect_tready : in  std_logic;
        detect_high         : out std_logic
    );
end entity;

architecture rtl of adsb_fixed_detector is
    signal c_hold, p_hold : unsigned(63 downto 0) := (others => '0');
    signal c_valid, p_valid, out_valid : std_logic := '0';
    signal decision : std_logic := '0';
begin
    s_axis_c_tready <= (not c_valid) and aresetn;
    s_axis_p_tready <= (not p_valid) and aresetn;
    m_axis_detect_tvalid <= out_valid;
    m_axis_detect_tdata <= "0000000" & decision;
    detect_high <= decision and out_valid;

    process(aclk)
        variable c16, p3 : unsigned(67 downto 0);
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                c_valid <= '0';
                p_valid <= '0';
                out_valid <= '0';
                decision <= '0';
            else
                if out_valid = '1' and m_axis_detect_tready = '1' then
                    out_valid <= '0';
                end if;
                if c_valid = '0' and s_axis_c_tvalid = '1' then
                    c_hold <= unsigned(s_axis_c_tdata);
                    c_valid <= '1';
                end if;
                if p_valid = '0' and s_axis_p_tvalid = '1' then
                    p_hold <= unsigned(s_axis_p_tdata);
                    p_valid <= '1';
                end if;
                if c_valid = '1' and p_valid = '1' and
                   (out_valid = '0' or m_axis_detect_tready = '1') then
                    -- Widen BEFORE shifting/adding to preserve all uint64 bits.
                    c16 := shift_left(resize(c_hold, 68), 4);
                    p3 := shift_left(resize(p_hold, 68), 1) + resize(p_hold, 68);
                    if c16 > p3 then
                        decision <= '1';
                    else
                        decision <= '0';
                    end if;
                    out_valid <= '1';
                    c_valid <= '0';
                    p_valid <= '0';
                end if;
            end if;
        end if;
    end process;
end architecture;
