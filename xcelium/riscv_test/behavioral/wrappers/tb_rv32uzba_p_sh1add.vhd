entity tb_rv32uzba_p_sh1add is end tb_rv32uzba_p_sh1add;
architecture behavioral of tb_rv32uzba_p_sh1add is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32uzba-p-sh1add.rcf");
end architecture;
