-- i2c_master.vhd
-- I2C Master (7-bit address, 1 byte per transaction, no clock stretching)
-- Lab 3, variant 11 (I2C, VHDL)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
    generic (
        QUARTER : positive := 125  -- clk cycles per 1/4 of SCL period
    );
    port (
        clk      : in  std_logic;                     -- system clock
        rst      : in  std_logic;                     -- synchronous reset, active high
        start    : in  std_logic;                     -- 1-cycle pulse: begin transaction
        rw       : in  std_logic;                     -- 0 = write, 1 = read
        addr     : in  std_logic_vector(6 downto 0);  -- slave address
        data_wr  : in  std_logic_vector(7 downto 0);  -- byte to write
        data_rd  : out std_logic_vector(7 downto 0);  -- byte read from slave
        busy     : out std_logic;                     -- transaction in progress
        done     : out std_logic;                     -- 1-cycle pulse: transaction finished
        ack_err  : out std_logic;                     -- 1 = slave did not ACK
        scl_o    : out std_logic;                     -- 0 = pull SCL low, 1 = release
        sda_o    : out std_logic;                     -- 0 = pull SDA low, 1 = release
        sda_i    : in  std_logic                      -- SDA bus value
    );
end entity i2c_master;

architecture rtl of i2c_master is
    type state_t is (S_IDLE, S_START, S_ADDR, S_ADDR_ACK,
                     S_WRITE, S_WR_ACK, S_READ, S_RD_NACK, S_STOP);
    signal state   : state_t := S_IDLE;
    signal phase   : unsigned(1 downto 0) := "00";   -- 4 phases per bit
    signal cnt     : natural range 0 to QUARTER - 1 := 0;
    signal tick    : std_logic;
    signal bit_cnt : natural range 0 to 7 := 7;
    signal tx_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal wr_r    : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal rw_r    : std_logic := '0';
    signal nack_r  : std_logic := '0';
    signal scl_r   : std_logic := '1';
    signal sda_r   : std_logic := '1';
begin
    scl_o <= scl_r;
    sda_o <= sda_r;
    tick  <= '1' when cnt = QUARTER - 1 else '0';

    process (clk)
    begin
        if rising_edge(clk) then
            done <= '0';
            if rst = '1' then
                state   <= S_IDLE;
                phase   <= "00";
                cnt     <= 0;
                scl_r   <= '1';
                sda_r   <= '1';
                busy    <= '0';
                ack_err <= '0';
                data_rd <= (others => '0');
            else
                -- quarter-period tick generator
                if state = S_IDLE or tick = '1' then
                    cnt <= 0;
                else
                    cnt <= cnt + 1;
                end if;

                if state = S_IDLE then
                    if start = '1' then
                        busy    <= '1';
                        ack_err <= '0';
                        rw_r    <= rw;
                        wr_r    <= data_wr;
                        tx_byte <= addr & rw;
                        phase   <= "00";
                        state   <= S_START;
                    end if;

                elsif tick = '1' then
                    case state is

                        when S_START =>   -- SDA falls while SCL = 1
                            case phase is
                                when "00" => sda_r <= '1'; scl_r <= '1'; phase <= "01";
                                when "01" => sda_r <= '0';               phase <= "10";
                                when "10" =>                             phase <= "11";
                                when others =>
                                    scl_r   <= '0';
                                    phase   <= "00";
                                    bit_cnt <= 7;
                                    state   <= S_ADDR;
                            end case;

                        when S_ADDR | S_WRITE =>   -- Tx: shift out 8 bits, MSB first
                            case phase is
                                when "00" => scl_r <= '0'; sda_r <= tx_byte(bit_cnt); phase <= "01";
                                when "01" => scl_r <= '1'; phase <= "10";
                                when "10" => phase <= "11";
                                when others =>
                                    scl_r <= '0';
                                    phase <= "00";
                                    if bit_cnt = 0 then
                                        if state = S_ADDR then
                                            state <= S_ADDR_ACK;
                                        else
                                            state <= S_WR_ACK;
                                        end if;
                                    else
                                        bit_cnt <= bit_cnt - 1;
                                    end if;
                            end case;

                        when S_ADDR_ACK | S_WR_ACK =>   -- slave ACK slot
                            case phase is
                                when "00" => scl_r <= '0'; sda_r <= '1'; phase <= "01";
                                when "01" => scl_r <= '1'; phase <= "10";
                                when "10" =>
                                    if sda_i = '0' then
                                        nack_r <= '0';
                                    else
                                        nack_r  <= '1';
                                        ack_err <= '1';
                                    end if;
                                    phase <= "11";
                                when others =>
                                    scl_r   <= '0';
                                    phase   <= "00";
                                    bit_cnt <= 7;
                                    if nack_r = '1' then
                                        state <= S_STOP;
                                    elsif state = S_ADDR_ACK then
                                        if rw_r = '0' then
                                            tx_byte <= wr_r;
                                            state   <= S_WRITE;
                                        else
                                            state   <= S_READ;
                                        end if;
                                    else
                                        state <= S_STOP;
                                    end if;
                            end case;

                        when S_READ =>   -- Rx: sample 8 bits from slave
                            case phase is
                                when "00" => scl_r <= '0'; sda_r <= '1'; phase <= "01";
                                when "01" => scl_r <= '1'; phase <= "10";
                                when "10" =>
                                    if sda_i = '0' then
                                        rx_byte(bit_cnt) <= '0';
                                    else
                                        rx_byte(bit_cnt) <= '1';
                                    end if;
                                    phase <= "11";
                                when others =>
                                    scl_r <= '0';
                                    phase <= "00";
                                    if bit_cnt = 0 then
                                        state <= S_RD_NACK;
                                    else
                                        bit_cnt <= bit_cnt - 1;
                                    end if;
                            end case;

                        when S_RD_NACK =>   -- master sends NACK (SDA released = 1)
                            case phase is
                                when "00" => scl_r <= '0'; sda_r <= '1'; phase <= "01";
                                when "01" => scl_r <= '1'; phase <= "10";
                                when "10" => phase <= "11";
                                when others =>
                                    scl_r   <= '0';
                                    data_rd <= rx_byte;
                                    phase   <= "00";
                                    state   <= S_STOP;
                            end case;

                        when S_STOP =>   -- SDA rises while SCL = 1
                            case phase is
                                when "00" => scl_r <= '0'; sda_r <= '0'; phase <= "01";
                                when "01" => scl_r <= '1'; phase <= "10";
                                when "10" => sda_r <= '1'; phase <= "11";
                                when others =>
                                    busy  <= '0';
                                    done  <= '1';
                                    phase <= "00";
                                    state <= S_IDLE;
                            end case;

                        when others =>
                            state <= S_IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;