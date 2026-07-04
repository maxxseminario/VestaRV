entity tb_rv32uzbs_p_bclr is end tb_rv32uzbs_p_bclr;
architecture behavioral of tb_rv32uzbs_p_bclr is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32uzbs-p-bclr.rcf");
end architecture;
