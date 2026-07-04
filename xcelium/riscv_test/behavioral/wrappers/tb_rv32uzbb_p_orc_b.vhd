entity tb_rv32uzbb_p_orc_b is end tb_rv32uzbb_p_orc_b;
architecture behavioral of tb_rv32uzbb_p_orc_b is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32uzbb-p-orc_b.rcf");
end architecture;
