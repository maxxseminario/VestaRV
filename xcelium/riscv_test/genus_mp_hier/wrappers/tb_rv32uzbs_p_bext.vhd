entity tb_rv32uzbs_p_bext is end tb_rv32uzbs_p_bext;
architecture behavioral of tb_rv32uzbs_p_bext is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32uzbs-p-bext.rcf");
end architecture;
