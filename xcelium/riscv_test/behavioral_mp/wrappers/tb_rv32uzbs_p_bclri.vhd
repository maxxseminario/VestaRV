entity tb_rv32uzbs_p_bclri is end tb_rv32uzbs_p_bclri;
architecture behavioral of tb_rv32uzbs_p_bclri is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32uzbs-p-bclri.rcf");
end architecture;
