entity tb_rv32uzbb_p_zext_h is end tb_rv32uzbb_p_zext_h;
architecture behavioral of tb_rv32uzbb_p_zext_h is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32uzbb-p-zext_h.rcf");
end architecture;
