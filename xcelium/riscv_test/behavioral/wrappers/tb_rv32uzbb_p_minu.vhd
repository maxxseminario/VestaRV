entity tb_rv32uzbb_p_minu is end tb_rv32uzbb_p_minu;
architecture behavioral of tb_rv32uzbb_p_minu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32uzbb-p-minu.rcf");
end architecture;
