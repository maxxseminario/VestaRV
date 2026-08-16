/* -----------------------------------------------------------------------------
   uart_bfm_pkg.vhd
   -----------------------------------------------------------------------------
   Bus-functional model for the UART peripheral's pad-level serial lines: capture a frame off the TX pad, drive a frame onto the RX pad.
   Use these when driving the peripheral's TX_OUT / RX_IN directly; TestbenchLibrary.vhd's UART helpers cover the full-MCU external TX/RX instead.
   bit_period is one UART bit time, 16*(BR+1) core clocks for this UART.
   For drive_rx, clk is the core clock the frame is aligned to: the start bit begins on a falling edge.
   Parity is psel XOR all data bits; corrupt_parity and good_stop inject error conditions.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;

package uart_bfm_pkg is

    -- Capture one frame off the TX pad.
    -- Self-syncs on the start bit and samples each bit at its centre; works for 8N1 and 8-data+parity.
    procedure uart_capture_tx(constant bit_period : in  time;
                              signal   tx         : in  std_logic;
                              parity_en : in  boolean;
                              data_o    : out std_logic_vector(7 downto 0);
                              parity_o  : out std_logic;
                              stop_o    : out std_logic);

    -- Drive one frame onto the RX pad.
    procedure uart_drive_rx(constant bit_period : in time;
                            signal   clk : in    std_logic;
                            signal   rx  : out   std_logic;
                            data           : in std_logic_vector(7 downto 0);
                            parity_en      : in boolean;
                            psel           : in std_logic;
                            corrupt_parity : in boolean;
                            good_stop      : in boolean);

end package uart_bfm_pkg;


package body uart_bfm_pkg is

    procedure uart_capture_tx(constant bit_period : in  time;
                              signal   tx         : in  std_logic;
                              parity_en : in  boolean;
                              data_o    : out std_logic_vector(7 downto 0);
                              parity_o  : out std_logic;
                              stop_o    : out std_logic) is
        variable d : std_logic_vector(7 downto 0);
    begin
        wait until tx = '0';                        -- start bit (mark falls to space)
        wait for bit_period + bit_period / 2;       -- centre of data bit 0
        for i in 0 to 7 loop                        -- LSB first
            d(i) := tx;
            wait for bit_period;
        end loop;
        if parity_en then
            parity_o := tx;
            wait for bit_period;
        else
            parity_o := '0';
        end if;
        stop_o := tx;
        data_o := d;
        -- Wait past the TX-complete flag settling so a following SR read sees the settled state.
        wait for 2 * bit_period;
    end procedure;

    procedure uart_drive_rx(constant bit_period : in time;
                            signal   clk : in    std_logic;
                            signal   rx  : out   std_logic;
                            data           : in std_logic_vector(7 downto 0);
                            parity_en      : in boolean;
                            psel           : in std_logic;
                            corrupt_parity : in boolean;
                            good_stop      : in boolean) is
        variable p : std_logic;
    begin
        -- Parity bit: the select value XORed with every data bit.
        p := psel;
        for i in 0 to 7 loop
            p := p xor data(i);
        end loop;
        if corrupt_parity then
            p := not p;
        end if;

        wait until clk = '0';               -- align to a falling clk edge
        rx <= '0';                          -- start bit
        wait for bit_period;
        for i in 0 to 7 loop                -- data, LSB first
            rx <= data(i);
            wait for bit_period;
        end loop;
        if parity_en then
            rx <= p;
            wait for bit_period;
        end if;
        if good_stop then
            rx <= '1';
        else
            rx <= '0';                      -- framing error
        end if;
        wait for bit_period;
        rx <= '1';                          -- back to idle
        wait for 2 * bit_period;            -- guard / let RCIF settle
    end procedure;

end package body uart_bfm_pkg;
