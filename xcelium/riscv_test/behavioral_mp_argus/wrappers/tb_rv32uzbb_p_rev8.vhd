entity tb_rv32uzbb_p_rev8 is end tb_rv32uzbb_p_rev8;
architecture behavioral of tb_rv32uzbb_p_rev8 is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxrv32uzbb-p-rev8.rcf");
end architecture;
