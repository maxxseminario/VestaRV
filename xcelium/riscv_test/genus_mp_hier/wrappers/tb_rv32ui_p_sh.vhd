entity tb_rv32ui_p_sh is end tb_rv32ui_p_sh;
architecture behavioral of tb_rv32ui_p_sh is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxxrv32ui-p-sh.rcf");
end architecture;
