-- i2c_master_tb.vhd
-- Testbench: I2C master + behavioural slave model (address 0x50)
library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity i2c_master_tb is
end entity i2c_master_tb;

architecture sim of i2c_master_tb is
    constant SLAVE_ADDR : std_logic_vector(6 downto 0) := "1010000";  -- 0x50
    constant SLAVE_RD   : std_logic_vector(7 downto 0) := x"A5";      -- byte slave returns

    signal clk, rst, start, rw : std_logic := '0';
    signal addr    : std_logic_vector(6 downto 0) := (others => '0');
    signal data_wr : std_logic_vector(7 downto 0) := (others => '0');
    signal data_rd : std_logic_vector(7 downto 0);
    signal busy, done, ack_err : std_logic;
    signal scl_o, sda_o : std_logic;
    signal scl, sda     : std_logic;      -- I2C bus (sda is open-drain, resolved)
    signal sda_slv      : std_logic := '1';  -- slave: 0 = pull low, 1 = release
    signal slave_rx     : std_logic_vector(7 downto 0) := x"00";
begin
    clk <= not clk after 5 ns;            -- 100 MHz

    -- open-drain bus with pull-up
    scl <= scl_o;
    sda <= '0' when sda_o = '0'   else 'Z';
    sda <= '0' when sda_slv = '0' else 'Z';
    sda <= 'H';

    dut : entity work.i2c_master
        generic map (QUARTER => 10)       -- SCL period = 40 clk = 400 ns
        port map (clk => clk, rst => rst, start => start, rw => rw,
                  addr => addr, data_wr => data_wr, data_rd => data_rd,
                  busy => busy, done => done, ack_err => ack_err,
                  scl_o => scl_o, sda_o => sda_o, sda_i => sda);

    -- Slave model
    slave : process
        variable sh, rx : std_logic_vector(7 downto 0);
    begin
        sda_slv <= '1';
        loop
            wait until falling_edge(sda) and to_x01(scl) = '1';   -- START
            for i in 7 downto 0 loop
                wait until rising_edge(scl);
                sh(i) := to_x01(sda);
            end loop;
            wait until falling_edge(scl);
            if sh(7 downto 1) = SLAVE_ADDR then
                sda_slv <= '0';                                   -- ACK address
                wait until falling_edge(scl);
                if sh(0) = '0' then                               -- master writes
                    sda_slv <= '1';
                    for i in 7 downto 0 loop
                        wait until rising_edge(scl);
                        rx(i) := to_x01(sda);
                    end loop;
                    wait until falling_edge(scl);
                    sda_slv <= '0';                               -- ACK data
                    wait until falling_edge(scl);
                    sda_slv <= '1';
                    slave_rx <= rx;
                else                                              -- master reads
                    for i in 7 downto 0 loop
                        sda_slv <= SLAVE_RD(i);
                        wait until falling_edge(scl);
                    end loop;
                    sda_slv <= '1';
                end if;
            end if;
        end loop;
    end process;

    -- Stimulus
    stim : process
    begin
        rst <= '1';
        wait for 100 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        -- TEST 1: write 0x3C to slave 0x50
        report "TEST 1: write 0x3C to slave 0x50";
        addr <= SLAVE_ADDR; rw <= '0'; data_wr <= x"3C";
        start <= '1'; wait until rising_edge(clk); start <= '0';
        wait until rising_edge(clk) and done = '1';
        if ack_err = '0' and slave_rx = x"3C" then
            report "TEST 1 PASSED";
        else
            report "TEST 1 FAILED" severity error;
        end if;
        wait for 2 us;

        -- TEST 2: read from slave 0x50 (expect 0xA5)
        report "TEST 2: read from slave 0x50";
        rw <= '1';
        start <= '1'; wait until rising_edge(clk); start <= '0';
        wait until rising_edge(clk) and done = '1';
        if ack_err = '0' and data_rd = SLAVE_RD then
            report "TEST 2 PASSED";
        else
            report "TEST 2 FAILED" severity error;
        end if;
        wait for 2 us;

        -- TEST 3: wrong address 0x30 -> expect NACK (ack_err = 1)
        report "TEST 3: wrong address 0x30, expect NACK";
        addr <= "0110000"; rw <= '0'; data_wr <= x"55";
        start <= '1'; wait until rising_edge(clk); start <= '0';
        wait until rising_edge(clk) and done = '1';
        if ack_err = '1' then
            report "TEST 3 PASSED";
        else
            report "TEST 3 FAILED" severity error;
        end if;
        wait for 2 us;

        report "SIMULATION FINISHED";
        finish;
    end process;
end architecture sim;