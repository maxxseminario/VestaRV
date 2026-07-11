entity tb_rv32uzba_p_sh2add is end tb_rv32uzba_p_sh2add;
architecture behavioral of tb_rv32uzba_p_sh2add is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xrv32uzba-p-sh2add.rcf");
end architecture;
