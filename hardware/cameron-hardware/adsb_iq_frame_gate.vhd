library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- VHDL-93. Pair decision[n] with IQ[n], then look back IQ_DELAY_SAMPLES.
-- Input IQ must start at the same sample index as the C/P decision stream.
-- Place an AXIS FIFO on the IQ bypass BEFORE this module to absorb the
-- correlator's clock latency. This module's history buffer handles preamble
-- lookback, independently of that FIFO's occupancy/latency.
entity adsb_iq_frame_gate is
    generic (
        IQ_DELAY_SAMPLES : positive := 89;
        FRAME_SAMPLES    : positive := 1300
    );
    port (
        aclk                 : in  std_logic;
        aresetn              : in  std_logic;
        s_axis_iq_tdata      : in  std_logic_vector(31 downto 0);
        s_axis_iq_tvalid     : in  std_logic;
        s_axis_iq_tready     : out std_logic;
        s_axis_detect_tdata  : in  std_logic_vector(7 downto 0);
        s_axis_detect_tvalid : in  std_logic;
        s_axis_detect_tready : out std_logic;
        m_axis_iq_tdata      : out std_logic_vector(31 downto 0);
        m_axis_iq_tvalid     : out std_logic;
        m_axis_iq_tready     : in  std_logic;
        m_axis_iq_tlast      : out std_logic;
        frame_active        : out std_logic;
        history_ready       : out std_logic
    );
end entity;

architecture rtl of adsb_iq_frame_gate is
    type history_type is array (0 to IQ_DELAY_SAMPLES-1) of
        std_logic_vector(31 downto 0);
    signal history : history_type;
    attribute ram_style : string;
    attribute ram_style of history : signal is "distributed";
    signal write_ptr : natural range 0 to IQ_DELAY_SAMPLES-1 := 0;
    signal filled : natural range 0 to IQ_DELAY_SAMPLES := 0;
    signal iq_hold : std_logic_vector(31 downto 0) := (others => '0');
    signal iq_valid, det_valid, det_hold : std_logic := '0';
    signal previous_detect, active : std_logic := '0';
    signal remaining : natural range 0 to FRAME_SAMPLES-1 := 0;
    signal out_data : std_logic_vector(31 downto 0) := (others => '0');
    signal out_valid, out_last : std_logic := '0';
begin
    s_axis_iq_tready <= (not iq_valid) and aresetn;
    s_axis_detect_tready <= (not det_valid) and aresetn;
    m_axis_iq_tdata <= out_data;
    m_axis_iq_tvalid <= out_valid;
    m_axis_iq_tlast <= out_last;
    frame_active <= active or out_valid;
    history_ready <= '1' when filled = IQ_DELAY_SAMPLES else '0';

    process(aclk)
        variable trigger : boolean;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                write_ptr <= 0;
                filled <= 0;
                iq_valid <= '0';
                det_valid <= '0';
                det_hold <= '0';
                previous_detect <= '0';
                active <= '0';
                remaining <= 0;
                out_valid <= '0';
                out_last <= '0';
                -- Do not reset history RAM: filled prevents unwritten reads.
            else
                if out_valid = '1' and m_axis_iq_tready = '1' then
                    out_valid <= '0';
                    out_last <= '0';
                end if;
                if iq_valid = '0' and s_axis_iq_tvalid = '1' then
                    iq_hold <= s_axis_iq_tdata;
                    iq_valid <= '1';
                end if;
                if det_valid = '0' and s_axis_detect_tvalid = '1' then
                    det_hold <= s_axis_detect_tdata(0);
                    det_valid <= '1';
                end if;
                if iq_valid = '1' and det_valid = '1' and
                   (out_valid = '0' or m_axis_iq_tready = '1') then
                    iq_valid <= '0';
                    det_valid <= '0';
                    trigger := det_hold = '1' and previous_detect = '0';
                    previous_detect <= det_hold;
                    -- Old value at this address is IQ[n-IQ_DELAY_SAMPLES].
                    history(write_ptr) <= iq_hold;
                    if write_ptr = IQ_DELAY_SAMPLES-1 then
                        write_ptr <= 0;
                    else
                        write_ptr <= write_ptr + 1;
                    end if;
                    if filled < IQ_DELAY_SAMPLES then
                        filled <= filled + 1;
                    else
                        if active = '1' or trigger then
                            out_data <= history(write_ptr);
                            out_valid <= '1';
                            out_last <= '0';
                            if active = '0' then
                                -- First sample of a new packet.
                                if FRAME_SAMPLES = 1 then
                                    out_last <= '1';
                                    active <= '0';
                                else
                                    active <= '1';
                                    remaining <= FRAME_SAMPLES-1;
                                end if;
                            elsif remaining = 1 then
                                out_last <= '1';
                                active <= '0';
                                remaining <= 0;
                            else
                                remaining <= remaining - 1;
                            end if;
                        end if;
                        -- Closed gate still consumes both inputs; drops IQ.
                        -- Trigger edges during an active packet are ignored.
                    end if;
                end if;
                -- Stalled output: out_data/out_last/out_valid stay unchanged.
            end if;
        end if;
    end process;
end architecture;
