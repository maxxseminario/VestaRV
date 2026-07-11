entity tb_rv32uzbs_p_binv is end tb_rv32uzbs_p_binv;
architecture behavioral of tb_rv32uzbs_p_binv is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxrv32uzbs-p-binv.rcf");
end architecture;
