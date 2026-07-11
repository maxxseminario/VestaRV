entity tb_rv32uzbs_p_binvi is end tb_rv32uzbs_p_binvi;
architecture behavioral of tb_rv32uzbs_p_binvi is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxrv32uzbs-p-binvi.rcf");
end architecture;
