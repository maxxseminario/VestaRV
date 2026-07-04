entity tb_rv32uzbs_p_bset is end tb_rv32uzbs_p_bset;
architecture behavioral of tb_rv32uzbs_p_bset is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32uzbs-p-bset.rcf");
end architecture;
