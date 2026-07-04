entity tb_rv32uzbb_p_maxu is end tb_rv32uzbb_p_maxu;
architecture behavioral of tb_rv32uzbb_p_maxu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32uzbb-p-maxu.rcf");
end architecture;
