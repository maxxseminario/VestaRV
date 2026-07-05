entity tb_rv32um_p_remu is end tb_rv32um_p_remu;
architecture behavioral of tb_rv32um_p_remu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxrv32um-p-remu.rcf");
end architecture;
