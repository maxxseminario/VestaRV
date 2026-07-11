entity tb_rv32uzba_p_sh3add is end tb_rv32uzba_p_sh3add;
architecture behavioral of tb_rv32uzba_p_sh3add is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xrv32uzba-p-sh3add.rcf");
end architecture;
