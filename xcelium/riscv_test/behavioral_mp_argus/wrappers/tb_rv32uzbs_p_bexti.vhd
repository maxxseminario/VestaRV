entity tb_rv32uzbs_p_bexti is end tb_rv32uzbs_p_bexti;
architecture behavioral of tb_rv32uzbs_p_bexti is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxrv32uzbs-p-bexti.rcf");
end architecture;
