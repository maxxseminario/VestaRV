entity tb_rv32uzbb_p_sext_h is end tb_rv32uzbb_p_sext_h;
architecture behavioral of tb_rv32uzbb_p_sext_h is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32uzbb-p-sext_h.rcf");
end architecture;
